import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import *

# An arming sword, held in first person (hotbar.gd). Blender +Z is up the blade (Godot +Y); the flat of the blade faces
# Blender +-Y (Godot Z). The hilt sits at the origin like the old code-built sword, so the hand model still fits:
# guard at z = 0, grip from 0 down to -0.15, pommel at -0.19.
# Two meshes per sword, so the game can give them different materials: sword_<kind>.glb (blade, guard, pommel: metal)
# and sword_grip.glb (the leather grip and its wrap). Proportions are the point: the first version was 5:1 (a leaf),
# a real blade is ~15:1; this one is ~11:1, a little broad so it still reads at first-person distance.

BLADE = 0.82  # length of the blade from the guard to the tip
WIDTHS = [(0.03, 0.038), (0.30, 0.034), (0.58, 0.029), (0.72, 0.024), (0.79, 0.013), (BLADE, 0.0015)]  # (z, half width)
THICK = 0.0065  # half thickness at the spine


def ring(bm, z, half, thick):
    """The blade's cross-section: a flattened hexagon. Points 0 and 3 are the edges; the four others bound the flats,
    so the faces between are the bevels (edge-0-1, 2-3, 3-4, 5-0) and the flats (1-2, 4-5)."""
    f = 0.42  # where the flat ends and the bevel begins, as a fraction of the half width
    return [bm.verts.new(p) for p in ((-half, 0, z), (-half * f, -thick, z), (half * f, -thick, z),
                                      (half, 0, z), (half * f, thick, z), (-half * f, thick, z))]


def tube(bm, z0, z1, r0, r1, sides, kind, kinds, rot=0.0, scale_y=1.0):
    """A tapered tube along Z with caps (scale_y < 1 flattens it across the blade)."""
    a = [bm.verts.new((math.cos(i / sides * math.tau + rot) * r0, math.sin(i / sides * math.tau + rot) * r0 * scale_y, z0)) for i in range(sides)]
    b = [bm.verts.new((math.cos(i / sides * math.tau + rot) * r1, math.sin(i / sides * math.tau + rot) * r1 * scale_y, z1)) for i in range(sides)]
    for i in range(sides):
        n = (i + 1) % sides
        kinds.append((bm.faces.new((a[i], a[n], b[n], b[i])), kind))
    kinds.append((bm.faces.new(list(reversed(a))), kind))
    kinds.append((bm.faces.new(b), kind))


