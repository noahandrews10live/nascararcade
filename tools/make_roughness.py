#!/usr/bin/env python3
"""Roughness maps for the photographed surfaces (assets/textures/*_rough.jpg).

The CC0 sets came as albedo + normal only. A roughness map is made from the
albedo's local brightness: on race asphalt the tops of the stones are polished
by the tyres (brighter and smoother) and the binder between them is rough; on
poured concrete the smooth formwork faces are lighter than the pits and stains.
512 px is plenty: roughness detail reads at a far lower resolution than colour.

    python3 tools/make_roughness.py
"""
from PIL import Image, ImageFilter

# kind: (base roughness, how much local brightness changes it, low, high)
KINDS = {
    "asphalt": (0.80, -1.1, 0.52, 0.96),
    "concrete": (0.82, -0.7, 0.62, 0.96),
}

for kind, (base, k, lo, hi) in KINDS.items():
    src = Image.open(f"assets/textures/{kind}_albedo.jpg").convert("L").resize((512, 512), Image.LANCZOS)
    mean = src.filter(ImageFilter.GaussianBlur(24))
    out = Image.new("L", src.size)
    sp, mp = src.load(), mean.load()
    w, h = src.size
    for y in range(h):
        for x in range(w):
            local = (sp[x, y] - mp[x, y]) / 255.0
            r = min(max(base + k * local, lo), hi)
            out.putpixel((x, y), int(round(r * 255)))
    out.save(f"assets/textures/{kind}_rough.jpg", quality=90)
    print(kind, "ok")
