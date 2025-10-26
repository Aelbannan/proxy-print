require 'open-uri'
require "prawn/measurement_extensions"
require 'mini_magick'

module PdfGenerator
  def self.generate(cards)
    pdf = Prawn::Document.new(:page_size => "A4", :page_layout => :portrait, :margin => 0)

    @@card_width = Prawn::Measurement.mm2pt(63.mm)
    @@card_height = Prawn::Measurement.mm2pt(88.mm)
    @@card_x_margin = 30.5.pt
    @@card_y_start = 805.pt
    @@card_border_width = 8.pt
    
    reset_cursor
    Rails.logger.info("Starting PDF generation with #{cards.size} unique images")

    draw_lines(pdf)

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
    # Create new StringIO for each copy to avoid rewind issues
    blob_io = StringIO.new(image_blob)
    pdf.image blob_io, width: @@card_width, at: [@@x_position, @@y_position]
    
    # Spacing calculations for portrait A4: 3 cards across

    # card_width (63mm ≈ 178pt) + small margin
    if ((@@x_position += @@card_width + @@card_x_margin) > (@@card_x_margin + @@card_width * 2))
      # Draw a thin white line under the completed row before moving to next row
      line_y = @@y_position - @@card_height

      pdf.line_width @@card_border_width

      pdf.stroke do
        pdf.line [0, line_y], [pdf.bounds.right, line_y]
      end
      
      @@x_position = @@card_x_margin
      # card_height (88mm ≈ 249pt) + small margin
      if ((@@y_position -= @@card_height + @@card_y_margin) < 100)
        @@y_position = 805
        pdf.start_new_page
        draw_lines(pdf)
      end
    end
  end

  def self.reset_cursor
    @@y_position = 805  # Higher starting position for portrait
    @@x_position = 30.5
  end

  def self.draw_lines(pdf)    
    # Set line properties: white color and thin width
    pdf.line_width @@card_border_width
    
    # Draw vertical cutting lines
    pdf.stroke do
      pdf.line [30.5, 0], [30.5, 843]
    end
  
    pdf.stroke do
      pdf.line [208.5, 0], [208.5, 843]
    end
  
    pdf.stroke do
      pdf.line [386.5, 0], [386.5, 843]
    end

    pdf.stroke do
      pdf.line [564.5, 0], [564.5, 843]
    end
  end
end
