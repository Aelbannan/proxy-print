class ProxyController < ApplicationController
  def show
    render 'show'
  end

  def new
    # Handle both deck IDs and direct card IDs
    if params[:id]
      # Deck ID from URL
      /(?<id>\d+)/ =~ params[:id]
      cards = card_ids(id).transform_keys { |card_id| card_image_url(card_id) }
    elsif params[:card_ids]
      # Direct card IDs (comma-separated or array)
      card_id_list = params[:card_ids].is_a?(String) ? params[:card_ids].split(',').map(&:strip) : params[:card_ids]
      # Build a hash of card_id => quantity (using same structure as deck endpoint)
      card_hash = Hash.new(0)
      card_id_list.each { |card_id| card_hash[card_id] += 1 }
      # Transform keys to image URLs, just like the deck endpoint
      cards = card_hash.transform_keys { |card_id| card_image_url(card_id) }
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
end
