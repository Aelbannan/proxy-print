require 'open-uri'
require "prawn/measurement_extensions"
require 'mini_magick'

module PdfGenerator
  def self.generate(cards)
    pdf = Prawn::Document.new(:page_size => "A4", :page_layout => :portrait, :margin => 0)

    @@card_width = 63.mm
    @@card_height = 88.mm
    
    @@card_y_start = 815.pt
    @@card_border_width = 8.pt
    @@card_x_margin = (595.pt - (@@card_width * 3 + @@card_border_width * 2)) / 2
    
    reset_cursor
    Rails.logger.info("Starting PDF generation with #{cards.size} unique images")

    #draw_lines(pdf)

    cards.each_with_index do |(card_image_url, quantity), index|
      begin
        Rails.logger.info("Processing card #{index + 1}/#{cards.size}: #{card_image_url} (quantity: #{quantity})")
        image = URI.open(card_image_url)
        
        # Process image once and reuse the blob for all copies
        img = MiniMagick::Image.read(image)
        
        # Convert AVIF or other unsupported formats to PNG
        if img.type == "AVIF" || !["JPEG", "PNG", "JPG"].include?(img.type)
          img.format "png"
        end
        
        # Check if image needs rotation
        if img.width > img.height
          img.rotate "90"
        end
        
        # Convert to blob once
        image_blob = img.to_blob
        
        # Add all copies to PDF
        quantity.times do |copy_num|
          Rails.logger.debug("Adding copy #{copy_num + 1}/#{quantity} of #{card_image_url}")
          add_image_blob_to_pdf(image_blob, pdf)
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

  # Add a pre-processed image blob to the PDF
  def self.add_image_blob_to_pdf(image_blob, pdf)
    # Draw black border square that's card_border_width bigger in each direction
    border_x = @@x_position - @@card_border_width
    border_y = @@y_position + @@card_border_width
    border_width = @@card_width + (@@card_border_width * 2)
    border_height = @@card_height + (@@card_border_width * 2)
    
    pdf.fill_color "000000"
    pdf.fill_rectangle [border_x, border_y], border_width, border_height
    
    # Create new StringIO for each copy to avoid rewind issues
    blob_io = StringIO.new(image_blob)
    pdf.image blob_io, width: @@card_width, at: [@@x_position, @@y_position]
    
    # Spacing calculations for portrait A4: 3 cards across

    # card_width (63mm ≈ 178pt) + small margin
    if ((@@x_position += @@card_width + @@card_border_width) > (@@card_x_margin + (@@card_width + @@card_border_width) * 2))
      @@x_position = @@card_x_margin
      # card_height (88mm ≈ 249pt) + small margin
      if ((@@y_position -= @@card_height + @@card_border_width) < 100)
        @@y_position = @@card_y_start
        pdf.start_new_page
        #draw_lines(pdf)
      end
    end
  end

  def self.reset_cursor
    @@y_position = @@card_y_start  # Higher starting position for portrait
    @@x_position = @@card_x_margin
  end

  def self.draw_lines(pdf)    
    # Set line properties: white color and thin width
    pdf.line_width @@card_border_width
    
    # Draw vertical cutting lines
    pdf.stroke do
      pdf.line [@@card_x_margin + @@card_border_width/2, 0], [@@card_x_margin + @@card_border_width/2, 843]
    end
  
    pdf.stroke do
      pdf.line [@@card_x_margin + (@@card_width + @@card_border_width) + @@card_border_width/2, 0], [@@card_x_margin + (@@card_width + @@card_border_width) + @@card_border_width/2, 843]
    end
  
    pdf.stroke do
      pdf.line [@@card_x_margin + (@@card_width + @@card_border_width) * 2 + @@card_border_width/2, 0], [@@card_x_margin + (@@card_width + @@card_border_width) * 2 + @@card_border_width/2, 843]
    end

    pdf.stroke do
      pdf.line [@@card_x_margin + (@@card_width + @@card_border_width) * 3 + @@card_border_width/2, 0], [@@card_x_margin + (@@card_width + @@card_border_width) * 3 + @@card_border_width/2, 843]
    end
  end
end
