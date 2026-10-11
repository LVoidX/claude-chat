import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import *
from lamp import beam


def footbridge():
    """A plank footbridge, 6 m long along X, 1.7 m wide, deck at y = 0.25 (z up in Blender), with rails and posts."""
    clear()
    random.seed(21)
    bm = bmesh.new()
    kinds = []
    # two stringers under the deck
    for y in (-0.6, 0.6):
        kinds += beam(bm, Vector((-3.1, y, 0.1)), Vector((3.1, y, 0.1)), 0.09, "beam")
    # planks
    n = 20
    for i in range(n):
        x = -2.9 + i * (5.8 / (n - 1))
        w = 0.14 + random.random() * 0.02
        kinds += beam(bm, Vector((x, -0.85, 0.22 + random.random() * 0.01)), Vector((x, 0.85, 0.22 + random.random() * 0.01)), 0.0 + w / 2, "plank")
    # posts and rails
    for y in (-0.82, 0.82):
        for x in (-2.9, -1.0, 1.0, 2.9):
            kinds += beam(bm, Vector((x, y, 0.2)), Vector((x, y, 1.1)), 0.05, "post")
        for z in (0.7, 1.05):
            kinds += beam(bm, Vector((-2.9, y, z)), Vector((2.9, y, z)), 0.035, "post")
    bm.faces.index_update()
    k = {f.index: n for f, n in kinds if f.is_valid}

    def colour(co, normal, idx):
        n = k.get(idx, "plank")
        base = {"plank": "#8a6a45", "beam": "#4a3423", "post": "#6b4a2b"}[n]
        return shade(hex_rgb(base), 0.72 + 0.5 * noise.noise(Vector((co.x * 3.0, co.y * 9.0, co.z * 9.0))))
    paint(bm, colour)
    export_glb("footbridge", [new_object("footbridge", bm)])


footbridge()
