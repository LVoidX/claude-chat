import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import *
from lamp import beam


def dog(name, coat_hex, patch_hex):
    """A shaggy farm dog standing: body, chest, head with a snout and floppy ears, four legs, a curled tail. Front is +Y (-Z in the game); ~0.9 m long, 0.55 m tall."""
    clear()
    random.seed(13)
    bm = bmesh.new()
    kinds = []

    def blob(centre, radii, kind, subdiv=1):
        geo = bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=1.0)
        for v in geo["verts"]:
            v.co = Vector((v.co.x * radii[0], v.co.y * radii[1], v.co.z * radii[2])) + Vector(centre)
        for f in {f for v in geo["verts"] for f in v.link_faces}:
            kinds.append((f, kind))
    blob((0, 0.0, 0.34), (0.13, 0.3, 0.14), "coat", 2)  # body
    blob((0, 0.2, 0.38), (0.14, 0.14, 0.15), "coat")  # chest
    blob((0, 0.4, 0.5), (0.085, 0.1, 0.085), "head")  # head
    blob((0, 0.5, 0.47), (0.04, 0.07, 0.035), "snout")  # snout
    for side in (-1, 1):
        blob((side * 0.075, 0.38, 0.5), (0.025, 0.05, 0.07), "ear")
    for lx, ly in ((-0.07, 0.2), (0.07, 0.2), (-0.07, -0.2), (0.07, -0.2)):
        kinds += [(f, "leg") for f, _ in beam(bm, Vector((lx, ly, 0.3)), Vector((lx, ly, 0.03)), 0.028, "x")]
    kinds += [(f, "coat") for f, _ in beam(bm, Vector((0, -0.28, 0.4)), Vector((0, -0.4, 0.55)), 0.03, "x")]  # tail up and back
    bm.faces.index_update()
    k = {}
    for f, n in kinds:
        if f.is_valid:
            k[f.index] = n
    coat = hex_rgb(coat_hex)
    patch = hex_rgb(patch_hex)

    def colour(co, normal, idx):
        n = k.get(idx, "coat")
        if n == "snout":
            return hex_rgb("#3a2e28") if co.y > 0.54 else shade(coat, 1.1)
        if n == "ear":
            return shade(patch, 0.8)
        if n == "leg":
            return shade(coat, 1.15) if co.z < 0.12 else shade(coat, 0.9)
        c = shade(coat, 0.8 + 0.4 * noise.noise(co * 10.0))
        if co.x > 0.02 and co.z > 0.3 and n == "coat":
            c = lerp(c, patch, 0.8)  # a patch on the back
        if normal.z < -0.3:
            c = shade(c, 1.25)
        return c
    flat(bm)
    paint(bm, colour)
    export_glb(name, [new_object(name, bm)])


dog("dog", "#b78a56", "#4a3524")
