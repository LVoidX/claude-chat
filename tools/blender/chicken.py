import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import *


def chicken_body(name, seed, hex_main):
    """A plump hen body with a tail fan and wing bumps; front is +Y here (-Z in the game). Head, legs are boxes in animals.gd."""
    clear()
    random.seed(seed)
    bm = bmesh.new()
    geo = bmesh.ops.create_icosphere(bm, subdivisions=2, radius=1.0)
    for v in geo["verts"]:
        v.co.x *= 0.13
        v.co.y *= 0.19
        v.co.z *= 0.12
        v.co += v.co.normalized() * noise.noise(v.co * 9.0 + Vector((seed, 0, 1))) * 0.018
        if v.co.y > 0.1 and v.co.z > 0.0:
            v.co.z += (v.co.y - 0.1) * 0.35  # the chest sticks out and up
        v.co.z += 0.25
    # a tail: a fan of three pointed feathers at the back
    tail = []
    for k, ang in enumerate((-0.4, 0.0, 0.4)):
        base = Vector((math.sin(ang) * 0.03, -0.15, 0.3))
        tip = Vector((math.sin(ang) * 0.1, -0.27, 0.42 + 0.02 * k % 2))
        a = bm.verts.new(base + Vector((-0.03, 0, 0)))
        b = bm.verts.new(base + Vector((0.03, 0, 0)))
        c = bm.verts.new(base + Vector((0, 0.03, -0.05)))
        t = bm.verts.new(tip)
        for tri in ((a, b, t), (b, c, t), (c, a, t)):
            tail.append(bm.faces.new(tri))
    flat(bm)
    main = hex_rgb(hex_main)

    def colour(co, normal, idx):
        c = shade(main, 0.85 + 0.3 * noise.noise(co * 14.0 + Vector((seed, 3, 1))))
        if co.y < -0.14:
            c = shade(c, 0.8)  # tail feathers a little darker
        if abs(co.x) > 0.095 and 0.2 < co.z < 0.33:
            c = shade(c, 0.92)  # the folded wings
        return c
    paint(bm, colour)
    export_glb(name, [new_object(name, bm)])


chicken_body("chicken_body_0", 3, "#f2ede2")
chicken_body("chicken_body_1", 7, "#a8643a")
