require 'open-uri'
require "prawn/measurement_extensions"
require 'mini_magick'

module PdfGenerator
  def self.generate(cards)
    pdf = Prawn::Document.new(:page_size => "A4", :page_layout => :portrait, :margin => 0)

    @@card_width = 63.mm
    @@card_height = 88.mm
    
    @@card_y_start = 815.pt
    @@card_space_between = 3.6.pt # 80px/1200 px per inch * 72 pn per inch
    @@card_bleed_size = 1.2.pt # 10px/1200 px per inch * 72 pn per inch
    @@card_x_margin = (595.pt - (@@card_width * 3 + @@card_space_between * 2 + @@card_bleed_size * 6)) / 2
    
    # URLs for generic card backs
    @@mythos_back_url = "https://hallofarkham.com/wp-content/uploads/2021/12/bleed2.png?strip=info&w=850"
    @@player_back_url = "https://hallofarkham.com/wp-content/uploads/2021/12/bleed1.png?strip=info&w=850"

    
    
    Rails.logger.info("Starting PDF generation with #{cards.size} cards")
    
    # Process cards in groups of 9 (one page of fronts, one page of backs)
    cards.each_slice(9).with_index do |card_batch, batch_index|
      Rails.logger.info("Processing batch #{batch_index + 1}: #{card_batch.size} cards")
      
      # Start new page for this batch (except for first batch)
      pdf.start_new_page if batch_index > 0
      draw_lines(pdf)
      
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
      draw_lines(pdf)
      
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
    
    x_offset = 0
    # Crop single-sided cards to 827px width (centered)
    unless double_sided
      current_width = img.width
      if current_width > 827
        # Calculate offset to center the crop
        x_offset = (current_width - 827) / 2
        img.crop "827x#{img.height}+#{x_offset}x0"  
        Rails.logger.info("Cropped single-sided card from #{current_width}px to 827px width")
      end
    end
    
    Rails.logger.info("Image width: #{img.width}, height: #{img.height}")

    # Extract 1px edge strips for bleed
    width = img.width
    height = img.height
    
    # Top edge (1px high strip)
    top_edge = MiniMagick::Image.open(img.path)
    top_edge.crop "#{width}x1+#{x_offset}+0"
    
    # Bottom edge (1px high strip)
    bottom_edge = MiniMagick::Image.open(img.path)
    bottom_edge.crop "#{width}x1+#{x_offset}+#{height - 1}"
    
    # Left edge (1px wide strip)
    left_edge = MiniMagick::Image.open(img.path)
    left_edge.crop "1x#{height}+#{x_offset}+0"
    
    # Right edge (1px wide strip)
    right_edge = MiniMagick::Image.open(img.path)
    right_edge.crop "1x#{height}+#{width - 1 + x_offset}+0"
    
    # Convert main image and edges to blobs
    image_blob = img.to_blob
    top_blob = top_edge.to_blob
    bottom_blob = bottom_edge.to_blob
    left_blob = left_edge.to_blob
    right_blob = right_edge.to_blob
    
    # Add to PDF with bleed edges
    add_image_blob_to_pdf_with_bleed(image_blob, top_blob, bottom_blob, left_blob, right_blob, pdf)
  end

  # Add image with mirrored edge bleed
  def self.add_image_blob_to_pdf_with_bleed(image_blob, top_blob, bottom_blob, left_blob, right_blob, pdf)
    # Main card image (no scaling)
    main_x = @@x_position + @@card_bleed_size
    main_y = @@y_position - @@card_bleed_size
    
    blob_io = StringIO.new(image_blob)
    pdf.image blob_io, width: @@card_width, height: @@card_height, at: [main_x, main_y]
    
    # Top bleed - stretch horizontally, height = bleed_size
    top_io = StringIO.new(top_blob)
    pdf.image top_io, width: @@card_width, height: @@card_bleed_size, at: [main_x, main_y + @@card_bleed_size]
    
    # Bottom bleed - stretch horizontally, height = bleed_size
    bottom_io = StringIO.new(bottom_blob)
    pdf.image bottom_io, width: @@card_width, height: @@card_bleed_size, at: [main_x, main_y - @@card_height]
    
    # Left bleed - stretch vertically, width = bleed_size
    left_io = StringIO.new(left_blob)
    pdf.image left_io, width: @@card_bleed_size, height: @@card_height, at: [main_x - @@card_bleed_size, main_y]
    
    # Right bleed - stretch vertically, width = bleed_size
    right_io = StringIO.new(right_blob)
    pdf.image right_io, width: @@card_bleed_size, height: @@card_height, at: [main_x + @@card_width, main_y]
    
    # Corner bleeds - use nearest edge pixel
    # Top-left corner
    top_left_io = StringIO.new(left_blob)
    pdf.image top_left_io, width: @@card_bleed_size, height: @@card_bleed_size, at: [main_x - @@card_bleed_size, main_y + @@card_bleed_size]
    
    # Top-right corner
    top_right_io = StringIO.new(right_blob)
    pdf.image top_right_io, width: @@card_bleed_size, height: @@card_bleed_size, at: [main_x + @@card_width, main_y + @@card_bleed_size]
    
    # Bottom-left corner
    bottom_left_io = StringIO.new(left_blob)
    pdf.image bottom_left_io, width: @@card_bleed_size, height: @@card_bleed_size, at: [main_x - @@card_bleed_size, main_y - @@card_height]
    
    # Bottom-right corner
    bottom_right_io = StringIO.new(right_blob)
    pdf.image bottom_right_io, width: @@card_bleed_size, height: @@card_bleed_size, at: [main_x + @@card_width, main_y - @@card_height]
    
    # Spacing calculations for portrait A4: 3 cards across
    # Move to next position after placing card
    if ((@@x_position += @@card_width + @@card_space_between + @@card_bleed_size * 2) > (@@card_x_margin + (@@card_width + @@card_space_between) * 2 + @@card_bleed_size * 6))
      # Move to start of next row
      @@x_position = @@card_x_margin
      @@y_position -= @@card_height + @@card_space_between + @@card_bleed_size * 2
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
      pdf.line [@@card_x_margin + @@card_bleed_size, 0], [@@card_x_margin + @@card_bleed_size, 843]
    end

    pdf.stroke do
      pdf.line [@@card_x_margin + (@@card_width) + @@card_bleed_size, 0], [@@card_x_margin + (@@card_width) + @@card_bleed_size, 843]
    end
  
    pdf.stroke do
      pdf.line [@@card_x_margin + (@@card_width + @@card_space_between ) + @@card_bleed_size * 3, 0], [@@card_x_margin + (@@card_width + @@card_space_between) + @@card_bleed_size * 3, 843]
    end

    pdf.stroke do
      pdf.line [@@card_x_margin + (@@card_width) * 2 + @@card_space_between + @@card_bleed_size * 3, 0], [@@card_x_margin + (@@card_width) * 2 + @@card_space_between + @@card_bleed_size * 3, 843]
    end
  
    pdf.stroke do
      pdf.line [@@card_x_margin + (@@card_width + @@card_space_between) * 2 + @@card_bleed_size * 5, 0], [@@card_x_margin + (@@card_width + @@card_space_between) * 2 + @@card_bleed_size * 5, 843]
    end

    pdf.stroke do
      pdf.line [@@card_x_margin + (@@card_width ) * 3 + @@card_space_between * 2 + @@card_bleed_size * 5, 0], [@@card_x_margin + (@@card_width ) * 3 + @@card_space_between * 2 + @@card_bleed_size * 5, 843]
    end

    # Draw horizontal cutting lines
    pdf.stroke do
      pdf.line [0, @@card_y_start - @@card_bleed_size], [595, @@card_y_start - @@card_bleed_size]
    end

    pdf.stroke do
      pdf.line [0, @@card_y_start - @@card_height - @@card_bleed_size], [595, @@card_y_start - @@card_height - @@card_bleed_size]
    end

    pdf.stroke do
      pdf.line [0, @@card_y_start - @@card_height - @@card_space_between - @@card_bleed_size * 3], [595, @@card_y_start - @@card_height - @@card_space_between - @@card_bleed_size * 3]
    end

    pdf.stroke do
      pdf.line [0, @@card_y_start - @@card_height * 2 - @@card_space_between - @@card_bleed_size * 3], [595, @@card_y_start - @@card_height * 2 - @@card_space_between - @@card_bleed_size * 3]
    end

    pdf.stroke do
      pdf.line [0, @@card_y_start - @@card_height * 2 - @@card_space_between * 2 - @@card_bleed_size * 5], [595, @@card_y_start - @@card_height * 2 - @@card_space_between * 2 - @@card_bleed_size * 5]
    end

    pdf.stroke do
      pdf.line [0, @@card_y_start - @@card_height * 3 - @@card_space_between * 2 - @@card_bleed_size * 5], [595, @@card_y_start - @@card_height * 3 - @@card_space_between * 2 - @@card_bleed_size * 5]
    end
  end
end
