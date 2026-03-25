# frozen_string_literal: true

require_relative "pura/gif/version"
require_relative "pura/gif/image"
require_relative "pura/gif/decoder"
require_relative "pura/gif/encoder"

module Pura
  module Gif
    def self.decode(input)
      Decoder.decode(input)
    end

    def self.encode(image, output_path, max_colors: 256)
      Encoder.encode(image, output_path, max_colors: max_colors)
    end
  end
end
