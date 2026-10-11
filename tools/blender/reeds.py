import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import *

STEM_LO = hex_rgb("#3f6a2a")
STEM_HI = hex_rgb("#9bbd58")
HEAD = hex_rgb("#5a3a22")
HEAD_TIP = hex_rgb("#7a5230")
LEAF = hex_rgb("#4f8a38")


def make_reeds(name, seed, stems, with_heads):
    clear()
    random.seed(seed)
    bm = bmesh.new()
    kind = {}

    def strip(base, tip, width, kind_name, bend=0.0):
        d = tip - base
        side = Vector((-d.y, d.x, 0.0)).normalized() * width
        mid = base + d * 0.55 + Vector((bend, 0, 0))
        v = [bm.verts.new(base - side), bm.verts.new(base + side), bm.verts.new(mid + side * 0.7), bm.verts.new(mid - side * 0.7), bm.verts.new(tip)]
        kind[bm.faces.new((v[0], v[1], v[2], v[3]))] = kind_name
        kind[bm.faces.new((v[3], v[2], v[4]))] = kind_name

    for i in range(stems):
        a = random.random() * math.tau
        r = random.random() * 0.22
        base = Vector((math.cos(a) * r, math.sin(a) * r, 0.0))
        h = 0.9 + random.random() * 0.7
        lean = Vector((math.cos(a), math.sin(a), 0.0)) * (0.05 + random.random() * 0.22)
        tip = base + lean + Vector((0, 0, h))
        strip(base, tip, 0.012 + random.random() * 0.01, "stem")
        if with_heads and i % 2 == 0:  # a cattail: a short brown cylinder near the top of the stem
            c0 = base + (tip - base) * 0.74
            before = len(bm.verts)
            rings = lathe(bm, [(0.0, 0.0), (0.035, 0.03), (0.04, 0.12), (0.03, 0.2), (0.0, 0.23)], segs=5, cap_bottom=False, cap_top=False)
            for v in list(bm.verts)[before:]:
                v.co += c0
    for i in range(max(3, stems // 3)):  # a few broad leaves leaning out
        a = random.random() * math.tau
        base = Vector((math.cos(a) * 0.05, math.sin(a) * 0.05, 0.0))
        tip = base + Vector((math.cos(a), math.sin(a), 0.0)) * (0.35 + random.random() * 0.3) + Vector((0, 0, 0.5 + random.random() * 0.4))
        strip(base, tip, 0.045, "leaf")
    bm.faces.index_update()
    kind_by_index = {f.index: k for f, k in kind.items()}
    ztop = 1.7

    def colour(co, normal, idx):
        k = kind_by_index.get(idx, "head")
        if k == "head":
            return lerp(HEAD, HEAD_TIP, noise.noise(co * 20.0) * 0.5 + 0.5)
        if k == "leaf":
            return lerp(STEM_LO, LEAF, min(1.0, co.z / 0.8))
        return lerp(STEM_LO, STEM_HI, min(1.0, co.z / ztop))

    paint(bm, colour)
    export_glb(name, [new_object(name, bm)])


make_reeds("reeds", 31, 9, True)
make_reeds("reeds_plain", 32, 8, False)
