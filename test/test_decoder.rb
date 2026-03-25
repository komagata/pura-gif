# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/pura-gif"

class TestDecoder < Minitest::Test
  FIXTURE_DIR = File.join(__dir__, "fixtures")

  def setup
    generate_fixtures unless File.exist?(File.join(FIXTURE_DIR, "basic_4x4.gif"))
  end

  def test_decode_basic_4x4
    image = Pura::Gif.decode(File.join(FIXTURE_DIR, "basic_4x4.gif"))
    assert_equal 4, image.width
    assert_equal 4, image.height
    assert_equal 4 * 4 * 3, image.pixels.bytesize
    # Top-left pixel should be red
    r, g, b = image.pixel_at(0, 0)
    assert_equal 255, r
    assert_equal 0, g
    assert_equal 0, b
  end

  def test_decode_pixel_colors
    image = Pura::Gif.decode(File.join(FIXTURE_DIR, "basic_4x4.gif"))
    # Row 0: red
    assert_equal [255, 0, 0], image.pixel_at(0, 0)
    assert_equal [255, 0, 0], image.pixel_at(3, 0)
    # Row 1: green
    assert_equal [0, 255, 0], image.pixel_at(0, 1)
    # Row 2: blue
    assert_equal [0, 0, 255], image.pixel_at(0, 2)
    # Row 3: white
    assert_equal [255, 255, 255], image.pixel_at(0, 3)
  end

  def test_decode_from_binary_data
    data = File.binread(File.join(FIXTURE_DIR, "basic_4x4.gif"))
    image = Pura::Gif.decode(data)
    assert_equal 4, image.width
    assert_equal 4, image.height
  end

  def test_decode_to_rgb_array
    image = Pura::Gif.decode(File.join(FIXTURE_DIR, "basic_4x4.gif"))
    arr = image.to_rgb_array
    assert_equal 16, arr.length
    assert_equal [255, 0, 0], arr[0]
    assert_equal [0, 255, 0], arr[4]
    assert_equal [0, 0, 255], arr[8]
  end

  def test_decode_to_ppm
    image = Pura::Gif.decode(File.join(FIXTURE_DIR, "basic_4x4.gif"))
    ppm = image.to_ppm
    assert ppm.start_with?("P6\n4 4\n255\n".b)
    assert_equal "P6\n4 4\n255\n".bytesize + (4 * 4 * 3), ppm.bytesize
  end

  def test_pixel_at_out_of_bounds
    image = Pura::Gif.decode(File.join(FIXTURE_DIR, "basic_4x4.gif"))
    assert_raises(IndexError) { image.pixel_at(4, 0) }
    assert_raises(IndexError) { image.pixel_at(0, 4) }
    assert_raises(IndexError) { image.pixel_at(-1, 0) }
  end

  def test_decode_with_transparency
    image = Pura::Gif.decode(File.join(FIXTURE_DIR, "transparent.gif"))
    assert_equal 4, image.width
    assert_equal 4, image.height
    # Transparent pixels should default to white
    r, g, b = image.pixel_at(0, 0)
    assert_equal 255, r
    assert_equal 255, g
    assert_equal 255, b
    # Non-transparent pixel should be red
    r, g, b = image.pixel_at(0, 1)
    assert_equal 255, r
    assert_equal 0, g
    assert_equal 0, b
  end

  def test_decode_interlaced
    image = Pura::Gif.decode(File.join(FIXTURE_DIR, "interlaced.gif"))
    assert_equal 8, image.width
    assert_equal 8, image.height
    # Verify first row is red
    r, g, b = image.pixel_at(0, 0)
    assert_equal 255, r
    assert_equal 0, g
    assert_equal 0, b
  end

  def test_decode_large_palette
    image = Pura::Gif.decode(File.join(FIXTURE_DIR, "palette_256.gif"))
    assert_equal 16, image.width
    assert_equal 16, image.height
  end

  def test_invalid_input
    assert_raises(Pura::Gif::DecodeError) { Pura::Gif.decode("not a gif".b) }
  end

  def test_image_class_validation
    assert_raises(ArgumentError) { Pura::Gif::Image.new(2, 2, "\x00" * 10) }
  end

  private

  def generate_fixtures
    FileUtils.mkdir_p(FIXTURE_DIR)

    generate_basic_4x4
    generate_transparent
    generate_interlaced
    generate_palette_256
  end

  # Build a minimal GIF file from scratch
  def build_gif(width, height, palette, indices, interlace: false, transparent_index: nil)
    out = String.new(encoding: Encoding::BINARY)

    # Header
    out << "GIF89a"

    # Palette size (power of 2)
    palette_bits = 1
    palette_bits += 1 while (1 << palette_bits) < palette.length
    palette_bits = 2 if palette_bits < 2
    palette_size = 1 << palette_bits

    # Logical Screen Descriptor
    out << [width, height].pack("v2")
    packed = 0x80 | ((palette_bits - 1) << 4) | (palette_bits - 1)
    out << packed.chr << "\x00".b << "\x00".b

    # Global Color Table
    palette_size.times do |i|
      out << if i < palette.length
               palette[i].pack("C3")
             else
               "\x00\x00\x00".b
             end
    end

    # Graphics Control Extension (if transparency)
    if transparent_index
      out << "\x21\xF9\x04".b
      out << "\x01".b # packed: transparent flag set
      out << [0].pack("v") # delay
      out << transparent_index.chr
      out << "\x00".b
    end

    # Image Descriptor
    out << "\x2C".b
    out << [0, 0, width, height].pack("v4")
    interlace_flag = interlace ? 0x40 : 0x00
    out << interlace_flag.chr

    # Image Data (LZW)
    min_code_size = palette_bits
    compressed = lzw_compress_simple(indices, min_code_size)
    out << min_code_size.chr

    # Sub-blocks
    pos = 0
    while pos < compressed.bytesize
      chunk = [compressed.bytesize - pos, 255].min
      out << chunk.chr
      out << compressed.byteslice(pos, chunk)
      pos += chunk
    end
    out << "\x00".b

    # Trailer
    out << "\x3B".b

    out
  end

  def lzw_compress_simple(indices, min_code_size)
    clear_code = 1 << min_code_size
    eoi_code = clear_code + 1

    out = String.new(encoding: Encoding::BINARY)
    bit_buf = 0
    bit_count = 0

    emit = lambda do |code, size|
      bit_buf |= code << bit_count
      bit_count += size
      while bit_count >= 8
        out << (bit_buf & 0xFF).chr
        bit_buf >>= 8
        bit_count -= 8
      end
    end

    code_size = min_code_size + 1
    next_code = eoi_code + 1
    max_code_val = 1 << code_size
    table = {}

    emit.call(clear_code, code_size)

    return out if indices.empty?

    prefix = indices[0]
    i = 1
    while i < indices.length
      suffix = indices[i]
      key = (prefix << 12) | suffix

      if table.key?(key)
        prefix = table[key]
      else
        emit.call(prefix, code_size)

        if next_code < 4096
          table[key] = next_code
          next_code += 1
          if next_code > max_code_val && code_size < 12
            code_size += 1
            max_code_val = 1 << code_size
          end
        else
          emit.call(clear_code, code_size)
          code_size = min_code_size + 1
          next_code = eoi_code + 1
          max_code_val = 1 << code_size
          table = {}
        end

        prefix = suffix
      end
      i += 1
    end

    emit.call(prefix, code_size)
    emit.call(eoi_code, code_size)

    out << (bit_buf & 0xFF).chr if bit_count.positive?

    out
  end

  def generate_basic_4x4
    palette = [[255, 0, 0], [0, 255, 0], [0, 0, 255], [255, 255, 255]]
    indices = []
    # Row 0: red (0), Row 1: green (1), Row 2: blue (2), Row 3: white (3)
    4.times { indices << 0 }
    4.times { indices << 1 }
    4.times { indices << 2 }
    4.times { indices << 3 }

    data = build_gif(4, 4, palette, indices)
    File.binwrite(File.join(FIXTURE_DIR, "basic_4x4.gif"), data)
  end

  def generate_transparent
    palette = [[0, 0, 0], [255, 0, 0], [0, 255, 0], [0, 0, 255]]
    # Index 0 is transparent
    indices = []
    4.times { indices << 0 } # Row 0: transparent
    4.times { indices << 1 } # Row 1: red
    4.times { indices << 2 } # Row 2: green
    4.times { indices << 3 } # Row 3: blue

    data = build_gif(4, 4, palette, indices, transparent_index: 0)
    File.binwrite(File.join(FIXTURE_DIR, "transparent.gif"), data)
  end

  def generate_interlaced
    palette = [[255, 0, 0], [0, 255, 0], [0, 0, 255], [255, 255, 255]]
    # 8x8 image with row-based colors
    # Non-interlaced order: rows 0-7 with colors [0,1,2,3,0,1,2,3]
    row_colors = [0, 1, 2, 3, 0, 1, 2, 3]

    # Interlaced order: pass1 (0,8...), pass2 (4,8...), pass3 (2,4...), pass4 (1,2...)
    # For 8 rows: pass1: row 0; pass2: row 4; pass3: rows 2,6; pass4: rows 1,3,5,7
    interlaced_row_order = [0, 4, 2, 6, 1, 3, 5, 7]
    indices = []
    interlaced_row_order.each do |row|
      8.times { indices << row_colors[row] }
    end

    data = build_gif(8, 8, palette, indices, interlace: true)
    File.binwrite(File.join(FIXTURE_DIR, "interlaced.gif"), data)
  end

  def generate_palette_256
    palette = 256.times.map { |i| [i, (i * 2) & 0xFF, (i * 3) & 0xFF] }
    indices = 256.times.to_a # 16x16, each pixel a different palette index

    data = build_gif(16, 16, palette, indices)
    File.binwrite(File.join(FIXTURE_DIR, "palette_256.gif"), data)
  end
end
