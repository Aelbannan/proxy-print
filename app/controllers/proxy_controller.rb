class ProxyController < ActionController::Base
  def show
  end

  def new
    /(?<id>\d+)/ =~ params[:id]
    cards = card_ids(id)
    send_data PdfGenerator.generate(cards), filename: "cards.pdf"
  end

  def card_ids(deck_id)
    link = "https://arkhamdb.com/api/public/decklist/"
    HTTParty.get(link + deck_id)["slots"].reject {|id, quantity| id == "01000"}
  end
end
