import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import *

WOOD = hex_rgb("#7a5532")
WOOD_DARK = hex_rgb("#4a3220")
IRON = hex_rgb("#3a3d42")
STRAW = hex_rgb("#cfae62")
TWINE = hex_rgb("#6a4a2a")
CLOTH = hex_rgb("#c8b58a")


def barrel():
    clear()
    bm = bmesh.new()
    # bulging staves: radius swells in the middle
    profile = [(0.28, 0.0), (0.33, 0.12), (0.37, 0.3), (0.38, 0.45), (0.37, 0.6), (0.33, 0.78), (0.28, 0.9)]
    lathe(bm, profile, segs=12, wobble=0.02, seed=1)
    # four iron hoops: slightly wider bands
    hoop_z = [0.1, 0.3, 0.6, 0.8]
    def radius_at(z):
        for i in range(len(profile) - 1):
            if profile[i][1] <= z <= profile[i + 1][1]:
                t = (z - profile[i][1]) / (profile[i + 1][1] - profile[i][1])
                return profile[i][0] + (profile[i + 1][0] - profile[i][0]) * t
        return 0.3
    for z in hoop_z:
        r = radius_at(z) + 0.012
        lathe(bm, [(r, z - 0.025), (r, z + 0.025)], segs=12, cap_bottom=False, cap_top=False)
    finish(bm)
    bm.faces.index_update()
    def colour(co, normal, idx):
        r = math.hypot(co.x, co.y)
        for z in hoop_z:
            if abs(co.z - z) < 0.03 and r > radius_at(co.z):
                return shade(IRON, 0.8 + 0.4 * noise.noise(co * 6.0))
        if co.z > 0.88 and normal.z > 0.5:  # the lid
            return shade(WOOD_DARK, 0.8 + 0.5 * abs(math.sin(co.x * 28.0)))
        a = math.atan2(co.y, co.x)
        return shade(WOOD, 0.78 + 0.4 * noise.noise(Vector((a * 4.0, co.z * 1.5, 1.0))))
    paint(bm, colour)
    export_glb("barrel", [new_object("barrel", bm)])


def crate():
    clear()
    bm = bmesh.new()
    s = 0.42
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co *= Vector((s * 2, s * 2, s * 2)) * 0.5
        v.co.z += s
    # chamfer the edges a little: chunky planks
    bmesh.ops.bevel(bm, geom=list(bm.edges), offset=0.035, segments=1, affect="EDGES")
    finish(bm)
    bm.faces.index_update()
    def colour(co, normal, idx):
        c = shade(WOOD, 0.75 + 0.45 * noise.noise(co * 5.0 + Vector((3, 3, 3))))
        # plank lines on the sides, darker cross battens
        if abs(normal.z) < 0.5:
            c = shade(c, 0.85 + 0.25 * (1 if math.sin(co.z * 19.0) > -0.2 else 0))
        edge = min(abs(abs(co.x) - s), abs(abs(co.y) - s), abs(co.z - 0.0), abs(co.z - 2 * s))
        if edge < 0.06:
            c = shade(WOOD_DARK, 0.85 + 0.3 * noise.noise(co * 7.0))
        return c
    paint(bm, colour)
    export_glb("crate", [new_object("crate", bm)])


def hay_bale():
    clear()
    random.seed(4)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.subdivide_edges(bm, edges=list(bm.edges), cuts=3, use_grid_fill=True)
    for v in bm.verts:
        v.co *= Vector((1.3, 0.9, 0.9))
        v.co.z += 0.45
        # rounded edges: pull the corners in a little, then roughen
        v.co.x *= 1.0 - 0.06 * abs(v.co.y / 0.45) * abs((v.co.z - 0.45) / 0.45)
        v.co += Vector((noise.noise(v.co * 5.0) * 0.03, noise.noise(v.co * 5.0 + Vector((9, 9, 9))) * 0.03, noise.noise(v.co * 5.0 + Vector((4, 4, 4))) * 0.03))
    finish(bm)
    bm.faces.index_update()
    def colour(co, normal, idx):
        c = shade(STRAW, 0.78 + 0.4 * noise.noise(Vector((co.x * 9.0, co.y * 2.0, co.z * 9.0))))
        for bx in (-0.32, 0.32):  # two bands of twine round the bale
            if abs(co.x - bx) < 0.035 and abs(normal.x) < 0.6:
                return shade(TWINE, 0.9 + 0.2 * noise.noise(co * 8.0))
        return c
    paint(bm, colour)
    export_glb("hay_bale", [new_object("hay_bale", bm)])


