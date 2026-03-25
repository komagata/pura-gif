# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/pura-gif"

class TestResize < Minitest::Test
  TMP_DIR = File.join(__dir__, "tmp")

  def setup
    FileUtils.mkdir_p(TMP_DIR)
  end

  def teardown
    Dir.glob(File.join(TMP_DIR, "*")).each { |f| File.delete(f) }
    FileUtils.rm_f(TMP_DIR)
  end

  def test_resize_exact_dimensions
    image = create_test_image(100, 80)
    resized = image.resize(50, 40)
    assert_equal 50, resized.width
    assert_equal 40, resized.height
    assert_equal 50 * 40 * 3, resized.pixels.bytesize
  end

  def test_resize_upscale
    image = create_test_image(32, 32)
    resized = image.resize(64, 64)
    assert_equal 64, resized.width
    assert_equal 64, resized.height
  end

  def test_resize_nearest_neighbor
    image = create_test_image(100, 80)
    resized = image.resize(50, 40, interpolation: :nearest)
    assert_equal 50, resized.width
    assert_equal 40, resized.height
  end

  def test_resize_bilinear
    image = create_test_image(100, 80)
    resized = image.resize(50, 40, interpolation: :bilinear)
    assert_equal 50, resized.width
    assert_equal 40, resized.height
  end

  def test_resize_fit_landscape
    image = create_test_image(200, 100)
    fitted = image.resize_fit(100, 100)
    assert_equal 100, fitted.width
    assert_equal 50, fitted.height
  end

  def test_resize_fit_portrait
    image = create_test_image(100, 200)
    fitted = image.resize_fit(100, 100)
    assert_equal 50, fitted.width
    assert_equal 100, fitted.height
  end

  def test_resize_fit_already_fits
    image = create_test_image(50, 50)
    fitted = image.resize_fit(100, 100)
    assert_equal 50, fitted.width
    assert_equal 50, fitted.height
  end

  def test_resize_fill
    image = create_test_image(200, 100)
    filled = image.resize_fill(100, 100)
    assert_equal 100, filled.width
    assert_equal 100, filled.height
  end

  def test_resize_fill_portrait
    image = create_test_image(100, 200)
    filled = image.resize_fill(100, 100)
    assert_equal 100, filled.width
    assert_equal 100, filled.height
  end

  def test_resize_preserves_color
    pixels = "\xFF\x00\x00".b * (64 * 64)
    image = Pura::Gif::Image.new(64, 64, pixels)
    resized = image.resize(32, 32)

    r, g, b = resized.pixel_at(16, 16)
    assert_equal 255, r
    assert_equal 0, g
    assert_equal 0, b
  end

  def test_resize_and_encode_roundtrip
    image = create_test_image(64, 64)
    resized = image.resize(32, 32)
    out_path = File.join(TMP_DIR, "test_resized.gif")
    Pura::Gif.encode(resized, out_path)

    decoded = Pura::Gif.decode(out_path)
    assert_equal 32, decoded.width
    assert_equal 32, decoded.height
  end

  def test_resize_invalid_dimensions
    image = create_test_image(64, 64)
    assert_raises(ArgumentError) { image.resize(0, 10) }
    assert_raises(ArgumentError) { image.resize(10, 0) }
    assert_raises(ArgumentError) { image.resize(-1, 10) }
  end

  def test_resize_fit_invalid_dimensions
    image = create_test_image(64, 64)
    assert_raises(ArgumentError) { image.resize_fit(0, 10) }
    assert_raises(ArgumentError) { image.resize_fit(10, 0) }
  end

  private

  def create_test_image(width, height)
    pixels = String.new(encoding: Encoding::BINARY, capacity: width * height * 3)
    height.times do |y|
      width.times do |x|
        r = (x * 255 / [width - 1, 1].max)
        g = (y * 255 / [height - 1, 1].max)
        b = 128
        pixels << r.chr << g.chr << b.chr
      end
    end
    Pura::Gif::Image.new(width, height, pixels)
  end
end
