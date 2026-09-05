#!/usr/bin/env python3
"""Generate the GRUB theme's pixel-art logo from the master phaethon-logo.png.

WHY THIS EXISTS -- three separate problems, one asset.

1. GRUB CANNOT SHRINK AN IMAGE COMPONENT.
   theme.txt asked for `width = 180`, and the boot menu drew the logo at its
   natural 251px anyway. grub-core/gfxmenu/gui_canvas.c:104 clamps every
   component UP to its minimal size:

       comp->ops->get_minimal_size (comp, &mw, &mh);
       if (w < (signed) mw) w = mw;

   and image_get_minimal_size returns the raw bitmap's dimensions. So the
   declared width is a floor, never a ceiling.

2. THAT IS WHY THE LOGO SAT RIGHT OF CENTRE.
   `left = 50%-90` is only centred for a 180px-wide component. Rendered at
   251px the emblem's centre lands (251-180)/2 = 35.5px right of the screen
   centre -- which is exactly the offset visible on the v1.0.0-Belle boot menu.
   The art itself is fine: its opaque bounding box is 3..247 on both axes,
   dead centre in its own canvas.

3. THE HD ART CLASHED WITH THE REST OF THE MENU.
   Everything else on that screen is drawn in Unifont, a 16px bitmap face. A
   smooth 251px emblem next to pixel type reads as a mistake.

Emitting the logo pre-scaled to exactly 180x180 fixes all three: minimal size
now equals the declared width so nothing is clamped and the centring maths is
true, and gui_image.c takes its `self->bitmap = self->raw_bitmap` fast path
(rescale_image, gui_image.c:137) instead of resampling with
GRUB_VIDEO_BITMAP_SCALE_METHOD_BEST -- so the blocks we bake in here reach the
screen 1:1 rather than being bilinearly smoothed back into mush.

The pixelation is an ordinary box-downsample to 45x45 followed by a
nearest-neighbour 4x upscale, so each output block is one flat colour. RGB is
averaged weighted by alpha, otherwise transparent-black padding bleeds a dark
rim into every edge block.

No third-party imaging library: the build container is not guaranteed to have
Pillow or ImageMagick, and this runs rarely enough that a hand-rolled PNG
codec is cheaper than a dependency. Output is written to the theme directory
and committed, so the ISO build itself needs nothing.

Usage:  python3 tools/pixelate-logo.py [--blocks 45] [--size 180]
"""

import argparse
import struct
import sys
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "phaethon-logo.png"
DST = ROOT / "phaethon-iso" / "grub" / "themes" / "phaethon" / "logo.png"


def read_png(path):
    """Decode an 8-bit RGBA non-interlaced PNG to (width, height, bytearray)."""
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit(f"{path}: not a PNG")

    pos, idat, hdr = 8, [], None
    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos : pos + 4])
        ctype = data[pos + 4 : pos + 8]
        chunk = data[pos + 8 : pos + 8 + length]
        if ctype == b"IHDR":
            hdr = struct.unpack(">IIBBBBB", chunk)
        elif ctype == b"IDAT":
            idat.append(chunk)
        pos += 12 + length

    w, h, depth, colour, _, _, interlace = hdr
    if (depth, colour, interlace) != (8, 6, 0):
        raise SystemExit(
            f"{path}: need 8-bit RGBA, non-interlaced "
            f"(got depth={depth} colour={colour} interlace={interlace})"
        )

    raw = zlib.decompress(b"".join(idat))
    bpp, stride = 4, w * 4
    out = bytearray(w * h * 4)
    prev = bytearray(stride)
    off = 0
    for y in range(h):
        ftype = raw[off]
        off += 1
        line = bytearray(raw[off : off + stride])
        off += stride
        if ftype == 1:  # Sub
            for i in range(bpp, stride):
                line[i] = (line[i] + line[i - bpp]) & 255
        elif ftype == 2:  # Up
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 255
        elif ftype == 3:  # Average
            for i in range(stride):
                a = line[i - bpp] if i >= bpp else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 255
        elif ftype == 4:  # Paeth
            for i in range(stride):
                a = line[i - bpp] if i >= bpp else 0
                c = prev[i - bpp] if i >= bpp else 0
                b = prev[i]
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 255
        elif ftype != 0:
            raise SystemExit(f"{path}: unknown filter type {ftype} on row {y}")
        out[y * stride : (y + 1) * stride] = line
        prev = line
    return w, h, out


def write_png(path, w, h, px):
    """Encode 8-bit RGBA. Every row uses filter 0; zlib does the real work."""
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        raw += px[y * w * 4 : (y + 1) * w * 4]

    def chunk(tag, payload):
        return (
            struct.pack(">I", len(payload))
            + tag
            + payload
            + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF)
        )

    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )


