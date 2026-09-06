# pura-gif

A pure Ruby GIF decoder/encoder without additional image-processing libraries.

Part of the **pura-*** series — pure Ruby image codec gems.

## Features

- GIF decoding (LZW decompression)
- GIF encoding with color quantization (median cut)
- Image resizing (bilinear / nearest-neighbor / fit / fill)
- No image-specific native extension or FFI dependency
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

These historical measurements include ffmpeg process startup. They do not compare against an in-process C codec or establish Rails pipeline throughput.

400×400 image, Ruby 4.0.2 + YJIT.

### Decode

| Decoder | Time |
|---------|------|
| ffmpeg (C) | 65 ms |
| **pura-gif** | **77 ms** |


### Encode

| Encoder | Time | vs ffmpeg | Notes |
|---------|------|-----------|-------|
| ffmpeg (C) | 59 ms | — | |
| **pura-gif** | **377 ms** | 6.4× slower | Includes color quantization |

## Why pure Ruby?

- **`gem install` and go** — no `brew install`, no `apt install`, no C compiler needed
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

## Pixel model and limitations

Images contain 8-bit RGB pixels. Only the first image is decoded, and encoding writes one image. Animation timing and subsequent frames are not preserved. Transparent pixels are flattened to a background color; the image model does not retain alpha.

`crop(x, y, width, height)` requires integer coordinates, positive dimensions, and a region entirely inside the image; invalid regions raise `ArgumentError`.

## License

MIT
