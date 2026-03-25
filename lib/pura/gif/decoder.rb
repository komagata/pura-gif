# frozen_string_literal: true

module Pura
  module Gif
    class DecodeError < StandardError; end

    class Decoder
      INTERLACE_PASSES = [
        [0, 8], # pass 1: every 8th row, starting at 0
        [4, 8], # pass 2: every 8th row, starting at 4
        [2, 4], # pass 3: every 4th row, starting at 2
        [1, 2] # pass 4: every 2nd row, starting at 1
      ].freeze

      def self.decode(input, transparency_color: [255, 255, 255])
        data = if input.is_a?(String) && input.encoding == Encoding::BINARY && input.start_with?("GIF")
                 input
               elsif input.is_a?(String) && File.exist?(input)
                 File.binread(input)
               elsif input.is_a?(String)
                 input.b
               else
                 raise DecodeError, "invalid input"
               end

        new(data, transparency_color: transparency_color).decode
      end

      def initialize(data, transparency_color: [255, 255, 255])
        @data = data
        @pos = 0
        @transparency_color = transparency_color
      end

      def decode
        read_header
        read_logical_screen_descriptor
        read_global_color_table if @gct_flag

        @transparent_index = nil

        # Read blocks until we find the first image
        loop do
          introducer = read_byte
          case introducer
          when 0x21 # Extension
            read_extension
          when 0x2C # Image Descriptor
            return read_image
          when 0x3B # Trailer
            raise DecodeError, "no image data found"
          else
            raise DecodeError, "unknown block type: 0x#{introducer.to_s(16)}"
          end
        end
      end

      private

      def read_byte
        raise DecodeError, "unexpected end of data" if @pos >= @data.bytesize

        b = @data.getbyte(@pos)
        @pos += 1
        b
      end

      def read_bytes(n)
        raise DecodeError, "unexpected end of data" if @pos + n > @data.bytesize

        bytes = @data.byteslice(@pos, n)
        @pos += n
        bytes
      end

      def read_u16
        lo = read_byte
        hi = read_byte
        (hi << 8) | lo
      end

      def read_header
        sig = read_bytes(3)
        ver = read_bytes(3)
        raise DecodeError, "not a GIF file" unless sig == "GIF"
        raise DecodeError, "unsupported GIF version: #{ver}" unless %w[89a 87a].include?(ver)
      end

      def read_logical_screen_descriptor
        @screen_width = read_u16
        @screen_height = read_u16
        packed = read_byte
        @bg_color_index = read_byte
        _pixel_aspect = read_byte

        @gct_flag = (packed >> 7) & 1 == 1
        @color_resolution = ((packed >> 4) & 0x07) + 1
        @gct_sort = (packed >> 3) & 1 == 1
        @gct_size = 2 << (packed & 0x07) if @gct_flag
      end

      def read_global_color_table
        @gct = read_color_table(@gct_size)
      end

      def read_color_table(size)
        table = Array.new(size)
        size.times do |i|
          r = read_byte
          g = read_byte
          b = read_byte
          table[i] = [r, g, b]
        end
        table
      end

      def read_extension
        label = read_byte
        case label
        when 0xF9 # Graphics Control Extension
          read_graphics_control_extension
        else
          # Skip unknown extensions (comment, application, plain text)
          skip_sub_blocks
        end
      end

      def read_graphics_control_extension
        block_size = read_byte
        raise DecodeError, "invalid GCE block size" unless block_size == 4

        packed = read_byte
        _delay = read_u16
        transparent_index = read_byte
        terminator = read_byte
        raise DecodeError, "missing GCE block terminator" unless terminator.zero?

        @disposal_method = (packed >> 2) & 0x07
        @transparent_flag = packed.allbits?(0x01)
        @transparent_index = transparent_index if @transparent_flag
      end

      def skip_sub_blocks
        loop do
          size = read_byte
          break if size.zero?

          @pos += size
        end
      end

      def read_image
        left = read_u16
        top = read_u16
        img_width = read_u16
        img_height = read_u16
        packed = read_byte

        lct_flag = (packed >> 7) & 1 == 1
        interlace = (packed >> 6) & 1 == 1
        lct_size = 2 << (packed & 0x07) if lct_flag

        color_table = if lct_flag
                        read_color_table(lct_size)
                      else
                        @gct || raise(DecodeError, "no color table available")
                      end

        # Read LZW data
        min_code_size = read_byte
        raise DecodeError, "invalid LZW minimum code size: #{min_code_size}" if min_code_size < 2 || min_code_size > 11

        # Collect all sub-block data
        compressed = String.new(encoding: Encoding::BINARY)
        loop do
          block_size = read_byte
          break if block_size.zero?

          compressed << read_bytes(block_size)
        end

        # LZW decompress
        indices = lzw_decompress(compressed, min_code_size, img_width * img_height)

        # De-interlace if needed
        indices = deinterlace(indices, img_width, img_height) if interlace

        # Build RGB pixels for the full screen
        pixels = String.new(encoding: Encoding::BINARY, capacity: @screen_width * @screen_height * 3)

        # Fill with background color
        bg = if @gct && @bg_color_index < @gct.length
               @gct[@bg_color_index]
             else
               [0, 0, 0]
             end
        (@screen_width * @screen_height).times do
          pixels << bg[0].chr << bg[1].chr << bg[2].chr
        end

        # Place the sub-image onto the canvas
        img_height.times do |row|
          img_width.times do |col|
            idx = indices[(row * img_width) + col]
            next unless idx

            canvas_x = left + col
            canvas_y = top + row
            next if canvas_x >= @screen_width || canvas_y >= @screen_height

            if @transparent_flag && idx == @transparent_index
              r, g, b = @transparency_color
            else
              color = color_table[idx]
              next unless color

              r, g, b = color
            end

            offset = ((canvas_y * @screen_width) + canvas_x) * 3
            pixels.setbyte(offset, r)
            pixels.setbyte(offset + 1, g)
            pixels.setbyte(offset + 2, b)
          end
        end

        Image.new(@screen_width, @screen_height, pixels)
      end

      def lzw_decompress(compressed, min_code_size, expected_pixels)
        clear_code = 1 << min_code_size
        eoi_code = clear_code + 1

        # Initialize code table
        code_size = min_code_size + 1
        next_code = eoi_code + 1
        max_code = 1 << code_size

        # Use arrays for the string table (prefix + suffix approach for speed)
        # table[code] = array of indices
        table = Array.new(next_code)
        clear_code.times { |i| table[i] = [i] }
        table[clear_code] = nil # clear
        table[eoi_code] = nil   # eoi

        output = Array.new(expected_pixels)
        out_pos = 0

        # Bit reader state
        bit_pos = 0
        data_len = compressed.bytesize

        prev_code = nil

        while out_pos < expected_pixels
          # Read next code of code_size bits
          byte_offset = bit_pos >> 3
          break if byte_offset >= data_len

          # Read up to 24 bits
          bits = compressed.getbyte(byte_offset)
          bits |= (compressed.getbyte(byte_offset + 1) || 0) << 8
          bits |= (compressed.getbyte(byte_offset + 2) || 0) << 16
          code = (bits >> (bit_pos & 7)) & ((1 << code_size) - 1)
          bit_pos += code_size

          if code == clear_code
            code_size = min_code_size + 1
            next_code = eoi_code + 1
            max_code = 1 << code_size
            # Reset table
            table = Array.new(next_code)
            clear_code.times { |i| table[i] = [i] }
            table[clear_code] = nil
            table[eoi_code] = nil
            prev_code = nil
            next
          end

          break if code == eoi_code

          if prev_code.nil?
            # First code after clear
            entry = table[code]
            break unless entry

            entry.each do |idx|
              output[out_pos] = idx
              out_pos += 1
              break if out_pos >= expected_pixels
            end
            prev_code = code
            next
          end

          if code < next_code && table[code]
            entry = table[code]
            entry.each do |idx|
              output[out_pos] = idx
              out_pos += 1
              break if out_pos >= expected_pixels
            end
            # Add to table: prev_entry + entry[0]
            if next_code < 4096
              prev_entry = table[prev_code]
              if prev_entry
                table[next_code] = prev_entry + [entry[0]]
                next_code += 1
              end
            end
          else
            # code == next_code (or unknown): special case
            prev_entry = table[prev_code]
            break unless prev_entry

            new_entry = prev_entry + [prev_entry[0]]
            new_entry.each do |idx|
              output[out_pos] = idx
              out_pos += 1
              break if out_pos >= expected_pixels
            end
            if next_code < 4096
              table[next_code] = new_entry
              next_code += 1
            end
          end

          if next_code >= max_code && code_size < 12
            code_size += 1
            max_code = 1 << code_size
          end

          prev_code = code
        end

        output
      end

      def deinterlace(indices, width, height)
        result = Array.new(width * height)
        src_row = 0

        INTERLACE_PASSES.each do |start_row, step|
          row = start_row
          while row < height
            width.times do |col|
              result[(row * width) + col] = indices[(src_row * width) + col]
            end
            src_row += 1
            row += step
          end
        end

        result
      end
    end
  end
end
