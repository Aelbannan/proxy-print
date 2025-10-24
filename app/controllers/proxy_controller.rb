class ProxyController < ApplicationController
  def show
    render 'show'
  end

  def new
    # Handle both deck IDs and direct card IDs
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
    else
      flash.alert = "Please provide either a deck ID or card IDs"
      render :show and return
    end
    
    send_data PdfGenerator.generate(cards), filename: "cards.pdf"
  rescue => ex
    Rails.logger.error(ex)
    flash.alert = "Error generating PDF: #{ex.message}"
    render :show
  end

  def card_ids(deck_id)
    decklist_api = "https://arkhamdb.com/api/public/decklist/"
    HTTParty.get(decklist_api + deck_id)["slots"].compact.reject {|id, quantity| id == "01000"}
  end

  def card_image_url(card_id)
    card_api = "https://arkhamdb.com/api/public/card/"
    "https://arkhamdb.com" + HTTParty.get(card_api + card_id)["imagesrc"]
  end

  def get_card_images(card_id)
    card_api = "https://arkhamdb.com/api/public/card/"
    card_data = HTTParty.get(card_api + card_id)
    
    images = []
    # Add front image
    images << "https://assets.arkham.build/optimized/#{card_data["code"]}.avif"
    
    # If card is double-sided, add backside image
    if card_data["double_sided"] == true && card_data["backimagesrc"]
      images << "https://assets.arkham.build/optimized/#{card_data["code"]}b.avif"
    end
    
    images
  end
end
