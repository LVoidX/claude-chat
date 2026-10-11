import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import *

clear()
random.seed(5)
bm = bmesh.new()
for centre, radius in [((0, 0, 0.5), 0.65), ((0.5, 0.15, 0.4), 0.45), ((-0.45, -0.1, 0.42), 0.48), ((0.1, -0.45, 0.38), 0.4)]:
    geo = bmesh.ops.create_icosphere(bm, subdivisions=2, radius=radius)
    for v in geo["verts"]:
        v.co += Vector(centre)
        n = noise.noise(v.co * 2.3 + Vector((1, 2, 3)))
        v.co += (v.co - Vector(centre)).normalized() * n * radius * 0.3
        if v.co.z < 0.05:
            v.co.z = 0.05
flat(bm)
lo = hex_rgb("#3c6b2a")
hi = hex_rgb("#8cbc48")
berry = hex_rgb("#c0392b")
def colour(co, normal, idx):
    t = max(0.0, min(1.0, co.z / 1.0)) * 0.6 + max(0.0, normal.z) * 0.4
    c = lerp(lo, hi, t)
    c = shade(c, 0.85 + 0.3 * noise.noise(co * 2.7 + Vector((4, 4, 4))))
    if noise.noise(co * 6.0 + Vector((9, 9, 9))) > 0.42 and normal.z > 0.2:  # a few berries
        c = berry
    return c
paint(bm, colour)
obj = new_object("bush", bm)
export_glb("bush", [obj])
