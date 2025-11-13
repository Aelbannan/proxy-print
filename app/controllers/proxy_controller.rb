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
end
