import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import *
from lamp import beam


def deer():
    """A deer standing: barrel body, long neck, small head, four slim legs, a pale rump patch and short antlers. Front is +Y (-Z in the game); ~1.5 m long, 1.2 m at the shoulder."""
    clear()
    random.seed(11)
    bm = bmesh.new()
    kinds = []

    def blob(centre, radii, kind, subdiv=1):
        geo = bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=1.0)
        for v in geo["verts"]:
            v.co = Vector((v.co.x * radii[0], v.co.y * radii[1], v.co.z * radii[2])) + Vector(centre)
        for f in {f for v in geo["verts"] for f in v.link_faces}:
            kinds.append((f, kind))
    blob((0, 0.0, 0.85), (0.2, 0.48, 0.24), "fur", 2)  # body
    blob((0, -0.42, 0.88), (0.2, 0.16, 0.22), "rump")  # rump
    blob((0, 0.62, 1.2), (0.09, 0.1, 0.22), "fur")  # neck (leaning forward)
    blob((0, 0.74, 1.4), (0.08, 0.16, 0.08), "head")  # head
    for side in (-1, 1):
        blob((side * 0.07, 0.68, 1.5), (0.02, 0.04, 0.09), "ear")
    for lx, ly in ((-0.11, 0.34), (0.11, 0.34), (-0.11, -0.4), (0.11, -0.4)):  # legs: hip to hoof
        kinds += [(f, "leg") for f in beam_faces(bm, Vector((lx, ly, 0.75)), Vector((lx * 0.9, ly + 0.02, 0.05)), 0.035)]
    for side in (-1, 1):  # antlers: a main beam with two tines
        a = Vector((side * 0.05, 0.7, 1.46))
        b = Vector((side * 0.14, 0.64, 1.72))
        kinds += [(f, "horn") for f in beam_faces(bm, a, b, 0.012)]
        kinds += [(f, "horn") for f in beam_faces(bm, a.lerp(b, 0.5), a.lerp(b, 0.5) + Vector((side * 0.1, 0.1, 0.12)), 0.01)]
        kinds += [(f, "horn") for f in beam_faces(bm, b, b + Vector((side * 0.06, -0.08, 0.12)), 0.01)]
    bm.faces.index_update()
    k = {}
    for f, n in kinds:
        if f.is_valid:
            k[f.index] = n

    def colour(co, normal, idx):
        n = k.get(idx, "fur")
        if n == "horn":
            return hex_rgb("#d8caa6")
        if n == "leg":
            return shade(hex_rgb("#6b4a30"), 0.8 + 0.3 * noise.noise(co * 9.0)) if co.z > 0.12 else hex_rgb("#2a2018")
        if n == "rump" and normal.y < -0.4:
            return hex_rgb("#e9dfc8")  # the pale rump patch
        if n == "head":
            return shade(hex_rgb("#7a5a40"), 1.0 - (0.5 if co.y > 0.88 and co.z < 1.42 else 0.0))  # dark muzzle
        if n == "ear":
            return hex_rgb("#a07a58")
        c = shade(hex_rgb("#8e6642"), 0.8 + 0.4 * noise.noise(co * 6.0))
        if normal.z < -0.3:
            c = lerp(c, hex_rgb("#d8cbb0"), 0.8)  # pale belly
        return c
    flat(bm)
    paint(bm, colour)
    export_glb("deer", [new_object("deer", bm)])


def beam_faces(bm, a, b, r):
    return [f for f, _ in beam(bm, a, b, r, "x")]


deer()
