#!/usr/bin/env python3
"""Screenshot regression check (standard library only).

The app draws its own screenshots from sample data (`TapTheTab --render-screenshots`).
This compares a folder of those PNGs with the committed reference
`docs/images/screenshot-reference.json`, which holds for every image

  - its size in pixels (a layout regression nearly always changes the size), and
  - a 16x16 average hash: the picture is reduced to a 16x16 grid of brightness values,
    and each cell becomes 1 (brighter than the average cell) or 0. 256 bits, written as
    64 hex digits.

The check fails when an image's size differs, or when its hash differs from the
reference in more bits than the threshold (default 48 of 256: generous, so font or icon
changes between macOS versions pass, while a missing block, a wrong theme or a light/dark
mix-up does not). Images missing from the folder or from the reference fail too.

    python3 -I scripts/check-screenshots.py dist/screenshots
    python3 -I scripts/check-screenshots.py --update dist/screenshots   # accept the new look

Without a reference file the check passes with a notice: run it with `--write FILE` to
get the file it would have used (CI uploads that file next to the screenshots).

Only the PNG forms the renderer and common optimisers write are read: 8-bit (or 16-bit)
grey, grey+alpha, RGB, RGBA and 8-bit palette, not interlaced. Transparency is ignored
(the renderer's images are opaque). Animated PNGs are read as their first frame.

Exit status: 0 = ok, 1 = a screenshot changed, 2 = usage or file error.
"""

import argparse
import itertools
import json
import operator
import os
import struct
import sys
import zlib

GRID = 16
DEFAULT_THRESHOLD = 48
FORMAT_VERSION = 1
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_REFERENCE = os.path.join(REPO_ROOT, "docs", "images", "screenshot-reference.json")
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"

# Samples per pixel for each PNG colour type.
CHANNELS = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}


class CheckError(Exception):
    """A problem with a file or the arguments (exit status 2)."""


# --- PNG reading --------------------------------------------------------------------------


def read_chunks(data, name):
    if data[:8] != PNG_SIGNATURE:
        raise CheckError("%s: not a PNG file" % name)
    position = 8
    while position + 8 <= len(data):
        length, kind = struct.unpack(">I4s", data[position:position + 8])
        body = data[position + 8:position + 8 + length]
        crc = data[position + 8 + length:position + 12 + length]
        if len(body) != length or len(crc) != 4:
            raise CheckError("%s: truncated PNG" % name)
        if struct.unpack(">I", crc)[0] != zlib.crc32(kind + body) & 0xFFFFFFFF:
            raise CheckError("%s: damaged PNG (bad checksum in %s chunk)" % (name, kind.decode("latin-1")))
        yield kind, body
        position += 12 + length
        if kind == b"IEND":
            return
    raise CheckError("%s: truncated PNG (no IEND chunk)" % name)


def unfilter_row(kind, raw, previous, bpp):
    """Undo one PNG scanline filter. `raw` and `previous` are bytes, the result is bytes."""
    if kind == 0:
        return raw
    if kind == 1:  # Sub: running sum per channel
        out = bytearray(len(raw))
        for channel in range(bpp):
            sums = itertools.accumulate(raw[channel::bpp])
            out[channel::bpp] = bytes(map((255).__and__, sums))
        return bytes(out)
    if kind == 2:  # Up
        return bytes(map((255).__and__, map(operator.add, raw, previous)))
    out = bytearray(raw)
    length = len(raw)
    if kind == 3:  # Average
        for i in range(min(bpp, length)):
            out[i] = (raw[i] + (previous[i] >> 1)) & 255
        for i in range(bpp, length):
            out[i] = (raw[i] + ((out[i - bpp] + previous[i]) >> 1)) & 255
        return bytes(out)
    if kind == 4:  # Paeth
        for i in range(min(bpp, length)):
            out[i] = (raw[i] + previous[i]) & 255
        for i in range(bpp, length):
            a = out[i - bpp]
            b = previous[i]
            c = previous[i - bpp]
            pa = abs(b - c)
            pb = abs(a - c)
            pc = abs(a + b - c - c)
            if pa <= pb and pa <= pc:
                predictor = a
            elif pb <= pc:
                predictor = b
            else:
                predictor = c
            out[i] = (raw[i] + predictor) & 255
        return bytes(out)
    raise CheckError("unknown PNG filter type %d" % kind)


