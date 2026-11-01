"""Flatten piece SVGs for flutter_svg / vector_graphics.

Upstream piece sets (lichess-org/lila public/piece/<set>) use a <style> block
with class rules and gradients that inherit stops via xlink:href. The Flutter
SVG compiler supports neither reliably, so this script:
  * applies `.class{...}` rules as presentation attributes (CSS wins over
    attributes, as in browsers),
  * copies inherited gradient stops/attributes into the referencing gradient,
  * drops <style>, ids and the root `style` attribute.

Usage: python3 tool/normalize_pieces.py <src_dir> <dst_dir>
"""
import copy
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

SVG = 'http://www.w3.org/2000/svg'
XLINK = 'http://www.w3.org/1999/xlink'
ET.register_namespace('', SVG)
ET.register_namespace('xlink', XLINK)


def q(tag: str) -> str:
    return f'{{{SVG}}}{tag}'


def parse_css(text: str) -> dict[str, dict[str, str]]:
    rules: dict[str, dict[str, str]] = {}
    for sel, body in re.findall(r'([^{}]+)\{([^}]*)\}', text):
        decls = dict(
            (k.strip(), v.strip())
            for k, v in (d.split(':', 1) for d in body.split(';') if ':' in d))
        for s in sel.split(','):
            s = s.strip()
            if not re.fullmatch(r'\.[\w-]+', s):
                raise SystemExit(f'unsupported CSS selector {s!r}')
            rules.setdefault(s[1:], {}).update(decls)
    return rules


def normalize(src: Path) -> str:
    tree = ET.parse(src)
    root = tree.getroot()
    rules: dict[str, dict[str, str]] = {}
    for parent in list(root.iter()):
        for child in list(parent):
            if child.tag == q('style'):
                rules.update(parse_css(child.text or ''))
                parent.remove(child)
    for el in root.iter():
        for cls in (el.attrib.pop('class', '') or '').split():
            for k, v in rules.get(cls, {}).items():
                el.set(k, v)
        inline = el.attrib.pop('style', None)
        if inline and el is not root:
            for d in inline.split(';'):
                if ':' in d:
                    k, v = d.split(':', 1)
                    el.set(k.strip(), v.strip())
    by_id = {el.get('id'): el for el in root.iter() if el.get('id')}
    href = f'{{{XLINK}}}href'
    for el in root.iter():
        ref = el.attrib.pop(href, None) or el.attrib.pop('href', None)
        if not ref:
            continue
        base = by_id[ref.lstrip('#')]
        if not list(el):
            for stop in base:
                el.append(copy.deepcopy(stop))
        for k, v in base.attrib.items():
            if k not in el.attrib and k != 'id':
                el.set(k, v)
    # Keep only ids that are referenced via url(#id).
    used = set(re.findall(r'url\(#([^)]+)\)', ET.tostring(root, encoding='unicode')))
    for el in root.iter():
        if el.get('id') and el.get('id') not in used:
            del el.attrib['id']
        if el.get('stroke-dasharray') == 'none':
            del el.attrib['stroke-dasharray']
    # Gradients nobody references any more (the old stop holders).
    for parent in list(root.iter()):
        for child in list(parent):
            if child.tag in (q('linearGradient'), q('radialGradient')) and not child.get('id'):
                parent.remove(child)
    return ET.tostring(root, encoding='unicode')


def main() -> None:
    src, dst = Path(sys.argv[1]), Path(sys.argv[2])
    dst.mkdir(parents=True, exist_ok=True)
    for f in sorted(src.glob('*.svg')):
        (dst / f.name).write_text(normalize(f))


if __name__ == '__main__':
    main()
