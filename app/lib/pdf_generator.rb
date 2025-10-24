require 'open-uri'
require "prawn/measurement_extensions"
require 'mini_magick'

module PdfGenerator
  def self.generate(cards)
    pdf = Prawn::Document.new(:page_size => "A4", :page_layout => :portrait)
    reset_cursor
    cards.each do |card_image_url, quantity|
      begin
        image = URI.open(card_image_url)
      rescue OpenURI::HTTPError
        next
      end
      quantity.times { add_image_to_pdf(image, pdf) }
    end
    pdf.render
  end

  def self.add_image_to_pdf(image, pdf)
    # Standard card size: 63x88mm
    card_width = 63.mm
    card_height = 88.mm
    
    # Check if image needs rotation (wider than tall)
    img = MiniMagick::Image.read(image)
    needs_rotation = img.width > img.height
    
    if needs_rotation
      # Rotate the image 90 degrees
      img.rotate "90"
      rotated_image = StringIO.new(img.to_blob)
      pdf.image rotated_image, width: card_width, at: [@@x_position, @@y_position]
    else
      image.rewind  # Reset the file pointer
      pdf.image image, width: card_width, at: [@@x_position, @@y_position]
    end
    
    # Spacing calculations for portrait A4: 3 cards across
    # card_width (63mm ≈ 178pt) + small margin
    if ((@@x_position += 180) > 360)
      @@x_position = -5
      # card_height (88mm ≈ 249pt) + small margin
      if ((@@y_position -= 253) < 100)
        @@y_position = 785
        pdf.start_new_page
      end
    end
  end

  def self.reset_cursor
    @@y_position = 785  # Higher starting position for portrait
    @@x_position = -5
  end
end
