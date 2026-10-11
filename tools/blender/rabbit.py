import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import *


def rabbit():
    """A wild rabbit sitting up a little: body, haunch, head, long ears, a white tail puff. Front is +Y (-Z in the game); ~0.35 m long."""
    clear()
    random.seed(4)
    bm = bmesh.new()
    kinds = []

    def blob(centre, radii, kind, subdiv=1):
        geo = bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=1.0)
        for v in geo["verts"]:
            v.co = Vector((v.co.x * radii[0], v.co.y * radii[1], v.co.z * radii[2])) + Vector(centre)
        for f in {f for v in geo["verts"] for f in v.link_faces}:
            kinds.append((f, kind))
    blob((0, 0.0, 0.13), (0.09, 0.17, 0.12), "fur")  # body
    blob((0, -0.1, 0.12), (0.1, 0.1, 0.12), "fur")  # haunch
    blob((0, 0.17, 0.2), (0.06, 0.08, 0.06), "head")  # head
    blob((0, -0.2, 0.15), (0.04, 0.04, 0.04), "tail")  # tail puff
    for side in (-1, 1):  # ears: tall flattened blobs leaning back
        blob((side * 0.03, 0.15, 0.31), (0.018, 0.012, 0.09), "ear")
    bm.faces.index_update()
    k = {}
    for f, n in kinds:
        if f.is_valid:
            k[f.index] = n

    def colour(co, normal, idx):
        n = k.get(idx, "fur")
        if n == "tail":
            return hex_rgb("#f2eee6")
        if n == "ear":
            return lerp(hex_rgb("#8a6d52"), hex_rgb("#d9a8a0"), 0.5 if normal.y > 0 else 0.0)
        base = hex_rgb("#8c6b4c") if n == "fur" else hex_rgb("#7d6046")
        c = shade(base, 0.8 + 0.4 * noise.noise(co * 18.0))
        if normal.z < -0.3:
            c = lerp(c, hex_rgb("#d8cfc0"), 0.7)  # pale belly
        return c
    flat(bm)
    paint(bm, colour)
    export_glb("rabbit", [new_object("rabbit", bm)])


rabbit()
