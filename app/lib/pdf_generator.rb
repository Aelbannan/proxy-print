require 'open-uri'
require "prawn/measurement_extensions"
require 'mini_magick'

module PdfGenerator
  def self.generate(cards)
    pdf = Prawn::Document.new(:page_size => "A4", :page_layout => :portrait, :margin => 0)

    @@card_width = 63.mm
    @@card_height = 88.mm
    
    @@card_y_start = 815.pt
    @@card_border_width = 0.pt
    @@card_x_margin = (595.pt - (@@card_width * 3 + @@card_border_width * 2)) / 2
    
    # URLs for generic card backs
    @@mythos_back_url = "https://hallofarkham.com/wp-content/uploads/2021/12/bleed2.png?strip=info&w=850"
    @@player_back_url = "https://hallofarkham.com/wp-content/uploads/2021/12/bleed1.png?strip=info&w=850"

    draw_lines(pdf)
    
    Rails.logger.info("Starting PDF generation with #{cards.size} cards")
    
    # Process cards in groups of 9 (one page of fronts, one page of backs)
    cards.each_slice(9).with_index do |card_batch, batch_index|
      Rails.logger.info("Processing batch #{batch_index + 1}: #{card_batch.size} cards")
      
      # Start new page for this batch (except for first batch)
      pdf.start_new_page if batch_index > 0
      
      # Generate fronts page
      reset_cursor
      card_batch.each_with_index do |card_metadata, card_index|
        begin
          Rails.logger.info("Processing front #{card_index + 1}/#{card_batch.size}")
          process_and_add_image(card_metadata[:front_image], pdf, card_metadata[:double_sided])
        rescue => e
          Rails.logger.error("Error processing front: #{e.message}")
          raise e
        end
      end
      
      # Start new page for backs
      pdf.start_new_page
      reset_cursor
      
      # Generate backs page - reverse order horizontally for double-sided printing
      # Reverse every 3 cards (each row) so they align when flipped
      reversed_batch = []
      card_batch.each_slice(3) do |row|
        reversed_batch.concat(row.reverse)
      end
      
      reversed_batch.each_with_index do |card_metadata, card_index|
        begin
          Rails.logger.info("Processing back #{card_index + 1}/#{card_batch.size}")
          
          # Determine which back image to use and whether it's from a double-sided card
          is_specific_back = card_metadata[:double_sided] && card_metadata[:back_image]
          
          back_image_url = if is_specific_back
            card_metadata[:back_image]
          elsif card_metadata[:faction] == "mythos"
            @@mythos_back_url
          else
            @@player_back_url
          end
          
          # Pass true for double_sided only if it's a specific back from a double-sided card
          process_and_add_image(back_image_url, pdf, is_specific_back)
        rescue => e
          Rails.logger.error("Error processing back: #{e.message}")
          raise e
        end
      end
    end
    
    Rails.logger.info("PDF generation completed successfully")
    pdf.render
  end
  
  def self.process_and_add_image(image_url, pdf, double_sided = true)
    image = URI.open(image_url)
    
    # Process image
    img = MiniMagick::Image.read(image)
    
    # Convert AVIF or other unsupported formats to PNG
    if img.type == "AVIF" || !["JPEG", "PNG", "JPG"].include?(img.type)
      img.format "png"
    end
    
    # Check if image needs rotation
    if img.width > img.height
      img.rotate "90"
    end
    
    # Crop single-sided cards to 827px width (centered)
    unless double_sided
      current_width = img.width
      if current_width > 827
        # Calculate offset to center the crop
        x_offset = (current_width - 827) / 2
        img.crop "827x#{img.height}+#{x_offset}+0"
        Rails.logger.info("Cropped single-sided card from #{current_width}px to 827px width")
      end
    end
    
    # Convert to blob
    image_blob = img.to_blob
    
    # Add to PDF
    add_image_blob_to_pdf(image_blob, pdf)
  end

  # Add a pre-processed image blob to the PDF
  def self.add_image_blob_to_pdf(image_blob, pdf)
    # Border settings
    border_width = 0.mm
    corner_radius = 4.mm
    
    # Shrink image by border width on each side
    image_width = @@card_width 
    image_height = @@card_height
    image_x = @@x_position + border_width
    image_y = @@y_position - border_width
    
    # Create new StringIO for each copy to avoid rewind issues
    blob_io = StringIO.new(image_blob)
    pdf.image blob_io, width: image_width, height: image_height, at: [image_x, image_y]
    
    # Draw 2mm black border with rounded corners around the full card area
    pdf.stroke_color "000000"
    pdf.line_width border_width
    #pdf.stroke_rounded_rectangle([@@x_position + border_width/2, @@y_position - border_width/2], @@card_width - border_width, @@card_height - border_width, corner_radius)
    
    # Spacing calculations for portrait A4: 3 cards across
    # Move to next position after placing card
    if ((@@x_position += @@card_width + @@card_border_width) > (@@card_x_margin + (@@card_width + @@card_border_width) * 2))
      # Move to start of next row
      @@x_position = @@card_x_margin
      @@y_position -= @@card_height + @@card_border_width
    end
  end

  def self.reset_cursor
    @@y_position = @@card_y_start  # Higher starting position for portrait
    @@x_position = @@card_x_margin
  end

  def self.draw_lines(pdf)    
    # Set line properties: white color and thin width
    pdf.line_width 0.1
    
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

    # Draw horizontal cutting lines
    pdf.stroke do
      pdf.line [0, @@card_y_start - @@card_border_width/2], [595, @@card_y_start - @@card_border_width/2]
    end

    pdf.stroke do
      pdf.line [0, @@card_y_start - @@card_border_width/2 - @@card_height], [595, @@card_y_start - @@card_border_width/2 - @@card_height]
    end

    pdf.stroke do
      pdf.line [0, @@card_y_start - @@card_border_width/2 - @@card_height * 2], [595, @@card_y_start - @@card_border_width/2 - @@card_height * 2]
    end

    pdf.stroke do
      pdf.line [0, @@card_y_start - @@card_border_width/2 - @@card_height * 3], [595, @@card_y_start - @@card_border_width/2 - @@card_height * 3]
    end
  end
end
