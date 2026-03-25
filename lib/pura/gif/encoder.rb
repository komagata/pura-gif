# frozen_string_literal: true

module Pura
  module Gif
    class Encoder
      def self.encode(image, output_path, max_colors: 256)
        data = new(image, max_colors: max_colors).encode
        File.binwrite(output_path, data)
        data.bytesize
      end

      def initialize(image, max_colors: 256)
        @image = image
        @max_colors = [max_colors, 256].min
        @max_colors = 2 if @max_colors < 2
      end

      def encode
        # Quantize RGB pixels to a palette of at most @max_colors
        palette, indices = quantize(@image.pixels, @image.width, @image.height, @max_colors)

        # Pad palette to next power of 2 (minimum 4 entries for min_code_size >= 2)
        palette_bits = 1
        palette_bits += 1 while (1 << palette_bits) < palette.length
        palette_bits = 2 if palette_bits < 2
        palette_size = 1 << palette_bits

        palette << [0, 0, 0] while palette.length < palette_size

        min_code_size = palette_bits

        # LZW compress the indices
        compressed = lzw_compress(indices, min_code_size)

        # Build the GIF binary
        out = String.new(encoding: Encoding::BINARY)

        # Header
        out << "GIF89a"

        # Logical Screen Descriptor
        out << [@image.width, @image.height].pack("v2")
        packed = 0x80 | ((palette_bits - 1) << 4) | (palette_bits - 1)
        out << packed.chr << "\x00".b << "\x00".b

        # Global Color Table
        palette.each do |r, g, b|
          out << r.chr << g.chr << b.chr
        end

        # Image Descriptor
        out << "\x2C".b
        out << [0, 0, @image.width, @image.height].pack("v4")
        out << "\x00".b # packed: no local color table, not interlaced

        # Image Data
        out << min_code_size.chr

        # Write compressed data as sub-blocks (max 255 bytes each)
        pos = 0
        while pos < compressed.bytesize
          chunk_size = [compressed.bytesize - pos, 255].min
          out << chunk_size.chr
          out << compressed.byteslice(pos, chunk_size)
          pos += chunk_size
        end
        out << "\x00".b # block terminator

        # Trailer
        out << "\x3B".b

        out
      end

      private

      # Median cut color quantization
      def quantize(pixels, width, height, max_colors)
        total = width * height

        # Collect all unique colors with counts
        color_counts = Hash.new(0)
        offset = 0
        total.times do
          r = pixels.getbyte(offset)
          g = pixels.getbyte(offset + 1)
          b = pixels.getbyte(offset + 2)
          color_counts[[r, g, b]] += 1
          offset += 3
        end

        # If already <= max_colors, use them directly
        if color_counts.size <= max_colors
          palette = color_counts.keys
          color_to_index = {}
          palette.each_with_index { |c, i| color_to_index[c] = i }

          indices = Array.new(total)
          offset = 0
          total.times do |i|
            r = pixels.getbyte(offset)
            g = pixels.getbyte(offset + 1)
            b = pixels.getbyte(offset + 2)
            indices[i] = color_to_index[[r, g, b]]
            offset += 3
          end

          return [palette, indices]
        end

        # Median cut
        all_colors = color_counts.keys
        boxes = [all_colors]

        while boxes.length < max_colors
          # Find box with widest range to split
          best_box_idx = 0
          best_range = -1
          best_channel = 0

          boxes.each_with_index do |box, idx|
            next if box.length <= 1

            3.times do |ch|
              vals = box.map { |c| c[ch] }
              range = vals.max - vals.min
              next unless range > best_range

              best_range = range
              best_channel = ch
              best_box_idx = idx
            end
          end

          break if best_range <= 0

          box = boxes.delete_at(best_box_idx)
          box.sort_by! { |c| c[best_channel] }
          mid = box.length / 2
          boxes << box[0...mid]
          boxes << box[mid..]
        end

        # Compute palette as average of each box
        palette = boxes.map do |box|
          next [0, 0, 0] if box.empty?

          total_weight = 0
          sum_r = sum_g = sum_b = 0
          box.each do |c|
            w = color_counts[c]
            total_weight += w
            sum_r += c[0] * w
            sum_g += c[1] * w
            sum_b += c[2] * w
          end
          [(sum_r.to_f / total_weight).round, (sum_g.to_f / total_weight).round, (sum_b.to_f / total_weight).round]
        end

        # Map each pixel to nearest palette entry
        # Build a cache for speed
        cache = {}
        indices = Array.new(total)
        offset = 0
        total.times do |i|
          r = pixels.getbyte(offset)
          g = pixels.getbyte(offset + 1)
          b = pixels.getbyte(offset + 2)
          key = (r << 16) | (g << 8) | b

          idx = cache[key]
          unless idx
            best_dist = Float::INFINITY
            idx = 0
            palette.each_with_index do |pc, pi|
              dr = r - pc[0]
              dg = g - pc[1]
              db = b - pc[2]
              dist = (dr * dr) + (dg * dg) + (db * db)
              next unless dist < best_dist

              best_dist = dist
              idx = pi
              break if dist.zero?
            end
            cache[key] = idx
          end

          indices[i] = idx
          offset += 3
        end

        [palette, indices]
      end

      # LZW compression for GIF
      def lzw_compress(indices, min_code_size)
        clear_code = 1 << min_code_size
        eoi_code = clear_code + 1

        out = String.new(encoding: Encoding::BINARY)
        bit_buf = 0
        bit_count = 0

        flush_bits = lambda do |code, size|
          bit_buf |= code << bit_count
          bit_count += size
          while bit_count >= 8
            out << (bit_buf & 0xFF).chr
            bit_buf >>= 8
            bit_count -= 8
          end
        end

        # Initialize
        code_size = min_code_size + 1
        next_code = eoi_code + 1
        max_code_val = (1 << code_size)

        # String table: map [prefix_code, suffix] -> code
        table = {}

        # Emit clear code
        flush_bits.call(clear_code, code_size)

        return out if indices.empty?

        prefix = indices[0]

        i = 1
        len = indices.length
        while i < len
          suffix = indices[i]
          key = (prefix << 12) | suffix

          if table.key?(key)
            prefix = table[key]
          else
            # Output the code for prefix
            flush_bits.call(prefix, code_size)

            if next_code < 4096
              table[key] = next_code
              next_code += 1

              if next_code > max_code_val && code_size < 12
                code_size += 1
                max_code_val = 1 << code_size
              end
            else
              # Table full, emit clear code and reset
              flush_bits.call(clear_code, code_size)
              code_size = min_code_size + 1
              next_code = eoi_code + 1
              max_code_val = 1 << code_size
              table = {}
            end

            prefix = suffix
          end

          i += 1
        end

        # Output remaining prefix
        flush_bits.call(prefix, code_size)

        # Output EOI
        flush_bits.call(eoi_code, code_size)

        # Flush remaining bits
        out << (bit_buf & 0xFF).chr if bit_count.positive?

        out
      end
    end
  end
end
