#!/usr/bin/env python3
"""Export crisp README PNGs from the built native app using synthetic readings.

No monitoring, personal history, visible windows or screen capture is involved.
Build first with ./scripts/build.sh. Use --app to select another built bundle.
"""
import argparse
from pathlib import Path
import struct
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--app', type=Path, default=root / 'dist/Mac Buddy.app')
args = parser.parse_args()
binary = args.app.resolve() / 'Contents/MacOS/MacBuddy'
if not binary.is_file():
    parser.error('Built app not found. Run ./scripts/build.sh first, or pass --app PATH.')

scenes = [
    ('strip@3x.png', ['--collapsed'], (1440, 204)),
    ('expanded-panel@3x.png', [], (1440, 1680)),
    ('dashboard@3x.png', ['--render-scene', 'dashboard'], (2880, 2370)),
]


def publication_png(data, expected):
    if data[:8] != b'\x89PNG\r\n\x1a\n':
        raise ValueError('Renderer did not produce a PNG.')
    dimensions = struct.unpack('>II', data[16:24])
    if dimensions != expected:
        raise ValueError(f'Expected a native 3x export {expected}, got {dimensions}. Rebuild the app.')
    output = bytearray(data[:8])
    position = 8
    while position < len(data):
        size = int.from_bytes(data[position:position + 4], 'big')
        kind = data[position + 4:position + 8]
        end = position + size + 12
        if end > len(data):
            raise ValueError('Truncated PNG chunk.')
        # Keep pixels, color profile and resolution; omit potentially identifying
        # EXIF/text metadata. This does not resize or sharpen the source pixels.
        if kind not in {b'eXIf', b'tEXt', b'zTXt', b'iTXt'}:
            output.extend(data[position:end])
        position = end
    return output


# Validate every render before replacing published assets.
with tempfile.TemporaryDirectory(prefix='MacBuddy-readme-') as scratch:
    rendered = []
    for name, options, expected in scenes:
        path = Path(scratch) / name
        subprocess.run([str(binary), '--render-overlay', str(path), *options], check=True)
        rendered.append((name, publication_png(path.read_bytes(), expected), expected))
    destination = root / 'docs/images'
    destination.mkdir(parents=True, exist_ok=True)
    for name, data, dimensions in rendered:
        path = destination / name
        stage = path.with_suffix('.png.tmp')
        stage.write_bytes(data)
        stage.replace(path)
        print(f'Created {path.relative_to(root)}: {dimensions[0]} × {dimensions[1]} pixels')
