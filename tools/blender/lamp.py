import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import *

WOOD = hex_rgb("#5a3d2a")
WOOD_DARK = hex_rgb("#3a281c")
IRON = hex_rgb("#2d2f33")


def beam(bm, a, b, r, kind):
    """A square beam from a to b (radius r), appended to the mesh; returns its faces' kind map entries."""
    d = (b - a)
    side = d.cross(Vector((0, 0, 1))) if abs(d.normalized().z) < 0.9 else d.cross(Vector((1, 0, 0)))
    side = side.normalized() * r
    up = d.cross(side).normalized() * r
    corners = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
    ring_a = [bm.verts.new(a + side * x + up * y) for x, y in corners]
    ring_b = [bm.verts.new(b + side * x + up * y) for x, y in corners]
    faces = []
    for i in range(4):
        faces.append(bm.faces.new((ring_a[i], ring_a[(i + 1) % 4], ring_b[(i + 1) % 4], ring_b[i])))
    faces.append(bm.faces.new(list(reversed(ring_a))))
    faces.append(bm.faces.new(ring_b))
    return [(f, kind) for f in faces]


def lamppost():
    """A wooden post with a curved bracket; the lantern hangs at (0.52, 1.82..2.1): the game adds the glass flame + light."""
    clear()
    random.seed(3)
    bm = bmesh.new()
    kinds = []
    # post: slightly tapered, leaning a hair, with a stone-footed base and a cap
    segs = 6
    prev = None
    for k, (z, r) in enumerate([(0.0, 0.11), (0.35, 0.085), (1.4, 0.07), (2.45, 0.065)]):
        ring = []
        for s in range(segs):
            a = s / segs * math.tau + 0.3
            wob = 1.0 + 0.08 * noise.noise(Vector((a * 2, z, 4)))
            ring.append(bm.verts.new((math.cos(a) * r * wob, math.sin(a) * r * wob, z)))
        if prev:
            for s in range(segs):
                kinds.append((bm.faces.new((prev[s], prev[(s + 1) % segs], ring[(s + 1) % segs], ring[s])), "post"))
        prev = ring
    kinds.append((bm.faces.new(prev), "post"))
    # a stone footing
    lathe(bm, [(0.2, 0.0), (0.22, 0.12), (0.14, 0.22)], segs=7, cap_top=False)
    # the arm: out from the top, with a diagonal brace back to the post
    kinds += beam(bm, Vector((0, 0, 2.5)), Vector((0.56, 0, 2.5)), 0.04, "arm")
    kinds += beam(bm, Vector((0.02, 0, 2.05)), Vector((0.42, 0, 2.47)), 0.025, "brace")
    kinds += beam(bm, Vector((0.54, 0, 2.5)), Vector((0.54, 0, 2.38)), 0.012, "iron")  # the hook
    # the lantern's iron frame (4 corner posts, lid, base): the glass flame is made by the game inside it
    cx, cz = 0.54, 1.82
    for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
        kinds += beam(bm, Vector((cx + sx * 0.1, sy * 0.1, cz)), Vector((cx + sx * 0.1, sy * 0.1, cz + 0.3)), 0.008, "iron")
    for zz, hh in ((cz - 0.02, 0.02), (cz + 0.3, 0.03)):
        kinds += beam(bm, Vector((cx - 0.12, 0, zz)), Vector((cx + 0.12, 0, zz)), 0.12, "iron")
    # a little pointed roof on the lantern
    top = bm.verts.new((cx, 0, cz + 0.42))
    base = [bm.verts.new((cx + math.cos(a) * 0.15, math.sin(a) * 0.15, cz + 0.33)) for a in (0, math.pi / 2, math.pi, 3 * math.pi / 2)]
    for i in range(4):
        kinds.append((bm.faces.new((base[i], base[(i + 1) % 4], top)), "iron"))
    bm.faces.index_update()
    k = {f.index: n for f, n in kinds if f.is_valid}

    def colour(co, normal, idx):
        n = k.get(idx, "stone")
        if n == "post":
            return shade(WOOD, 0.75 + 0.45 * noise.noise(Vector((co.x * 6, co.y * 6, co.z * 2.5))))
        if n == "arm" or n == "brace":
            return shade(WOOD_DARK, 0.85 + 0.3 * noise.noise(co * 8.0))
        if n == "iron":
            return shade(IRON, 0.9 + 0.2 * noise.noise(co * 12.0))
        return shade(hex_rgb("#7d7a74"), 0.8 + 0.4 * noise.noise(co * 5.0))  # the stone footing
    paint(bm, colour)
    export_glb("lamppost", [new_object("lamppost", bm)])


def fence_section():
    """One fence bay, 2 m long along X: two posts' worth of rails and one post at the start; rails sag and are rough-hewn."""
    clear()
    random.seed(8)
    bm = bmesh.new()
    kinds = []
    segs = 5
    for post_x in (0.0,):
        prev = None
        for z, r in ((0.0, 0.085), (0.6, 0.075), (1.15, 0.07), (1.22, 0.05)):
            ring = []
            for s in range(segs):
                a = s / segs * math.tau + post_x
                ring.append(bm.verts.new((post_x + math.cos(a) * r, math.sin(a) * r, z + noise.noise(Vector((a, z, 1))) * 0.02)))
            if prev:
                for s in range(segs):
                    kinds.append((bm.faces.new((prev[s], prev[(s + 1) % segs], ring[(s + 1) % segs], ring[s])), "post"))
            prev = ring
        kinds.append((bm.faces.new(prev), "post"))
    for z in (0.5, 0.92):
        a = Vector((0.0, 0.0, z + 0.02))
        b = Vector((2.0, 0.0, z - 0.02 + (random.random() - 0.5) * 0.03))
        kinds += beam(bm, a, b, 0.035, "rail")
    bm.faces.index_update()
    k = {f.index: n for f, n in kinds if f.is_valid}

    def colour(co, normal, idx):
        n = k.get(idx, "post")
        wood = hex_rgb("#6b4a2b") if n == "post" else hex_rgb("#7a5532")
        c = shade(wood, 0.72 + 0.5 * noise.noise(Vector((co.x * 3.0, co.y * 9.0, co.z * 9.0))))
        if co.z > 1.1 and n == "post":
            c = shade(c, 1.15)  # the sawn top is paler
        return c
    paint(bm, colour)
    export_glb("fence", [new_object("fence", bm)])


lamppost()
fence_section()
