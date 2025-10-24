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
        cards = card_ids(id).transform_keys { |card_id| get_card_images(card_id) }.flatten(1)
      elsif params[:card_ids]
        # Direct card IDs (comma-separated or array)
        card_id_list = params[:card_ids].is_a?(String) ? params[:card_ids].split(',').map(&:strip) : params[:card_ids]
        # Build a hash of card_id => quantity (using same structure as deck endpoint)
        card_hash = Hash.new(0)
        card_id_list.each { |card_id| card_hash[card_id] += 1 }
        # Get card images including backsides for double-sided cards
        cards = card_hash.flat_map { |card_id, quantity| 
          get_card_images(card_id).map { |img_url| [img_url, quantity] }
        }.to_h
      elsif params[:pack_code]
        # Pack code
        pack_code = params[:pack_code].strip
        cards = pack_cards(pack_code)
      else
        flash.now[:alert] = "Please provide a deck ID, card IDs, or pack code"
        render :show and return
      end
      
      send_data PdfGenerator.generate(cards), filename: "cards.pdf"
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

  # Shared function to convert card data to image URLs
  # Takes already-fetched card data and returns array of image URLs
  def card_data_to_image_urls(card_data)
    if card_data.nil? || card_data["code"].nil?
      Rails.logger.error("Invalid card data received")
      return []
    end
    
    images = []
    # Add front image
    front_image = "https://assets.arkham.build/optimized/#{card_data["code"]}.avif"
    images << front_image
    Rails.logger.info("Card #{card_data["code"]}: Front image - #{front_image}")
    
    # If card is double-sided, add backside image
    if card_data["double_sided"] == true && card_data["backimagesrc"]
      back_image = "https://assets.arkham.build/optimized/#{card_data["code"]}b.avif"
      images << back_image
      Rails.logger.info("Card #{card_data["code"]}: Back image - #{back_image} (double-sided)")
    end
    
    Rails.logger.info("Card #{card_data["code"]}: Returning #{images.size} image(s)")
    images
  end

  # Fetch card by ID and return image URLs
  def get_card_images(card_id)
    Rails.logger.info("Fetching card data for: #{card_id}")
    card_api = "https://arkhamdb.com/api/public/card/"
    card_data = HTTParty.get(card_api + card_id)
    
    card_data_to_image_urls(card_data)
  end

  # Fetch entire pack and return card images with quantities
  # Pack API already returns all card data, so no need to fetch individually
  def pack_cards(pack_code)
    Rails.logger.info("Fetching pack data for: #{pack_code}")
    pack_api = "https://arkhamdb.com/api/public/cards/#{pack_code}"
    pack_data = HTTParty.get(pack_api)
    
    cards = {}
    pack_data.each do |card_data|
      # Get appropriate quantity: player cards get quantity, others get 1
      quantity = card_data["quantity"] || 1
      
      # Convert card data to image URLs using shared function (no extra API calls)
      card_data_to_image_urls(card_data).each do |img_url|
        cards[img_url] = quantity
      end
    end
    
    cards
  end
end
