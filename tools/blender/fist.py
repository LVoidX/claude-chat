import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import *
from lamp import beam

# The first-person sword hand (hotbar.gd): a leather-gloved fist closed round the grip. Built round the grip's own axis
# (Blender +Z = Godot +Y, along the grip), so the fingers really wrap the handle. The camera sees the Godot +Z side,
# which is Blender -Y. Angles below are measured in Godot's X-Z plane (0 = +X, 90 = +Z towards the viewer).
# Chunky square-section segments, flat shaded, to match the low-poly world (the old hand was smooth capsules).

R = 0.029  # distance of a finger's middle from the grip's axis (grip radius ~0.017 + half a finger)


def at(angle_deg, r, y):
    a = math.radians(angle_deg)
    return Vector((math.cos(a) * r, -math.sin(a) * r, y))


def box(bm, centre, size, rot_z, kind, kinds):
    geo = bmesh.ops.create_cube(bm, size=1.0)
    m = Matrix.Rotation(math.radians(rot_z), 4, "Z")
    for v in geo["verts"]:
        v.co = m @ Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2])) + centre
    for f in {f for v in geo["verts"] for f in v.link_faces}:
        kinds.append((f, kind))


def fist():
    clear()
    bm = bmesh.new()
    kinds = []
    # four fingers, index at the top (next to the guard), little finger smallest at the bottom
    path = [150, 98, 45, -8, -55]
    for i, (y, s) in enumerate(((0.03, 1.0), (0.007, 1.0), (-0.016, 0.95), (-0.037, 0.82))):
        pts = [at(a, R * (1.0 if j < 4 else 0.92), y) for j, a in enumerate(path)]
        for j in range(len(pts) - 1):
            kinds += beam(bm, pts[j], pts[j + 1], 0.0098 * s, "finger" if j > 0 else "knuckle")
        kinds += beam(bm, at(150, R - 0.004, y), at(150, R + 0.012, y), 0.0105 * s, "knuckle")  # the knuckle, standing proud
    # back of the hand, running from the knuckles out towards the wrist side, and the palm on the far side
    box(bm, at(172, 0.043, -0.004), (0.03, 0.026, 0.09), -8, "back", kinds)
    box(bm, at(-105, 0.034, -0.004), (0.05, 0.02, 0.088), 15, "palm", kinds)
    # the thumb closes over the index finger from the far side
    t = [at(-160, 0.046, 0.05), at(150, 0.037, 0.056), at(100, 0.032, 0.052), at(58, 0.03, 0.047)]
    for j in range(len(t) - 1):
        kinds += beam(bm, t[j], t[j + 1], 0.0108, "thumb")
    bm.faces.index_update()
    k = {f.index: n for f, n in kinds if f.is_valid}
    leather = hex_rgb("#6b4a2f")

    def colour(co, normal, idx):
        n = k.get(idx, "finger")
        c = shade(leather, 0.85 + 0.25 * noise.noise(co * 70.0))
        if n == "knuckle":
            c = shade(c, 1.22)  # worn paler where the glove bends
        elif n == "back":
            c = shade(c, 0.92)
            if abs(co.z) < 0.004:
                c = shade(c, 0.7)  # a stitched seam down the back
        elif n == "thumb":
            c = shade(c, 1.08)
        elif n == "palm":
            c = shade(c, 0.8)
        return c
    flat(bm)
    paint(bm, colour)
    export_glb("fist", [new_object("fist", bm)])


fist()
