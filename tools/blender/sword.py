import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import *
from lamp import beam


def sword(name, steel_hex, brass_hex, rusty=False, glow=False):
    """A longsword standing along +Z (Godot +Y) with the hilt at the origin: guard at 0, blade 0.085..1.2 m, grip below to -0.19.
    The blade is diamond-sectioned with a fuller; flat faces point along Blender -Y/+Y (Godot Z). Colours painted per face."""
    clear()
    random.seed(17)
    bm = bmesh.new()
    kinds = []
    # blade: rings of a flattened hexagon, tapering to a point
    levels = [(0.085, 0.11), (0.38, 0.1), (0.78, 0.075), (1.0, 0.05), (1.2, 0.002)]
    rings = []
    for z, half in levels:
        thick = 0.016 if z < 1.19 else 0.002
        rings.append([bm.verts.new(p) for p in ((-half, 0, z), (-half * 0.4, -thick, z), (half * 0.4, -thick, z), (half, 0, z),
                                                 (half * 0.4, thick, z), (-half * 0.4, thick, z))])
    for i in range(len(rings) - 1):
        a, b = rings[i], rings[i + 1]
        for k in range(6):
            n = (k + 1) % 6
            kinds.append((bm.faces.new((a[k], a[n], b[n], b[k])), "edge" if k in (0, 2, 3, 5) else "flat"))
    kinds.append((bm.faces.new(list(reversed(rings[0]))), "flat"))
    # guard: a curved crossguard made of two beams and a boss
    for side in (-1, 1):
        kinds += beam(bm, Vector((0, 0, 0.02)), Vector((side * 0.14, 0, 0.0)), 0.022, "brass")
        kinds += beam(bm, Vector((side * 0.14, 0, 0.0)), Vector((side * 0.165, 0, -0.025)), 0.022, "brass")
    kinds += beam(bm, Vector((0, 0, 0.0)), Vector((0, 0, 0.09)), 0.045, "brass")  # ricasso collar
    # grip with wrap rings, then a round pommel
    kinds += beam(bm, Vector((0, 0, -0.17)), Vector((0, 0, -0.0)), 0.03, "grip")
    for i in range(5):
        z = -0.02 - i * 0.032
        kinds += beam(bm, Vector((0, 0, z)), Vector((0, 0, z - 0.012)), 0.036, "wrap" if i % 2 == 0 else "grip")
    geo = bmesh.ops.create_icosphere(bm, subdivisions=1, radius=0.045)
    for v in geo["verts"]:
        v.co.z -= 0.19
    for f in {f for v in geo["verts"] for f in v.link_faces}:
        kinds.append((f, "brass"))
    bm.faces.index_update()
    k = {}
    for f, n in kinds:
        if f.is_valid:
            k[f.index] = n
    steel = hex_rgb(steel_hex)
    brass = hex_rgb(brass_hex)

    def colour(co, normal, idx):
        n = k.get(idx, "flat")
        if n == "brass":
            return shade(brass, 0.85 + 0.3 * noise.noise(co * 25.0))
        if n == "grip":
            return hex_rgb("#493020")
        if n == "wrap":
            return hex_rgb("#9b7651")
        c = shade(steel, (0.95 if n == "edge" else 0.78) + 0.1 * noise.noise(co * 8.0))
        if abs(co.x) < 0.03 and 0.15 < co.z < 1.05:
            c = shade(c, 0.55)  # the fuller: a darker line down the middle
        if rusty and noise.noise(co * 14.0 + Vector((3, 1, 2))) > 0.22:
            c = lerp(c, hex_rgb("#805032"), 0.8)
        return c
    flat(bm)
    paint(bm, colour)
    export_glb(name, [new_object(name, bm)])


sword("sword_rusty", "#8f8478", "#776044", rusty=True)
sword("sword_iron", "#bac5ce", "#c99c51")
sword("sword_steel", "#91b7e3", "#c99c51")
