# pura-gif

A pure Ruby GIF decoder/encoder with zero C extension dependencies.

Part of the **pura-*** series — pure Ruby image codec gems.

## Features

- GIF decoding (LZW decompression)
- GIF encoding with color quantization (median cut)
- Image resizing (bilinear / nearest-neighbor / fit / fill)
- No native extensions, no FFI, no external dependencies
- CLI tool included

## Installation

```bash
gem install pura-gif
```

## Usage

```ruby
require "pura-gif"

# Decode
image = Pura::Gif.decode("animation.gif")
image.width      #=> 400
image.height     #=> 400
image.pixels     #=> Raw RGB byte string
image.pixel_at(x, y) #=> [r, g, b]

# Encode (with color quantization)
Pura::Gif.encode(image, "output.gif")
Pura::Gif.encode(image, "output.gif", max_colors: 128)

# Resize
thumb = image.resize(200, 200)
fitted = image.resize_fit(800, 600)
```

## CLI

```bash
pura-gif decode input.gif --info
pura-gif resize input.gif --width 200 --height 200 --out thumb.gif
```

## Benchmark

400×400 image, Ruby 4.0.2 + YJIT.

### Decode

| Decoder | Time |
|---------|------|
| ffmpeg (C) | 65 ms |
| **pura-gif** | **77 ms** |

**pura-gif is within 1.2× of ffmpeg** for GIF decoding. No other pure Ruby GIF implementation exists.

### Encode

| Encoder | Time | Notes |
|---------|------|-------|
| **pura-gif** | **372 ms** | Includes color quantization |

## Why pure Ruby?

- **`gem install` and go** — no `brew install`, no `apt install`, no C compiler needed
- **Near-C speed** — GIF decode is within 1.2× of ffmpeg
- **Works everywhere Ruby works** — CRuby, ruby.wasm, JRuby, TruffleRuby
- **Part of pura-\*** — convert between JPEG, PNG, BMP, GIF, TIFF, WebP seamlessly

## Related gems

| Gem | Format | Status |
|-----|--------|--------|
| [pura-jpeg](https://github.com/komagata/pura-jpeg) | JPEG | ✅ Available |
| [pura-png](https://github.com/komagata/pura-png) | PNG | ✅ Available |
| [pura-bmp](https://github.com/komagata/pura-bmp) | BMP | ✅ Available |
| **pura-gif** | GIF | ✅ Available |
| [pura-tiff](https://github.com/komagata/pura-tiff) | TIFF | ✅ Available |
| [pura-ico](https://github.com/komagata/pura-ico) | ICO | ✅ Available |
| [pura-webp](https://github.com/komagata/pura-webp) | WebP | ✅ Available |
| [pura-image](https://github.com/komagata/pura-image) | All formats | ✅ Available |

## License

MIT
