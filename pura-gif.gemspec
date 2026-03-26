# frozen_string_literal: true

require_relative "lib/pura/gif/version"

Gem::Specification.new do |spec|
  spec.name = "pura-gif"
  spec.version = Pura::Gif::VERSION
  spec.authors = ["komagata"]
  spec.summary = "Pure Ruby GIF decoder/encoder"
  spec.description = "A pure Ruby GIF decoder and encoder with zero C extension dependencies. " \
                     "Supports LZW compression, color tables, transparency, and interlaced images."
  spec.homepage = "https://github.com/komagata/pure-gif"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.files = Dir["lib/**/*.rb", "bin/*", "LICENSE", "README.md"]
  spec.bindir = "bin"
  spec.executables = ["pura-gif"]

  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "rake", "~> 13.0"
end
