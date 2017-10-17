require "prawn/measurement_extensions"

module PdfGenerator
  def self.generate(cards)
    pdf = Prawn::Document.new(:page_size => "A4", :page_layout => :landscape)
    cards_url = "https://arkhamdb.com/bundles/cards/"
    reset_cursor
    cards.each do |id, quantity|

      begin
        image = open(cards_url + id + ".png")
      rescue OpenURI::HTTPError
        image = open(cards_url + id + ".jpg")
      end
      quantity.times { add_image_to_pdf(image, pdf) }
    end
    pdf.render
  end

  def self.add_image_to_pdf(image, pdf)
    pdf.image image, width: 2.5.send(:in), at: [@@x_position, @@y_position]
    if ((@@x_position += 182) > 700)
      @@x_position = 0
      if ((@@y_position -= 253) < 100)
        @@y_position = 520
        pdf.start_new_page
      end
    end
  end

  def self.reset_cursor
    @@y_position = 520
    @@x_position = 0
  end
end
