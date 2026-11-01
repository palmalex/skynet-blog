"""Image size budget for a built site (run by `build.sh check`), and a generator of test images.

Usage:
  check_images.py <output dir> <max bytes>      every image of the output must be at most <max bytes>
  check_images.py fixture <path> <width> <height>
                                                write a noisy PNG (test material for `build.sh check`)

The budget applies to the output, so it also counts what the build produced: a large image that goes through the
`resized_image` component is scaled and converted to WebP first and passes, a large image copied as it is fails.
"""
import os
import random
import struct
import sys
import zlib

EXTENSIONS = (".png", ".jpg", ".jpeg", ".gif", ".webp", ".avif", ".svg", ".ico")


def write_noisy_png(path, width, height, block=4):
    """Blocks of random colours: a size of a few hundred KB that compresses well once scaled down."""
    rnd = random.Random(1)
    rows = []
    for _ in range(0, height, block):
        colours = [bytes(rnd.randrange(256) for _ in range(3)) for _ in range(0, width, block)]
        row = b"\x00" + b"".join(c * block for c in colours)[: width * 3]
        rows.extend([row] * block)

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(b"".join(rows[:height]), 6)) + chunk(b"IEND", b"")
    with open(path, "wb") as handle:
        handle.write(png)


if sys.argv[1] == "fixture":
    write_noisy_png(sys.argv[2], int(sys.argv[3]), int(sys.argv[4]))
    sys.exit(0)

out, budget = sys.argv[1], int(sys.argv[2])
images, failures = [], []
for root, _, names in os.walk(out):
    for name in names:
        if name.lower().endswith(EXTENSIONS):
            path = os.path.join(root, name)
            images.append((os.path.getsize(path), os.path.relpath(path, out)))
            if images[-1][0] > budget:
                failures.append("%s is %d bytes, the budget is %d" % (images[-1][1], images[-1][0], budget))

largest = max(images)[0] if images else 0
print("images: %d checked, largest %d bytes, budget %d bytes" % (len(images), largest, budget))
if not images:
    # A checker that looks at nothing must not pass (wrong directory).
    failures.append("no image found: wrong output directory?")
if failures:
    print("OVER THE BUDGET:\n  " + "\n  ".join(sorted(failures)))
    sys.exit(1)
print("OK")