def alpha_bbox(w, h, px, threshold=16):
    """Tightest box containing everything more opaque than `threshold`."""
    minx, miny, maxx, maxy = w, h, -1, -1
    for y in range(h):
        row = y * w * 4
        for x in range(w):
            if px[row + x * 4 + 3] > threshold:
                minx = min(minx, x)
                maxx = max(maxx, x)
                miny = min(miny, y)
                maxy = max(maxy, y)
    if maxx < 0:
        raise SystemExit("source image is fully transparent")
    return minx, miny, maxx, maxy


def downsample(w, h, px, box, blocks, threshold):
    """Box-average `box` down to blocks x blocks, weighting RGB by alpha, then
    snap each block's alpha to fully opaque or fully clear."""
    x0, y0, x1, y1 = box
    side = max(x1 - x0 + 1, y1 - y0 + 1)
    # Re-centre the content in a square window so a non-square bounding box
    # cannot shift the emblem off centre in the output.
    cx, cy = (x0 + x1 + 1) / 2, (y0 + y1 + 1) / 2
    left, top = cx - side / 2, cy - side / 2

    out = bytearray(blocks * blocks * 4)
    step = side / blocks
    for by in range(blocks):
        sy0, sy1 = top + by * step, top + (by + 1) * step
        for bx in range(blocks):
            sx0, sx1 = left + bx * step, left + (bx + 1) * step
            r = g = b = a = 0.0
            wsum = 0.0
            for sy in range(int(sy0), int(sy1) + 1):
                if sy < 0 or sy >= h:
                    continue
                # Fraction of this source row inside the block.
                cover_y = min(sy + 1, sy1) - max(sy, sy0)
                if cover_y <= 0:
                    continue
                for sx in range(int(sx0), int(sx1) + 1):
                    if sx < 0 or sx >= w:
                        continue
                    cover_x = min(sx + 1, sx1) - max(sx, sx0)
                    if cover_x <= 0:
                        continue
                    area = cover_x * cover_y
                    i = (sy * w + sx) * 4
                    sa = px[i + 3] / 255.0
                    r += px[i] * area * sa
                    g += px[i + 1] * area * sa
                    b += px[i + 2] * area * sa
                    a += px[i + 3] * area
                    wsum += area * sa
            o = (by * blocks + bx) * 4
            if wsum > 0:
                out[o] = min(255, round(r / wsum))
                out[o + 1] = min(255, round(g / wsum))
                out[o + 2] = min(255, round(b / wsum))
            total_area = step * step
            alpha = min(255, round(a / total_area)) if total_area else 0
            # Hard alpha. Partial coverage on the outline blocks would give the
            # emblem a soft halo against the flat black desktop-color, which is
            # the one thing that still reads as "smooth image scaled down".
            out[o + 3] = 255 if alpha >= threshold else 0
    return out


def upscale(blocks, px, factor):
    """Nearest-neighbour, so each source pixel becomes a hard factor x factor
    block. This is what makes the result read as pixel art rather than as a
    small smooth image."""
    size = blocks * factor
    out = bytearray(size * size * 4)
    for y in range(size):
        srow = (y // factor) * blocks * 4
        drow = y * size * 4
        for x in range(size):
            s = srow + (x // factor) * 4
            d = drow + x * 4
            out[d : d + 4] = px[s : s + 4]
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--blocks", type=int, default=45, help="pixel grid (default 45)")
    ap.add_argument("--size", type=int, default=180, help="output px (default 180)")
    ap.add_argument(
        "--alpha-threshold",
        type=int,
        default=128,
        help="block coverage at or above which a block is fully opaque, "
        "below which it is dropped entirely (default 128)",
    )
    ap.add_argument("--src", type=Path, default=SRC)
    ap.add_argument("--dst", type=Path, default=DST)
    args = ap.parse_args()

    if args.size % args.blocks:
        raise SystemExit(
            f"--size {args.size} must be a whole multiple of --blocks {args.blocks}, "
            "otherwise the blocks come out uneven"
        )
    factor = args.size // args.blocks

    w, h, px = read_png(args.src)
    box = alpha_bbox(w, h, px)
    small = downsample(w, h, px, box, args.blocks, args.alpha_threshold)
    big = upscale(args.blocks, small, factor)
    write_png(args.dst, args.size, args.size, big)

    print(
        f"{args.src.name} {w}x{h}  content {box[2]-box[0]+1}x{box[3]-box[1]+1}"
        f"  ->  {args.dst.name} {args.size}x{args.size}"
        f"  ({args.blocks}x{args.blocks} blocks of {factor}px)"
    )
    print(f"wrote {args.dst} ({args.dst.stat().st_size} bytes)")
    print("theme.txt must declare width/height = %d to match, or GRUB will "
          "clamp the component back up to this size and re-break the centring."
          % args.size)


if __name__ == "__main__":
    sys.exit(main())
