import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import *

def make_rock(name, seed, squash, lumps):
    clear()
    random.seed(seed)
    bm = bmesh.new()
    geo = bmesh.ops.create_icosphere(bm, subdivisions=2, radius=1.0)
    for v in geo["verts"]:
        v.co.z *= squash
        v.co.x *= 1.0 + 0.25 * noise.noise(Vector((seed, 0.3, 0.7)))
        n = noise.noise(v.co * lumps + Vector((seed, seed * 1.7, 3)))
        v.co += v.co.normalized() * n * 0.38
        if v.co.z < -0.15:  # flat underside, so it sits on the ground
            v.co.z = -0.15 + (v.co.z + 0.15) * 0.2
    flat(bm)
    stone = hex_rgb("#7d7a74")
    moss = hex_rgb("#5d7a3a")
    def colour(co, normal, idx):
        c = shade(stone, 0.75 + 0.5 * noise.noise(co * 3.1 + Vector((seed, 2, 1))))
        if normal.z > 0.55:  # moss on the top faces
            c = lerp(c, moss, min(1.0, (normal.z - 0.55) * 2.2) * 0.8)
        if co.z < 0.0:
            c = shade(c, 0.7)
        return c
    paint(bm, colour)
    obj = new_object(name, bm)
    export_glb(name, [obj])

make_rock("rock1", 3, 0.62, 1.4)
make_rock("rock2", 8, 0.8, 1.9)
make_rock("rock3", 15, 0.5, 1.2)
