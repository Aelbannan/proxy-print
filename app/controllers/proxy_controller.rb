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
        card_api = "https://arkhamdb.com/api/public/card/"
        card_id_list.each { |card_id| card_hash[card_id] += 1 }
        # Get card images including backsides for double-sided cards
        cards = card_hash.flat_map { |card_id, quantity| 
          get_card_images(HTTParty.get(card_api + card_id)).map { |img_url| [img_url, quantity] }
        }.to_h
      elsif params[:pack_code]
        # Pack code
        pack_code = params[:pack_code].strip
        cards = pack_cards(pack_code)
      else
        flash.alert = "Please provide a deck ID, card IDs, or pack code"
        render :show and return
      end
      
      send_data PdfGenerator.generate(cards), filename: "cards.pdf"
    rescue MiniMagick::Error => ex
      Rails.logger.error("ImageMagick error: #{ex.class} - #{ex.message}")
      Rails.logger.error(ex.backtrace.first(10).join("\n"))
      flash.alert = "Image processing error: ImageMagick failed to process an image. This may be due to an unsupported image format (AVIF). Error: #{ex.message}"
      render :show
    rescue HTTParty::Error, SocketError, Errno::ECONNREFUSED => ex
      Rails.logger.error("Network error: #{ex.class} - #{ex.message}")
      flash.alert = "Network error: Failed to fetch data from ArkhamDB. Please check your internet connection. Error: #{ex.message}"
      render :show
    rescue StandardError => ex
      Rails.logger.error("Unexpected error: #{ex.class} - #{ex.message}")
      Rails.logger.error(ex.backtrace.first(10).join("\n"))
      flash.alert = "Error generating PDF: #{ex.class} - #{ex.message}"
      render :show
    end
  end

  def card_ids(deck_id)
    decklist_api = "https://arkhamdb.com/api/public/decklist/"
    HTTParty.get(decklist_api + deck_id)["slots"].compact.reject {|id, quantity| id == "01000"}
  end

  def card_image_url(card_data)
    card_api = "https://arkhamdb.com/api/public/card/"
    "https://arkhamdb.com" + HTTParty.get(card_api + card_id)["imagesrc"]
  end

  def get_card_images(card_id)
    
    if card_data.nil? || card_data["code"].nil?
      Rails.logger.error("Failed to fetch card data for: #{card_id}")
      raise StandardError, "Card #{card_id} not found or API returned invalid data"
    end
    
    images = []
    # Add front image
    front_image = "https://assets.arkham.build/optimized/#{card_data["code"]}.avif"
    images << front_image
    Rails.logger.info("Card #{card_id}: Front image - #{front_image}")
    
    # If card is double-sided, add backside image
    if card_data["double_sided"] == true && card_data["backimagesrc"]
      back_image = "https://assets.arkham.build/optimized/#{card_data["code"]}b.avif"
      images << back_image
      Rails.logger.info("Card #{card_id}: Back image - #{back_image} (double-sided)")
    end
    
    Rails.logger.info("Card #{card_id}: Returning #{images.size} image(s)")
    images
  end

  def pack_cards(pack_code)
    pack_api = "https://arkhamdb.com/api/public/cards/#{pack_code}"
    pack_data = HTTParty.get(pack_api)
    
    cards = {}
    pack_data.each do |card|
      # Get appropriate quantity: player cards get quantity, others get 1
      quantity = card["quantity"] || 1
      
      # Get card images (front and back if double-sided)
      get_card_images(card).each do |img_url|
        cards[img_url] = quantity
      end
    end
    
    cards
  end
end
