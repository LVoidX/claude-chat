import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import *

clear()
random.seed(7)
bm = bmesh.new()

# trunk: a tapered, slightly bent column with a flared root
trunk_h = 2.6
segs = 7
rings = 5
verts = []
for r in range(rings + 1):
    t = r / rings
    y = t * trunk_h
    rad = (0.34 - 0.12 * t) * (1.0 + 0.5 * max(0.0, 1.0 - t * 4.0))  # flare at the foot
    bend = Vector((0.10 * math.sin(t * 2.4), 0.06 * math.sin(t * 3.1 + 1.0), 0))
    ring = []
    for s in range(segs):
        a = s / segs * math.tau
        wob = 1.0 + 0.10 * noise.noise(Vector((a * 2.0, t * 3.0, 1.3)))
        ring.append(bm.verts.new((math.cos(a) * rad * wob + bend.x, math.sin(a) * rad * wob + bend.y, y)))
    verts.append(ring)
for r in range(rings):
    for s in range(segs):
        a, b = verts[r][s], verts[r][(s + 1) % segs]
        c, d = verts[r + 1][(s + 1) % segs], verts[r + 1][s]
        bm.faces.new((a, b, c, d))
bmesh.ops.contain_coplanar_faces if False else None
top = verts[-1]
bm.faces.new(list(reversed(top)))
trunk_faces = [f.index for f in bm.faces]
bm.faces.ensure_lookup_table()
n_trunk = len(bm.faces)

# crown: clustered lumpy blobs (icospheres pushed around by noise), flat shaded
blobs = [((0, 0, 3.7), 1.55), ((0.95, 0.25, 3.2), 1.1), ((-0.9, -0.2, 3.3), 1.15), ((0.1, 0.85, 4.35), 1.05),
         ((-0.45, 0.7, 3.5), 0.95), ((0.6, -0.75, 3.85), 0.95), ((-0.25, -0.65, 4.4), 0.8)]
for centre, radius in blobs:
    geo = bmesh.ops.create_icosphere(bm, subdivisions=2, radius=radius)
    for v in geo["verts"]:
        v.co += Vector(centre)
    for v in geo["verts"]:
        n = noise.noise(v.co * 1.7 + Vector((3, 1, 2)))
        v.co += (v.co - Vector(centre)).normalized() * n * radius * 0.28
flat(bm)
bm.faces.ensure_lookup_table()

bark = hex_rgb("#5a3d2a")
leaf_lo = hex_rgb("#3d7a2e")
leaf_hi = hex_rgb("#9bc94a")

def colour(co, normal, idx):
    if idx < n_trunk:
        return shade(bark, 0.75 + 0.5 * noise.noise(co * 3.0))
    t = max(0.0, min(1.0, (co.z - 2.4) / 2.2))  # darker underneath, sunlit on top
    t = 0.15 + t * 0.55 + max(0.0, normal.z) * 0.3
    c = lerp(leaf_lo, leaf_hi, t)
    return shade(c, 0.85 + 0.3 * noise.noise(co * 1.9 + Vector((5, 5, 5))))

paint(bm, colour)
obj = new_object("oak", bm)
export_glb("oak", [obj])
preview("oak", [obj])