def bar(bm, a, b, w, h, kind, kinds):
    """A rectangular bar from a to b in the XZ plane: w wide across the blade (Y), h tall."""
    d = (b - a).normalized()
    up = Vector((-d.z, 0, d.x)) * (h / 2)
    side = Vector((0, w / 2, 0))
    pa = [bm.verts.new(a + up * sy + side * sx) for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    pb = [bm.verts.new(b + up * sy + side * sx) for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    for i in range(4):
        n = (i + 1) % 4
        kinds.append((bm.faces.new((pa[i], pa[n], pb[n], pb[i])), kind))
    kinds.append((bm.faces.new(list(reversed(pa))), kind))
    kinds.append((bm.faces.new(pb), kind))


def metal_parts(name, steel_hex, fitting_hex, rusty=False):
    clear()
    random.seed(17)
    bm = bmesh.new()
    kinds = []
    # blade
    rings = [ring(bm, z, half, THICK if z < BLADE - 0.01 else 0.0008) for z, half in WIDTHS]
    bevel = {0, 2, 3, 5}  # face k runs from point k to point k+1
    for i in range(len(rings) - 1):
        a, b = rings[i], rings[i + 1]
        for k in range(6):
            n = (k + 1) % 6
            kinds.append((bm.faces.new((a[k], a[n], b[n], b[k])), "bevel" if k in bevel else "flat"))
    kinds.append((bm.faces.new(list(reversed(rings[0]))), "flat"))
    # ricasso block where the blade meets the guard
    tube(bm, -0.005, 0.035, 0.03, 0.026, 4, "fitting", kinds, rot=math.pi / 4, scale_y=0.45)
    # crossguard: a slim bar, rising a little towards the blade at each end, with flared tips
    for side in (-1, 1):
        pts = [Vector((side * x, 0, 0.004 + 0.12 * x * x)) for x in (0.0, 0.035, 0.07, 0.1)]
        for p, q in zip(pts, pts[1:]):
            bar(bm, p, q, 0.022, 0.018, "fitting", kinds)
        tip = pts[-1]
        tube(bm, tip.z - 0.016, tip.z + 0.016, 0.013, 0.013, 6, "fitting", kinds)
        for v in bm.verts[-12:]:
            v.co.x += tip.x
    # pommel: a wheel (a short disc, its face towards the flat of the blade) and a small peen on top
    geo = bmesh.ops.create_cone(bm, cap_ends=True, segments=12, radius1=0.034, radius2=0.034, depth=0.022)
    for v in geo["verts"]:
        v.co = Vector((v.co.x, v.co.z, v.co.y))  # turn the disc to stand on edge
        v.co.z -= 0.19
    for f in {f for v in geo["verts"] for f in v.link_faces}:
        kinds.append((f, "pommel"))
    tube(bm, -0.235, -0.222, 0.012, 0.008, 6, "fitting", kinds)
    bm.faces.index_update()
    k = {f.index: n for f, n in kinds if f.is_valid}
    steel = hex_rgb(steel_hex)
    fitting = hex_rgb(fitting_hex)

    def colour(co, normal, idx):
        n = k.get(idx, "flat")
        if n in ("fitting", "pommel"):
            c = shade(fitting, 0.8 + 0.25 * noise.noise(co * 30.0))
            if n == "pommel" and abs(normal.y) > 0.8:
                c = shade(c, 1.15)  # the polished faces of the wheel
            return c
        c = shade(steel, 1.12 if n == "bevel" else 0.86)  # bright honed edges, darker flats
        if n == "flat" and abs(co.x) < 0.0075 and 0.05 < co.z < 0.6:
            c = shade(steel, 0.48)  # the fuller, a dark groove down the middle
        c = shade(c, 0.94 + 0.08 * noise.noise(co * 9.0))
        if rusty:
            spot = noise.noise(co * 22.0 + Vector((3, 1, 2)))
            if spot > 0.25:
                c = lerp(c, hex_rgb("#6e4126"), min(1.0, (spot - 0.25) * 4.0))
        return c
    flat(bm)
    paint(bm, colour)
    export_glb(name, [new_object(name, bm)])


def grip():
    """The leather grip: a slightly swelling octagonal core with a raised spiral cord wound round it."""
    clear()
    bm = bmesh.new()
    kinds = []
    tube(bm, -0.155, -0.005, 0.017, 0.016, 8, "leather", kinds, scale_y=0.8)
    turns = 6
    steps = 48
    for s in range(steps):  # the cord: short bars following a helix
        t0, t1 = s / steps, (s + 1) / steps
        def at(t):
            a = t * turns * math.tau
            return Vector((math.cos(a) * 0.0175, math.sin(a) * 0.0175 * 0.8, -0.15 + t * 0.14))
        tube_seg = (at(t0), at(t1))
        d = tube_seg[1] - tube_seg[0]
        side = d.cross(Vector((0, 0, 1))).normalized() * 0.003
        up = d.cross(side).normalized() * 0.003
        a = [bm.verts.new(tube_seg[0] + side * x + up * y) for x, y in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
        b = [bm.verts.new(tube_seg[1] + side * x + up * y) for x, y in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
        for i in range(4):
            n = (i + 1) % 4
            kinds.append((bm.faces.new((a[i], a[n], b[n], b[i])), "cord"))
    bm.faces.index_update()
    k = {f.index: n for f, n in kinds if f.is_valid}

    def colour(co, normal, idx):
        if k.get(idx) == "cord":
            return shade(hex_rgb("#7a5a3c"), 0.9 + 0.2 * noise.noise(co * 60.0))
        return shade(hex_rgb("#3e2a1c"), 0.85 + 0.25 * noise.noise(co * 40.0))
    paint(bm, colour)
    export_glb("sword_grip", [new_object("sword_grip", bm)])


metal_parts("sword_rusty", "#8c8580", "#5e4a36", rusty=True)
metal_parts("sword_iron", "#b9c0c6", "#a8823f")
metal_parts("sword_steel", "#a9c3e0", "#c9a24a")
grip()
