import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import *

# one roof per cottage in village.gd HOUSES: (width, depth); the roof is wider/longer than the house by the overhang
HOUSES = [(5.0, 7.0), (4.5, 6.0), (5.5, 8.0), (4.5, 6.5), (4.0, 5.5)]
HEIGHT = 2.8  # the roof's rise (matches the old prism)
COURSES = 7

STRAW = hex_rgb("#c9a45c")
STRAW_LIGHT = hex_rgb("#e3c880")
STRAW_DARK = hex_rgb("#8d6c35")
MOSS = hex_rgb("#6e8238")
WOOD = hex_rgb("#4a3220")


def make_roof(name, w, d):
    clear()
    random.seed(int(w * 100 + d * 10))
    W_ = w + 1.2
    D_ = d + 1.1
    hw = W_ / 2.0
    L = math.hypot(hw, HEIGHT)
    bm = bmesh.new()
    cols = max(8, int(D_ / 0.42))

    def slope_point(side, t, yb, push):
        """A point on the roof slope: t 0 at the eave .. 1 at the ridge, yb along the ridge, push out along the normal."""
        x = side * hw * (1.0 - t)
        z = HEIGHT * t
        n = Vector((side * HEIGHT, 0.0, hw)) / L  # outward normal of the slope
        return Vector((x, yb, z)) + n * push

    for side in (-1, 1):
        for k in range(COURSES):
            t0, t1 = k / COURSES, (k + 1) / COURSES
            lows, highs = [], []
            for c in range(cols + 1):
                yb = -D_ / 2.0 + D_ * c / cols
                ragged = (random.random() - 0.5) * 0.03
                lows.append(bm.verts.new(slope_point(side, max(0.0, t0 + ragged - 0.02), yb, 0.10 + random.random() * 0.05)))
                highs.append(bm.verts.new(slope_point(side, t1 + 0.012, yb, 0.0 + (random.random() - 0.5) * 0.02)))
            for c in range(cols):
                quad = (lows[c], lows[c + 1], highs[c + 1], highs[c])
                bm.faces.new(quad if side > 0 else tuple(reversed(quad)))
            if k > 0:  # a riser under the overhanging lower edge, so there is no slit into the dark behind it
                under = []
                for c in range(cols + 1):
                    yb = lows[c].co.y
                    tt = max(0.0, (lows[c].co.z / HEIGHT))
                    under.append(bm.verts.new(slope_point(side, tt - 0.03, yb, 0.0)))
                for c in range(cols):
                    quad = (under[c], under[c + 1], lows[c + 1], lows[c])
                    bm.faces.new(quad if side > 0 else tuple(reversed(quad)))

    # the ridge roll: a hexagonal bundle along the top, a little longer than the roof
    ring_r = 0.21
    ends = (-D_ / 2.0 - 0.14, D_ / 2.0 + 0.14)
    rings = []
    for yb in ends:
        ring = []
        for s in range(6):
            a = s / 6 * math.tau
            ring.append(bm.verts.new((math.cos(a) * ring_r * 1.2, yb, HEIGHT + 0.04 + math.sin(a) * ring_r)))
        rings.append(ring)
    for s in range(6):
        bm.faces.new((rings[0][s], rings[0][(s + 1) % 6], rings[1][(s + 1) % 6], rings[1][s]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[1])

    # gable ends (dark boards) and the underside
    for yb in (-D_ / 2.0 + 0.04, D_ / 2.0 - 0.04):
        tri = [bm.verts.new((-hw + 0.05, yb, 0.0)), bm.verts.new((hw - 0.05, yb, 0.0)), bm.verts.new((0.0, yb, HEIGHT - 0.1))]
        bm.faces.new(tri if yb > 0 else list(reversed(tri)))
    under = [bm.verts.new(p) for p in ((-hw, -D_ / 2.0, -0.02), (hw, -D_ / 2.0, -0.02), (hw, D_ / 2.0, -0.02), (-hw, D_ / 2.0, -0.02))]
    bm.faces.new(list(reversed(under)))

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    flat(bm)

    def colour(co, normal, idx):
        if normal.z < -0.5 or abs(normal.y) > 0.9:  # underside and gable ends: dark boards
            return shade(WOOD, 0.8 + 0.4 * noise.noise(co * 3.0))
        if co.z > HEIGHT - 0.1 and abs(co.x) < 0.3:  # the ridge roll
            return shade(STRAW_DARK, 0.85 + 0.35 * noise.noise(co * 5.0 + Vector((1, 1, 1))))
        t = co.z / HEIGHT
        local = (t * COURSES) % 1.0  # 0 at a course's lower edge .. 1 under the next course
        base = lerp(STRAW, STRAW_LIGHT, 0.5 + 0.5 * noise.noise(Vector((co.y * 1.7, t * 5.0, 3.0))))
        c = shade(base, 0.74 + 0.36 * local)  # each course dark where it overhangs, light on top
        c = shade(c, 0.88 + 0.24 * noise.noise(co * 2.2 + Vector((7, 7, 7))))
        if noise.noise(co * 1.1 + Vector((2, 9, 4))) > 0.30 and t < 0.6:  # moss near the eaves
            c = lerp(c, MOSS, min(0.85, (noise.noise(co * 1.1 + Vector((2, 9, 4))) - 0.30) * 3.0))
        return c

    paint(bm, colour)
    obj = new_object(name, bm)
    export_glb(name, [obj])


for i, (w, d) in enumerate(HOUSES):
    make_roof("roof_%d" % i, w, d)
