import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import *

BASE = hex_rgb("#2b5a1f")
MID = hex_rgb("#5b9a34")
TIP = hex_rgb("#b3d765")
TIP_DRY = hex_rgb("#d4c768")


def blade(bm, x, y, angle, height, width, lean, tip_colour, store):
    """One grass blade: a tapering strip in two parts (base..mid..tip), leaning and curving toward `angle`."""
    d = Vector((math.cos(angle), math.sin(angle), 0.0))
    side = Vector((-d.y, d.x, 0.0)) * width
    p0 = Vector((x, y, 0.0))
    mid = p0 + d * lean * 0.28 + Vector((0, 0, height * 0.55))
    top = p0 + d * lean + Vector((0, 0, height))
    v = [bm.verts.new(p0 - side), bm.verts.new(p0 + side), bm.verts.new(mid + side * 0.7), bm.verts.new(mid - side * 0.7), bm.verts.new(top)]
    store.append((bm.faces.new((v[0], v[1], v[2], v[3])), tip_colour))
    store.append((bm.faces.new((v[3], v[2], v[4])), tip_colour))


def make_tuft(name, seed, blades):
    clear()
    random.seed(seed)
    bm = bmesh.new()
    store = []
    for i in range(blades):
        r = random.random() * 0.09
        a = random.random() * math.tau
        h = 0.22 + random.random() * 0.26
        blade(bm, math.cos(a) * r, math.sin(a) * r, a + (random.random() - 0.5) * 0.9, h, 0.028 + random.random() * 0.02, 0.07 + random.random() * 0.16,
              TIP_DRY if random.random() < 0.15 else TIP, store)
    colours = {}
    for face, tip in store:
        colours[face.index] = tip
    bm.faces.index_update()
    tips = {f.index: t for f, t in store}

    def colour(co, normal, idx):
        t = max(0.0, min(1.0, co.z / 0.42))
        tip = tips.get(idx, TIP)
        if t < 0.5:
            return lerp(BASE, MID, t * 2.0)
        return lerp(MID, tip, (t - 0.5) * 2.0)

    paint(bm, colour)
    obj = new_object(name, bm)
    export_glb(name, [obj])


def make_flower(name, petal_hex, centre_hex, seed, petals=5, size=0.07, height=0.4):
    clear()
    random.seed(seed)
    bm = bmesh.new()
    kinds = {}
    # stem: a thin curved strip
    lean = Vector((0.05, 0.02, 0.0))
    w = 0.008
    s0 = [bm.verts.new((-w, 0, 0)), bm.verts.new((w, 0, 0))]
    s1 = [bm.verts.new((-w + lean.x * 0.4, 0, height * 0.5)), bm.verts.new((w + lean.x * 0.4, 0, height * 0.5))]
    s2 = [bm.verts.new((-w + lean.x, lean.y, height)), bm.verts.new((w + lean.x, lean.y, height))]
    f = bm.faces.new((s0[0], s0[1], s1[1], s1[0])); kinds[f] = "stem"
    f = bm.faces.new((s1[0], s1[1], s2[1], s2[0])); kinds[f] = "stem"
    head = Vector((lean.x, lean.y, height))
    centre = bm.verts.new(head + Vector((0, 0, 0.012)))
    for p in range(petals):
        a = p / petals * math.tau
        d = Vector((math.cos(a), math.sin(a), 0.0))
        side = Vector((-d.y, d.x, 0.0)) * size * 0.45
        inner = head + d * size * 0.18
        outer = head + d * size + Vector((0, 0, size * 0.35))  # cupped upward
        v = [bm.verts.new(inner - side * 0.4), bm.verts.new(inner + side * 0.4), bm.verts.new(outer + side), bm.verts.new(outer - side)]
        f = bm.faces.new(v); kinds[f] = "petal"
        f = bm.faces.new((v[0], v[1], centre)); kinds[f] = "centre"
    bm.faces.index_update()
    kind_by_index = {f.index: k for f, k in kinds.items()}
    petal = hex_rgb(petal_hex)
    centre_c = hex_rgb(centre_hex)
    leaf = hex_rgb("#4f8a30")

    def colour(co, normal, idx):
        k = kind_by_index.get(idx, "stem")
        if k == "stem":
            return lerp(BASE, leaf, min(1.0, co.z / height))
        if k == "centre":
            return centre_c
        t = max(0.0, min(1.0, (math.hypot(co.x - lean.x, co.y - lean.y) - size * 0.18) / (size * 0.85)))
        return lerp(shade(petal, 0.82), petal, t)

    paint(bm, colour)
    obj = new_object(name, bm)
    export_glb(name, [obj])


make_tuft("grass_tuft", 21, 6)
make_flower("flower_white", "#f6f2e4", "#f0c230", 1)
make_flower("flower_yellow", "#f4c82e", "#c9781c", 2, petals=6, size=0.06)
make_flower("flower_purple", "#8f6ed1", "#f3e3a0", 3, petals=5, size=0.065, height=0.45)
make_flower("flower_red", "#d9483b", "#3a2a16", 4, petals=5, size=0.06, height=0.36)
