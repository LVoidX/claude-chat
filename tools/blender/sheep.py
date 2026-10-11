import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import *


def sheep_body(name, seed, wool_hex):
    """The fleece: a lumpy low-poly ellipsoid, 0.7 x 1.05 x 0.6 m, centred 0.66 m up; the front is +Y here (-Z in the game).
    The game adds the head, legs and tail as boxes so they can move."""
    clear()
    random.seed(seed)
    bm = bmesh.new()
    geo = bmesh.ops.create_icosphere(bm, subdivisions=2, radius=1.0)
    for v in geo["verts"]:
        v.co.x *= 0.35
        v.co.y *= 0.54
        v.co.z *= 0.31
        n = noise.noise(v.co * 4.5 + Vector((seed, seed * 1.3, 2)))
        v.co += v.co.normalized() * n * 0.09
        v.co.z += 0.66
    flat(bm)
    wool = hex_rgb(wool_hex)

    def colour(co, normal, idx):
        c = shade(wool, 0.82 + 0.32 * noise.noise(co * 6.0 + Vector((seed, 1, 2))))
        if co.z < 0.55:
            c = shade(c, 0.78)  # the belly is in shadow
        return c
    paint(bm, colour)
    export_glb(name, [new_object(name, bm)])


sheep_body("sheep_body_0", 2, "#ebe6d8")
sheep_body("sheep_body_1", 5, "#d9d2c0")
sheep_body("sheep_body_2", 9, "#a9a49a")
