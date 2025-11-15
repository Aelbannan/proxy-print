class ProxyController < ApplicationController
  def show
    render 'show'
  end

  def new
    # Handle deck IDs, card IDs, and pack codes
    begin
      if params[:id]
        # Deck ID from URL
        /(?<id>\d+)/ =~ params[:id]
        deck_cards = card_ids(id)
        cards = []
        deck_cards.each do |card_id, quantity|
          metadata = get_card_metadata(card_id)
          if metadata
            quantity.times { cards << metadata }
          end
        end
      elsif params[:card_ids]
        # Direct card IDs (comma-separated or array)
        card_id_list = params[:card_ids].is_a?(String) ? params[:card_ids].split(',').map(&:strip) : params[:card_ids]
        # Build a hash of card_id => quantity
        card_hash = Hash.new(0)
        card_id_list.each { |card_id| card_hash[card_id] += 1 }
        # Get card metadata for each card
        cards = []
        card_hash.each do |card_id, quantity|
          metadata = get_card_metadata(card_id)
          if metadata
            quantity.times { cards << metadata }
          end
        end
      elsif params[:pack_code]
        # Pack code(s) - can be comma-separated
        pack_codes = params[:pack_code].split(',').map(&:strip)
        cards = []
        pack_codes.each do |pack_code|
          Rails.logger.info("Fetching pack: #{pack_code}")
          cards.concat(pack_cards(pack_code))
        end
        
        # Sort all cards after combining multiple packs: double-sided first, then mythos, then other factions
        cards.sort_by! do |card|
          [
            card[:double_sided] ? 0 : 1,                           # Double-sided cards first
            card[:faction] == "mythos" ? "0" : card[:faction] || "zzz"  # Mythos first, then alphabetically
          ]
        end
        Rails.logger.info("Final sort: #{cards.size} total cards sorted by double-sided, mythos first, then faction")
      else
        flash.now[:alert] = "Please provide a deck ID, card IDs, or pack code"
        render :show and return
      end
      
      # Convert card metadata to image URL pairs for PDF generation
      card_pairs = prepare_card_pairs(cards)
      
      send_data PdfGenerator.generate(card_pairs), filename: "cards.pdf"
    rescue MiniMagick::Error => ex
      Rails.logger.error("ImageMagick error: #{ex.class} - #{ex.message}")
      Rails.logger.error(ex.backtrace.first(10).join("\n"))
      flash.now[:alert] = "Image processing error. Check server logs for details."
      render :show
    rescue HTTParty::Error, SocketError, Errno::ECONNREFUSED => ex
      Rails.logger.error("Network error: #{ex.class} - #{ex.message}")
      flash.now[:alert] = "Network error: Cannot connect to ArkhamDB."
      render :show
    rescue StandardError => ex
      Rails.logger.error("Unexpected error: #{ex.class} - #{ex.message}")
      Rails.logger.error(ex.backtrace.first(10).join("\n"))
      flash.now[:alert] = "Error generating PDF. Check server logs."
      render :show
    end
  end

  def card_ids(deck_id)
    decklist_api = "https://arkhamdb.com/api/public/decklist/"
    HTTParty.get(decklist_api + deck_id)["slots"].compact.reject {|id, quantity| id == "01000"}
  end

  # Shared function to convert card data to card metadata
  # Returns hash with front image, back image (if double-sided), faction, and type
  def card_data_to_metadata(card_data)
    if card_data.nil? || card_data["code"].nil?
      Rails.logger.error("Invalid card data received")
      return nil
    end
    
    metadata = {
      front_image: "https://assets.arkham.build/optimized/#{card_data["code"]}.avif",
      double_sided: card_data["double_sided"] == true,
      faction: card_data["faction_code"] || "neutral",
      type: card_data["type_code"] || "unknown"
    }
    
    # If card is double-sided, include the back image
    if metadata[:double_sided] && card_data["backimagesrc"]
      metadata[:back_image] = "https://assets.arkham.build/optimized/#{card_data["code"]}b.avif"
    end
    
    Rails.logger.info("Card #{card_data["code"]}: #{metadata}")
    metadata
  end

  # Fetch card by ID and return metadata
  def get_card_metadata(card_id)
    Rails.logger.info("Fetching card data for: #{card_id}")
    card_api = "https://arkhamdb.com/api/public/card/"
    card_data = HTTParty.get(card_api + card_id)
    
    card_data_to_metadata(card_data)
  end

  # Fetch entire pack and return card metadata with quantities
  # Pack API already returns all card data, so no need to fetch individually
  def pack_cards(pack_code)
    Rails.logger.info("Fetching pack data for: #{pack_code}")
    pack_api = "https://arkhamdb.com/api/public/cards/#{pack_code}"
    pack_data = HTTParty.get(pack_api)
    
    cards = []
    pack_data.each do |card_data|
      # Get appropriate quantity: player cards get quantity, others get 1
      quantity = card_data["quantity"] || 1
      
      # Convert card data to metadata using shared function (no extra API calls)
      metadata = card_data_to_metadata(card_data)
      if metadata
        quantity.times { cards << metadata }
      end
    end
    
    # Sort cards: double-sided first, then mythos, then other factions
    cards.sort_by! do |card|
      [
        card[:double_sided] ? 0 : 1,                           # Double-sided cards first
        card[:faction] == "mythos" ? "0" : card[:faction] || "zzz"  # Mythos first, then alphabetically
      ]
    end
    
    Rails.logger.info("Sorted #{cards.size} cards: double-sided first, mythos first, then by faction")
    cards
  end

  # Convert Arkham Horror card metadata to generic card pairs for PDF generation
  # This method contains all game-specific logic for determining card backs
  def prepare_card_pairs(cards)
    # Generic card back URLs
    mythos_back_url = "https://hallofarkham.com/wp-content/uploads/2021/12/bleed2.png?strip=info&w=850"
    player_back_url = "https://hallofarkham.com/wp-content/uploads/2021/12/bleed1.png?strip=info&w=850"
    
    cards.map do |card|
      # Determine back image based on card properties
      back_url = if card[:double_sided] && card[:back_image]
        # Use specific back for double-sided cards
        card[:back_image]
      elsif card[:faction] == "mythos"
        # Use mythos generic back
        mythos_back_url
      else
        # Use player generic back
        player_back_url
      end
      
      # Return generic format: just front and back URLs
      {
        front: card[:front_image],
        back: back_url
      }
    end
  end

  # Netrunner card proxy generation
  def netrunner
    begin
      unless params[:card_list].present?
        flash.now[:alert] = "Please provide a card list"
        render :show and return
      end

      # Parse card list
      card_list = parse_netrunner_card_list(params[:card_list])
      
      # Fetch and match cards from NetrunnerDB
      cards = fetch_netrunner_cards(card_list)
      
      # Convert to card pairs
      card_pairs = prepare_netrunner_card_pairs(cards)
      
      send_data PdfGenerator.generate(card_pairs), filename: "netrunner_cards.pdf"
    rescue StandardError => ex
      Rails.logger.error("Netrunner error: #{ex.class} - #{ex.message}")
      Rails.logger.error(ex.backtrace.first(10).join("\n"))
      flash.now[:alert] = "Error generating Netrunner PDF. Check server logs."
      render :show
    end
  end

  # Netrunner pack proxy generation
  def netrunner_pack
    begin
      unless params[:pack_code].present?
        flash.now[:alert] = "Please provide a pack code"
        render :show and return
      end

      pack_code = params[:pack_code].strip
      
      # Fetch cards from pack
      cards = fetch_netrunner_pack_cards(pack_code)
      
      if cards.empty?
        flash.now[:alert] = "No cards found for pack code: #{pack_code}"
        render :show and return
      end
      
      # Convert to card pairs
      card_pairs = prepare_netrunner_card_pairs(cards)
      
      send_data PdfGenerator.generate(card_pairs), filename: "netrunner_#{pack_code}.pdf"
    rescue StandardError => ex
      Rails.logger.error("Netrunner pack error: #{ex.class} - #{ex.message}")
      Rails.logger.error(ex.backtrace.first(10).join("\n"))
      flash.now[:alert] = "Error generating Netrunner pack PDF. Check server logs."
      render :show
    end
  end

  private

  # Parse Netrunner card list in format "2x Card Title" or "2× Card Title"
  def parse_netrunner_card_list(card_list_text)
    parsed_cards = []
    
    card_list_text.each_line do |line|
      line = line.strip
      next if line.empty?
      
      # Match format: "2x Card Title", "2× Card Title", or just "Card Title"
      # Support both 'x' and '×' (multiplication sign)
      if line =~ /^(\d+)\s*[x×]\s*(.+)$/i
        quantity = $1.to_i
        title = $2.strip
      else
        quantity = 1
        title = line.strip
      end
      
      quantity.times { parsed_cards << title }
    end
    
    Rails.logger.info("Parsed #{parsed_cards.size} cards from input")
    parsed_cards
  end

  # Fetch cards from NetrunnerDB and match titles
  def fetch_netrunner_cards(card_titles)
    # Fetch all cards from NetrunnerDB
    netrunner_api = "https://netrunnerdb.com/api/2.0/public/cards"
    all_cards_data = HTTParty.get(netrunner_api)
    all_cards = all_cards_data["data"] || []
    
    Rails.logger.info("Fetched #{all_cards.size} cards from NetrunnerDB")
    
    cards = []
    card_titles.each do |title|
      card = find_best_netrunner_match(title, all_cards)
      if card
        # Use image_url if available, otherwise use fallback URL
        image_url = card["image_url"]
        if image_url.nil? && card["code"]
          image_url = "https://card-images.netrunnerdb.com/v2/xlarge/#{card["code"]}.webp"
          Rails.logger.info("Using fallback image URL for #{card["title"]} (#{card["code"]})")
        end
        
        if image_url
          cards << {
            title: card["title"],
            image_url: image_url,
            faction: card["faction_code"],
            side: card["side_code"]  # "corp" or "runner"
          }
        else
          Rails.logger.warn("No match or no image available for: #{title}")
        end
      else
        Rails.logger.warn("No match found for: #{title}")
      end
    end
    
    Rails.logger.info("Successfully matched #{cards.size} out of #{card_titles.size} cards")
    cards
  end

  # Find best matching card for a title
  def find_best_netrunner_match(search_title, all_cards)
    search_normalized = search_title.downcase.strip
    
    # Find all matching cards
    matches = all_cards.select do |card|
      card["title"]&.downcase&.include?(search_normalized) ||
      search_normalized.include?(card["title"]&.downcase || "")
    end
    
    return nil if matches.empty?
    
    # Filter out System Gateway cards unless explicitly requested
    unless search_title.include?("System Gateway")
      non_sg = matches.reject { |c| c["title"]&.include?("(System Gateway)") }
      matches = non_sg unless non_sg.empty?
    end
    
    # Sort by:
    # 1. Exact title match first
    # 2. Then by date (newer first) using card code
    # 3. Then by title similarity
    matches.sort_by do |card|
      card_title = card["title"]&.downcase || ""
      exact_match = (card_title == search_normalized) ? 0 : 1
      
      # Extract numeric part of code for rough date ordering (higher = newer)
      code_number = card["code"]&.scan(/\d+/)&.first&.to_i || 0
      date_sort = -code_number  # Negative for descending order
      
      # Calculate title similarity (Levenshtein distance approximation)
      title_diff = (card_title.length - search_normalized.length).abs
      
      [exact_match, date_sort, title_diff]
    end.first
  end

  # Fetch all cards from a Netrunner pack
  def fetch_netrunner_pack_cards(pack_code)
    # Fetch all cards
    netrunner_api = "https://netrunnerdb.com/api/2.0/public/cards"
    all_cards_data = HTTParty.get(netrunner_api)
    all_cards = all_cards_data["data"] || []
    
    Rails.logger.info("Fetched #{all_cards.size} cards from NetrunnerDB")
    
    # Filter by pack code
    pack_cards = all_cards.select { |card| card["pack_code"] == pack_code }
    
    Rails.logger.info("Found #{pack_cards.size} cards in pack #{pack_code}")
    
    cards = []
    pack_cards.each do |card|
      # Get quantity (usually 3 for player cards, 1 for identities)
      quantity = card["quantity"] || 1
      
      # Use image_url if available, otherwise use fallback URL
      image_url = card["image_url"]
      if image_url.nil? && card["code"]
        image_url = "https://card-images.netrunnerdb.com/v2/xlarge/#{card["code"]}.webp"
        Rails.logger.info("Using fallback image URL for #{card["title"]} (#{card["code"]})")
      end
      
      if image_url
        # Add card quantity times
        quantity.times do
          cards << {
            title: card["title"],
            image_url: image_url,
            faction: card["faction_code"],
            side: card["side_code"]
          }
        end
      else
        Rails.logger.warn("No image available for: #{card["title"]}")
      end
    end
    
    Rails.logger.info("Generated #{cards.size} total cards (with quantities) from pack")
    cards
  end

  # Convert Netrunner cards to card pairs with appropriate backs
  def prepare_netrunner_card_pairs(cards)
    cards.map do |card|
      # Determine back image based on side
      back_filename = case card[:side]
      when "corp"
        "Back Corp.png"
      when "runner"
        "Back Runner.png"
      else
        "Back Runner.png"  # Default to runner
      end
      
      # Use local file path directly (without file:// prefix)
      back_path = "#{Rails.root}/images/#{back_filename}"
      
      {
        front: card[:image_url],
        back: back_path
      }
    end
  end
end
