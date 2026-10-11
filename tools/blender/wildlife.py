import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import *

# (Wings are single faces: the game draws both sides.) Blender +Y is the animal's front (it becomes -Z, "forward", in Godot); wings stretch along +-X.


def bird():
    clear()
    bm = bmesh.new()
    kinds = {}
    body = bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1.0)
    for v in body["verts"]:
        v.co = Vector((v.co.x * 0.05, v.co.y * 0.15, v.co.z * 0.05))
    for f in bm.faces:
        kinds[f] = "body"
    # tail: a flat wedge
    t = [bm.verts.new(p) for p in ((-0.03, -0.12, 0.0), (0.03, -0.12, 0.0), (0.0, -0.3, 0.005))]
    kinds[bm.faces.new(t)] = "tail"
    for side in (-1, 1):  # wings: root, mid and tip, swept back a little
        w = [bm.verts.new((side * 0.03, 0.06, 0.01)), bm.verts.new((side * 0.03, -0.09, 0.0)),
             bm.verts.new((side * 0.22, -0.14, 0.012)), bm.verts.new((side * 0.2, 0.03, 0.02)),
             bm.verts.new((side * 0.4, -0.2, 0.02))]
        quad = (w[0], w[1], w[2], w[3]) if side > 0 else (w[3], w[2], w[1], w[0])
        kinds[bm.faces.new(quad)] = "wing"
        tri = (w[3], w[2], w[4]) if side > 0 else (w[4], w[2], w[3])
        kinds[bm.faces.new(tri)] = "tip"
    bm.faces.index_update()
    k = {f.index: v for f, v in kinds.items()}
    def colour(co, normal, idx):
        n = k.get(idx, "wing")
        if n == "body":
            return lerp(hex_rgb("#4d3f35"), hex_rgb("#cfc4b2"), 1.0 if normal.z < -0.3 else 0.0)  # pale belly
        if n == "tail":
            return hex_rgb("#3a3028")
        if n == "tip":
            return hex_rgb("#26211c")
        return lerp(hex_rgb("#5d4c3e"), hex_rgb("#8a7560"), min(1.0, abs(co.x) / 0.25))
    paint(bm, colour)
    export_glb("bird", [new_object("bird", bm)])


def butterfly():
    clear()
    bm = bmesh.new()
    kinds = {}
    for side in (-1, 1):
        # upper wing (bigger) and lower wing
        up = [bm.verts.new((side * 0.01, 0.0, 0.0)), bm.verts.new((side * 0.05, 0.07, 0.0)), bm.verts.new((side * 0.11, 0.06, 0.0)),
              bm.verts.new((side * 0.12, 0.0, 0.0)), bm.verts.new((side * 0.04, -0.02, 0.0))]
        lo = [bm.verts.new((side * 0.01, -0.005, 0.0)), bm.verts.new((side * 0.04, -0.02, 0.0)), bm.verts.new((side * 0.1, -0.03, 0.0)),
              bm.verts.new((side * 0.08, -0.09, 0.0)), bm.verts.new((side * 0.02, -0.08, 0.0))]
        for poly, name in ((up, "up"), (lo, "lo")):
            kinds[bm.faces.new(poly if side > 0 else poly[::-1])] = name
    # body: a thin sliver
    b = [bm.verts.new(p) for p in ((-0.006, 0.05, 0.0), (0.006, 0.05, 0.0), (0.006, -0.07, 0.0), (-0.006, -0.07, 0.0))]
    kinds[bm.faces.new(b)] = "body"
    bm.faces.index_update()
    k = {f.index: v for f, v in kinds.items()}
    def colour(co, normal, idx):
        n = k.get(idx, "up")
        if n == "body":
            return hex_rgb("#2a2018")
        r = math.hypot(co.x, co.y - (0.03 if n == "up" else -0.05))
        rim = min(1.0, r / 0.09)
        base = hex_rgb("#ffffff") if n == "up" else hex_rgb("#f3e3c0")
        dark = hex_rgb("#33261c")
        return lerp(base, dark, max(0.0, (rim - 0.72) * 3.2))  # a dark edge, bright middle (tinted per butterfly in the game)
    paint(bm, colour)
    export_glb("butterfly", [new_object("butterfly", bm)])


def duck():
    clear()
    bm = bmesh.new()
    kinds = {}
    def blob(centre, scale, kind, subdiv=1):
        before = set(bm.faces)
        geo = bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=1.0)
        for v in geo["verts"]:
            v.co = Vector((v.co.x * scale[0], v.co.y * scale[1], v.co.z * scale[2])) + Vector(centre)
        for f in bm.faces:
            if f not in before:
                kinds[f] = kind
    blob((0, -0.02, 0.07), (0.115, 0.2, 0.09), "body", 2)
    blob((0, 0.15, 0.2), (0.05, 0.06, 0.1), "neck")
    blob((0, 0.2, 0.28), (0.052, 0.07, 0.055), "head", 2)
    # beak: a flat wedge
    bk = [bm.verts.new(p) for p in ((-0.025, 0.25, 0.275), (0.025, 0.25, 0.275), (0.0, 0.33, 0.265), (0.0, 0.26, 0.255))]
    for tri in ((bk[0], bk[1], bk[2]), (bk[1], bk[0], bk[3]), (bk[0], bk[2], bk[3]), (bk[1], bk[3], bk[2])):
        kinds[bm.faces.new(tri)] = "beak"
    # tail
    tl = [bm.verts.new(p) for p in ((-0.03, -0.17, 0.1), (0.03, -0.17, 0.1), (0.0, -0.3, 0.13), (0.0, -0.18, 0.06))]
    for tri in ((tl[0], tl[1], tl[2]), (tl[1], tl[0], tl[3]), (tl[0], tl[2], tl[3]), (tl[1], tl[3], tl[2])):
        kinds[bm.faces.new(tri)] = "tail"
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    flat(bm)
    bm.faces.index_update()
    k = {}
    for f, v in kinds.items():
        if f.is_valid:
            k[f.index] = v
    def colour(co, normal, idx):
        n = k.get(idx, "body")
        if n == "head":
            return hex_rgb("#2f6b3a") if co.y > 0.18 else hex_rgb("#efe9dc")
        if n == "beak":
            return hex_rgb("#e0b030")
        if n == "neck":
            return hex_rgb("#efe9dc") if co.z < 0.24 else hex_rgb("#2f6b3a")
        if n == "tail":
            return hex_rgb("#2a2a30")
        c = lerp(hex_rgb("#7c6a58"), hex_rgb("#b8b0a2"), min(1.0, max(0.0, (0.1 - co.z) * 4.0 + 0.4)))
        if co.y < -0.12:
            c = hex_rgb("#33343a")
        return shade(c, 0.88 + 0.24 * noise.noise(co * 14.0))
    paint(bm, colour)
    export_glb("duck", [new_object("duck", bm)])


bird()
butterfly()
duck()
