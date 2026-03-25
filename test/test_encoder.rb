# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/pura-gif"

class TestEncoder < Minitest::Test
  TMP_DIR = File.join(__dir__, "tmp")

  def setup
    FileUtils.mkdir_p(TMP_DIR)
  end

  def teardown
    Dir.glob(File.join(TMP_DIR, "*")).each { |f| File.delete(f) }
    FileUtils.rm_f(TMP_DIR)
  end

  def test_encode_creates_valid_gif
    image = create_red_image(8, 8)
    path = File.join(TMP_DIR, "test_output.gif")
    size = Pura::Gif.encode(image, path)
    assert size.positive?
    assert File.exist?(path)

    # Verify GIF signature
    data = File.binread(path)
    assert_equal "GIF89a", data.byteslice(0, 6)
  end

  def test_encode_decode_roundtrip
    image = create_solid_image(16, 16, [128, 64, 200])
    path = File.join(TMP_DIR, "roundtrip.gif")
    Pura::Gif.encode(image, path)

    decoded = Pura::Gif.decode(path)
    assert_equal 16, decoded.width
    assert_equal 16, decoded.height
    # GIF is lossy due to quantization, but solid color should survive
    r, g, b = decoded.pixel_at(8, 8)
    assert_equal 128, r
    assert_equal 64, g
    assert_equal 200, b
  end

  def test_encode_decode_roundtrip_solid_colors
    [[255, 0, 0], [0, 255, 0], [0, 0, 255], [255, 255, 255], [0, 0, 0]].each do |color|
      pixels = color.pack("C3").b * (8 * 8)
      image = Pura::Gif::Image.new(8, 8, pixels)
      path = File.join(TMP_DIR, "solid_#{color.join("_")}.gif")
      Pura::Gif.encode(image, path)

      decoded = Pura::Gif.decode(path)
      r, g, b = decoded.pixel_at(4, 4)
      assert_equal color[0], r, "Red mismatch for #{color}"
      assert_equal color[1], g, "Green mismatch for #{color}"
      assert_equal color[2], b, "Blue mismatch for #{color}"
    end
  end

  def test_encode_preserves_few_colors
    # Image with exactly 4 colors should roundtrip perfectly
    pixels = String.new(encoding: Encoding::BINARY)
    colors = [[255, 0, 0], [0, 255, 0], [0, 0, 255], [255, 255, 0]]
    16.times do |y|
      16.times do |x|
        c = colors[((y / 8) * 2) + (x / 8)]
        pixels << c.pack("C3")
      end
    end
    image = Pura::Gif::Image.new(16, 16, pixels)
    path = File.join(TMP_DIR, "few_colors.gif")
    Pura::Gif.encode(image, path)

    decoded = Pura::Gif.decode(path)
    assert_equal [255, 0, 0], decoded.pixel_at(0, 0)
    assert_equal [0, 255, 0], decoded.pixel_at(8, 0)
    assert_equal [0, 0, 255], decoded.pixel_at(0, 8)
    assert_equal [255, 255, 0], decoded.pixel_at(8, 8)
  end

  def test_encode_various_sizes
    [[1, 1], [3, 5], [100, 1], [1, 100], [64, 64]].each do |w, h|
      pixels = "\x80\x80\x80".b * (w * h)
      image = Pura::Gif::Image.new(w, h, pixels)
      path = File.join(TMP_DIR, "size_#{w}x#{h}.gif")
      Pura::Gif.encode(image, path)

      decoded = Pura::Gif.decode(path)
      assert_equal w, decoded.width
      assert_equal h, decoded.height
    end
  end

  def test_encode_from_image_class
    image = Pura::Gif::Image.new(2, 2, "\xFF\x00\x00\x00\xFF\x00\x00\x00\xFF\xFF\xFF\xFF".b)
    path = File.join(TMP_DIR, "from_image.gif")
    Pura::Gif.encode(image, path)

    decoded = Pura::Gif.decode(path)
    assert_equal [255, 0, 0], decoded.pixel_at(0, 0)
    assert_equal [0, 255, 0], decoded.pixel_at(1, 0)
    assert_equal [0, 0, 255], decoded.pixel_at(0, 1)
    assert_equal [255, 255, 255], decoded.pixel_at(1, 1)
  end

  def test_encode_max_colors_option
    image = create_gradient_image(32, 32)
    path16 = File.join(TMP_DIR, "colors_16.gif")
    path256 = File.join(TMP_DIR, "colors_256.gif")

    Pura::Gif.encode(image, path16, max_colors: 16)
    Pura::Gif.encode(image, path256, max_colors: 256)

    # 16-color should be smaller or equal
    assert File.size(path16) <= File.size(path256)

    # Both should decode
    dec16 = Pura::Gif.decode(path16)
    dec256 = Pura::Gif.decode(path256)
    assert_equal 32, dec16.width
    assert_equal 32, dec256.width
  end

  private

  def create_red_image(w, h)
    pixels = "\xFF\x00\x00".b * (w * h)
    Pura::Gif::Image.new(w, h, pixels)
  end

  def create_solid_image(w, h, color)
    pixels = color.pack("C3").b * (w * h)
    Pura::Gif::Image.new(w, h, pixels)
  end

  def create_gradient_image(w, h)
    pixels = String.new(encoding: Encoding::BINARY, capacity: w * h * 3)
    h.times do |y|
      w.times do |x|
        r = (x * 255 / [w - 1, 1].max)
        g = (y * 255 / [h - 1, 1].max)
        b = 128
        pixels << r.chr << g.chr << b.chr
      end
    end
    Pura::Gif::Image.new(w, h, pixels)
  end
end