def bucket():
    clear()
    bm = bmesh.new()
    lathe(bm, [(0.17, 0.0), (0.2, 0.12), (0.23, 0.28)], segs=10, cap_top=False)
    lathe(bm, [(0.22, 0.22), (0.235, 0.2), (0.235, 0.23), (0.22, 0.25)], segs=10, cap_bottom=False, cap_top=False)
    # rope handle: an arc of small quads
    n = 9
    prev = None
    for i in range(n + 1):
        a = math.pi * i / n
        c = Vector((math.cos(a) * 0.23, 0.0, 0.28 + math.sin(a) * 0.17))
        quad = [bm.verts.new(c + Vector((0, -0.012, 0.0))), bm.verts.new(c + Vector((0, 0.012, 0.0)))]
        if prev:
            bm.faces.new((prev[0], prev[1], quad[1], quad[0]))
        prev = quad
    finish(bm)
    bm.faces.index_update()
    def colour(co, normal, idx):
        if co.z > 0.285 or abs(co.y) < 0.02 and co.z > 0.27:
            return shade(TWINE, 0.9 + 0.2 * noise.noise(co * 9.0))
        if 0.19 < co.z < 0.26 and math.hypot(co.x, co.y) > 0.215:
            return shade(IRON, 0.9)
        return shade(WOOD, 0.75 + 0.4 * noise.noise(Vector((math.atan2(co.y, co.x) * 3.0, co.z * 2.0, 2.0))))
    paint(bm, colour)
    export_glb("bucket", [new_object("bucket", bm)])


def sack():
    clear()
    random.seed(2)
    bm = bmesh.new()
    lathe(bm, [(0.05, 0.0), (0.2, 0.05), (0.26, 0.2), (0.24, 0.35), (0.14, 0.48), (0.07, 0.55), (0.1, 0.62), (0.07, 0.7)], segs=9, wobble=0.12, seed=5)
    finish(bm)
    bm.faces.index_update()
    def colour(co, normal, idx):
        if co.z > 0.5:
            return shade(TWINE, 0.9)
        return shade(CLOTH, 0.78 + 0.35 * noise.noise(co * 6.0 + Vector((1, 5, 2))))
    paint(bm, colour)
    export_glb("sack", [new_object("sack", bm)])


def stool():
    clear()
    bm = bmesh.new()
    lathe(bm, [(0.2, 0.42), (0.21, 0.47)], segs=10)
    for i in range(3):
        a = i / 3 * math.tau + 0.4
        before = len(bm.verts)
        rings = lathe(bm, [(0.026, 0.0), (0.02, 0.43)], segs=4)
        # lean the leg outward at the foot, then move it under the seat
        foot = Vector((math.cos(a) * 0.07, math.sin(a) * 0.07, 0.0))
        for v in list(bm.verts)[before:]:
            v.co.x += math.cos(a) * 0.12 + foot.x * (1.0 - v.co.z / 0.43)
            v.co.y += math.sin(a) * 0.12 + foot.y * (1.0 - v.co.z / 0.43)
    finish(bm)
    bm.faces.index_update()
    def colour(co, normal, idx):
        return shade(WOOD, 0.8 + 0.4 * noise.noise(co * 7.0))
    paint(bm, colour)
    export_glb("stool", [new_object("stool", bm)])


for fn in (barrel, crate, hay_bale, bucket, sack, stool):
    fn()
