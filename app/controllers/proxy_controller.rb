class ProxyController < ActionController::Base
  def show
  end

  def new
    /(?<id>\d+)/ =~ params[:id]
    cards = card_ids(id).transform_keys { |card_id| card_image_url(card_id) }
    send_data PdfGenerator.generate(cards), filename: "cards.pdf"
  rescue
    flash.alert = "Deck not found"
    render :show
  end

  def card_ids(deck_id)
    decklist_api = "https://arkhamdb.com/api/public/decklist/"
    HTTParty.get(decklist_api + deck_id)["slots"].reject {|id, quantity| id == "01000"}
  end

  def card_image_url(card_id)
    card_api = "https://arkhamdb.com/api/public/card/"
    "https://arkhamdb.com" + HTTParty.get(card_api + card_id)["imagesrc"]
  end
end