def bin_edges(count, parts):
    return [i * count // parts for i in range(parts + 1)]


def png_fingerprint(path):
    """Returns (width, height, hash as an int of GRID*GRID bits)."""
    name = os.path.basename(path)
    try:
        with open(path, "rb") as handle:
            data = handle.read()
    except OSError as error:
        raise CheckError("cannot read %s: %s" % (path, error.strerror))

    header = None
    palette = None
    compressed = []
    for kind, body in read_chunks(data, name):
        if kind == b"IHDR":
            header = struct.unpack(">IIBBBBB", body)
        elif kind == b"PLTE":
            palette = body
        elif kind == b"IDAT":
            compressed.append(body)
    if header is None or not compressed:
        raise CheckError("%s: not a complete PNG (no header or image data)" % name)

    width, height, depth, color_type, _compression, _filter_method, interlace = header
    if width < GRID or height < GRID:
        raise CheckError("%s: image is smaller than %dx%d" % (name, GRID, GRID))
    if interlace != 0:
        raise CheckError("%s: interlaced PNGs are not supported" % name)
    if color_type not in CHANNELS or depth not in ((8,) if color_type == 3 else (8, 16)):
        raise CheckError(
            "%s: unsupported PNG format (color type %d, %d bits per sample)" % (name, color_type, depth)
        )
    if color_type == 3 and (palette is None or len(palette) % 3 != 0):
        raise CheckError("%s: palette PNG without a valid palette" % name)

    channels = CHANNELS[color_type]
    step = channels * (depth // 8)  # bytes per pixel, also the filter's distance
    stride = width * step
    try:
        pixels = zlib.decompress(b"".join(compressed))
    except zlib.error as error:
        raise CheckError("%s: damaged image data (%s)" % (name, error))
    if len(pixels) != height * (stride + 1):
        raise CheckError("%s: image data has the wrong length" % name)

    # Per-channel lookup tables turning a palette index into red, green and blue.
    tables = None
    if color_type == 3:
        entries = len(palette) // 3
        tables = []
        for channel in range(3):
            table = bytearray(256)
            for index in range(min(entries, 256)):
                table[index] = palette[index * 3 + channel]
            tables.append(bytes(table))

    x_edges = bin_edges(width, GRID)
    y_edges = bin_edges(height, GRID)
    row_bin = []
    for index in range(GRID):
        row_bin.extend([index] * (y_edges[index + 1] - y_edges[index]))
    sums = [[[0, 0, 0] for _ in range(GRID)] for _ in range(GRID)]
    previous = bytes(stride)
    for y in range(height):
        offset = y * (stride + 1)
        row = unfilter_row(pixels[offset], pixels[offset + 1:offset + 1 + stride], previous, step)
        previous = row
        # Grey and RGB keep the high byte of 16-bit samples; alpha is ignored.
        if color_type == 3:
            planes = [row.translate(table) for table in tables]
        elif color_type in (0, 4):
            plane = row[0::step]
            planes = [plane, plane, plane]
        else:
            planes = [row[0::step], row[step // channels::step], row[2 * (step // channels)::step]]
        cells = sums[row_bin[y]]
        for column in range(GRID):
            low, high = x_edges[column], x_edges[column + 1]
            cell = cells[column]
            for index in range(3):
                cell[index] += sum(planes[index][low:high])

    # Average brightness of each cell (299/587/114 luma weights), then compare with the mean.
    values = []
    for row_index in range(GRID):
        rows = y_edges[row_index + 1] - y_edges[row_index]
        for column in range(GRID):
            count = rows * (x_edges[column + 1] - x_edges[column])
            red, green, blue = sums[row_index][column]
            values.append((299 * red + 587 * green + 114 * blue) / (1000.0 * count))
    mean = sum(values) / len(values)
    bits = 0
    for value in values:
        bits = (bits << 1) | (1 if value > mean else 0)
    return width, height, bits


# --- Reference file -----------------------------------------------------------------------


def hash_text(bits):
    return "%0*x" % (GRID * GRID // 4, bits)


def distance(a, b):
    return bin(a ^ b).count("1")


def collect(directory):
    try:
        names = sorted(n for n in os.listdir(directory) if n.lower().endswith(".png"))
    except OSError as error:
        raise CheckError("cannot read %s: %s" % (directory, error.strerror))
    if not names:
        raise CheckError("no .png files in %s" % directory)
    images = {}
    for name in names:
        width, height, bits = png_fingerprint(os.path.join(directory, name))
        images[name] = {"width": width, "height": height, "hash": hash_text(bits)}
    return images


def reference_document(images):
    return {
        "format": FORMAT_VERSION,
        "about": (
            "Written by scripts/check-screenshots.py. Per image: pixel size and a %dx%d average hash "
            "(%d bits, hex, row by row). Update with: python3 -I scripts/check-screenshots.py --update dist/screenshots"
            % (GRID, GRID, GRID * GRID)
        ),
        "images": images,
    }


def write_json(path, document):
    try:
        parent = os.path.dirname(os.path.abspath(path))
        os.makedirs(parent, exist_ok=True)
        with open(path, "w", encoding="utf-8") as handle:
            json.dump(document, handle, indent=2, sort_keys=True)
            handle.write("\n")
    except OSError as error:
        raise CheckError("cannot write %s: %s" % (path, error.strerror))


def load_reference(path):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            document = json.load(handle)
    except OSError as error:
        raise CheckError("cannot read %s: %s" % (path, error.strerror))
    except ValueError as error:
        raise CheckError("%s is not valid JSON: %s" % (path, error))
    if not isinstance(document, dict) or document.get("format") != FORMAT_VERSION:
        raise CheckError("%s: unknown format; regenerate it with --update" % path)
    images = document.get("images")
    if not isinstance(images, dict):
        raise CheckError("%s: no \"images\" table" % path)
    for name, entry in images.items():
        try:
            int(entry["hash"], 16)
            int(entry["width"]), int(entry["height"])
        except (KeyError, TypeError, ValueError):
            raise CheckError("%s: bad entry for %s" % (path, name))
    return images


# --- Comparison and report ----------------------------------------------------------------


def bit_grid(bits):
    text = "{:0{n}b}".format(bits, n=GRID * GRID)
    return [text[i * GRID:(i + 1) * GRID] for i in range(GRID)]


def hash_diff(reference_bits, current_bits):
    """Three 16x16 pictures side by side: reference, now, and where they differ."""
    reference, current = bit_grid(reference_bits), bit_grid(current_bits)
    lines = ["      reference         now            differs"]
    for r, c in zip(reference, current):
        differs = "".join("X" if x != y else "." for x, y in zip(r, c))
        lines.append("      %s  %s  %s" % (r.replace("0", ".").replace("1", "#"),
                                          c.replace("0", ".").replace("1", "#"), differs))
    return lines


def compare(reference, current, threshold):
    """Returns (problems, lines to print). A problem is a one-line summary."""
    problems = []
    report = []
    for name in sorted(set(reference) | set(current)):
        if name not in current:
            problems.append("%s: in the reference but not rendered" % name)
            continue
        if name not in reference:
            problems.append("%s: rendered but not in the reference (new screenshot?)" % name)
            continue
        old, new = reference[name], current[name]
        if (old["width"], old["height"]) != (new["width"], new["height"]):
            problems.append(
                "%s: size changed from %dx%d to %dx%d px (layout change?)"
                % (name, old["width"], old["height"], new["width"], new["height"])
            )
            continue
        old_bits, new_bits = int(old["hash"], 16), int(new["hash"], 16)
        changed = distance(old_bits, new_bits)
        if changed > threshold:
            problems.append(
                "%s: picture changed (%d of %d hash bits differ, allowed %d)"
                % (name, changed, GRID * GRID, threshold)
            )
            report.extend(hash_diff(old_bits, new_bits))
        else:
            report.append("ok  %s (%d px wide, %d of %d bits differ)" % (name, new["width"], changed, GRID * GRID))
    return problems, report


def on_github():
    return os.environ.get("GITHUB_ACTIONS") == "true"


def main(argv):
    parser = argparse.ArgumentParser(
        description="Compare rendered screenshots with the committed reference (size + average hash).",
    )
    parser.add_argument("directory", help="folder with the rendered PNGs, e.g. dist/screenshots")
    parser.add_argument("--reference", default=DEFAULT_REFERENCE, help="reference file (default: %(default)s)")
    parser.add_argument("--update", action="store_true", help="write the reference from the folder and exit")
    parser.add_argument("--write", metavar="FILE", help="also write the reference this folder would produce to FILE")
    parser.add_argument("--threshold", type=int, default=DEFAULT_THRESHOLD,
                        help="most hash bits (of 256) that may differ (default: %(default)s)")
    args = parser.parse_args(argv)
    if not 0 <= args.threshold <= GRID * GRID:
        raise CheckError("--threshold must be between 0 and %d" % (GRID * GRID))

    current = collect(args.directory)
    document = reference_document(current)
    if args.write:
        write_json(args.write, document)
        print("Wrote %s (%d images)." % (args.write, len(current)))

    if args.update:
        write_json(args.reference, document)
        print("Updated %s (%d images). Commit it together with the images in docs/images." %
              (args.reference, len(current)))
        return 0

    if not os.path.exists(args.reference):
        message = (
            "No reference file at %s, so nothing was compared. Take the generated "
            "screenshot-reference.json from this run's screenshots artifact, or run "
            "`python3 -I scripts/check-screenshots.py --update <folder>`, and commit it."
            % os.path.relpath(args.reference, REPO_ROOT)
        )
        print("notice: " + message)
        if on_github():
            print("::notice title=Screenshot reference missing::" + message)
        return 0

    problems, report = compare(load_reference(args.reference), current, args.threshold)
    for line in report:
        print(line)
    if not problems:
        print("Screenshots match the reference (%d images)." % len(current))
        return 0

    print()
    for problem in problems:
        print("FAIL  " + problem)
        if on_github():
            print("::error title=Screenshot regression::" + problem)
    print()
    print("If the change is intended, accept the new look and commit the result:")
    print("  python3 -I scripts/check-screenshots.py --update %s" % args.directory)
    print("(then commit docs/images/screenshot-reference.json and the refreshed PNGs from the CI artifact).")
    return 1


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except CheckError as error:
        print("error: %s" % error, file=sys.stderr)
        sys.exit(2)
