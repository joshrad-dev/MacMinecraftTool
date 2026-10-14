#!/usr/bin/env python3
"""Derive Icon Composer-compatible vector artwork from the full SVG icon."""
from pathlib import Path
import re
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parent.parent
source = (root / "Resources/AppIcon.svg").read_text()
art = re.sub(r'  <rect x="(?:64|65\.5)"[^>]*/>\n', '', source)


def flatten_face(match):
    name, a, b, c, d, e, f, body = match.groups()
    a, b, c, d, e, f = map(float, (a, b, c, d, e, f))
    bounds = ET.fromstring(re.search(r'<rect[^>]*/>', body).group(0)).attrib
    face_width, height = float(bounds["width"]), float(bounds["height"])
    paths = [f'<g id="{name}">']
    for rect in re.findall(r'<rect[^>]*/>', body):
        attrs = ET.fromstring(rect).attrib
        x, y = float(attrs.get("x", 0)), float(attrs.get("y", 0))
        width = min(float(attrs["width"]), face_width - x)
        depth = min(float(attrs["height"]), height - y)
        if width <= 0 or depth <= 0:
            continue
        corners = [(x, y), (x + width, y), (x + width, y + depth), (x, y + depth)]
        points = [f'{a*u+c*v+e:.3f},{b*u+d*v+f:.3f}' for u, v in corners]
        paths.append('<path d="M' + ' L'.join(points) + 'Z" fill="' + attrs['fill'] + '"/>')
    return '\n'.join(paths) + '</g>'


# Icon Composer does not render this artwork's transformed clip-path groups.
art = re.sub(
    r'<g id="(top|left|right)" transform="matrix\(([^ ]+) ([^ ]+) ([^ ]+) ([^ ]+) ([^ ]+) ([^)]+)\)" clip-path="[^"]+">(.*?)</g>',
    flatten_face, art, flags=re.S,
)
# The system supplies the icon tile and lighting. Keep the pixel artwork opaque.
art = re.sub(r' filter="url\(#[^)]+\)"', '', art)
ET.fromstring(art)
(root / "Resources/AppIcon.icon/Assets/IconForeground.svg").write_text(art)
