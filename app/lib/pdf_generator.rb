require 'open-uri'
require "prawn/measurement_extensions"
require 'mini_magick'

module PdfGenerator
  def self.generate(cards)
    pdf = Prawn::Document.new(:page_size => "A4", :page_layout => :portrait)
    reset_cursor
    Rails.logger.info("Starting PDF generation with #{cards.size} unique images")
    
    cards.each_with_index do |(card_image_url, quantity), index|
      begin
        Rails.logger.info("Processing card #{index + 1}/#{cards.size}: #{card_image_url} (quantity: #{quantity})")
        Rails.logger.info("Image URL: #{card_image_url}")
        image = URI.open(card_image_url)
        quantity.times do |copy_num|
          Rails.logger.debug("Adding copy #{copy_num + 1}/#{quantity} of #{card_image_url}")
          add_image_to_pdf(image, pdf)
        end
        Rails.logger.info("Successfully processed: #{card_image_url}")
      rescue OpenURI::HTTPError => e
        Rails.logger.warn("Failed to fetch image (HTTP error): #{card_image_url} - #{e.message}")
        next
      rescue MiniMagick::Error => e
        Rails.logger.error("ImageMagick error processing: #{card_image_url}")
        Rails.logger.error("Error: #{e.class} - #{e.message}")
        raise e
      rescue StandardError => e
        Rails.logger.error("Unexpected error processing: #{card_image_url}")
        Rails.logger.error("Error: #{e.class} - #{e.message}")
        raise e
      end
    end
    
    Rails.logger.info("PDF generation completed successfully")
    pdf.render
  end

  def self.add_image_to_pdf(image, pdf)
    # Standard card size: 63x88mm
    card_width = 63.mm
    card_height = 88.mm
    
    # Read image with MiniMagick to handle AVIF and other formats
    img = MiniMagick::Image.read(image)
    
    # Convert AVIF or other unsupported formats to PNG for Prawn compatibility
    if img.type == "AVIF" || !["JPEG", "PNG", "JPG"].include?(img.type)
      img.format "png"
    end
    
    # Check if image needs rotation (wider than tall)
    needs_rotation = img.width > img.height
    
    if needs_rotation
      # Rotate the image 90 degrees
      img.rotate "90"
    end
    
    # Convert to blob for Prawn
    image_blob = StringIO.new(img.to_blob)
    pdf.image image_blob, width: card_width, at: [@@x_position, @@y_position]
    
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
