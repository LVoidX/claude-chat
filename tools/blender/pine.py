import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import *

clear()
random.seed(11)
bm = bmesh.new()

def tier(zc, radius, height, segs=9, droop=0.25, jag=0.22, seed=0):
    """One bough layer: a skirt of triangles with a ragged lower edge, apex above, closed underneath."""
    apex = bm.verts.new((0, 0, zc + height))
    ring = []
    for i in range(segs):
        a = i / segs * math.tau + seed
        r = radius * (1.0 + (random.random() - 0.5) * jag * 2.0)
        z = zc - droop * random.random()
        # alternate points reach further out so the skirt looks like separate boughs
        r *= 1.0 if i % 2 == 0 else 0.72
        ring.append(bm.verts.new((math.cos(a) * r, math.sin(a) * r, z)))
    centre = bm.verts.new((0, 0, zc - 0.05))
    for i in range(segs):
        a, b = ring[i], ring[(i + 1) % segs]
        bm.faces.new((a, b, apex))
        bm.faces.new((b, a, centre))

# trunk: a short tapered post (mostly hidden by the boughs)
trunk = []
for r_i, (z, rad) in enumerate([(0.0, 0.30), (0.7, 0.22), (1.6, 0.16)]):
    ring = []
    for s in range(6):
        a = s / 6 * math.tau
        ring.append(bm.verts.new((math.cos(a) * rad, math.sin(a) * rad, z)))
    trunk.append(ring)
for r in range(2):
    for s in range(6):
        bm.faces.new((trunk[r][s], trunk[r][(s + 1) % 6], trunk[r + 1][(s + 1) % 6], trunk[r + 1][s]))
bm.faces.ensure_lookup_table()
n_trunk = len(bm.faces)

tiers = [(1.0, 2.15, 1.55), (2.0, 1.85, 1.5), (3.0, 1.5, 1.4), (3.95, 1.15, 1.3), (4.8, 0.8, 1.25), (5.55, 0.45, 1.15)]
for k, (zc, rad, h) in enumerate(tiers):
    tier(zc, rad, h, segs=9 if k < 4 else 7, seed=k * 0.7)
flat(bm)
bm.faces.ensure_lookup_table()

bark = hex_rgb("#4d3524")
lo = hex_rgb("#2a5a35")
hi = hex_rgb("#6fa04a")
tier_z = [t[0] for t in tiers]

def colour(co, normal, idx):
    if idx < n_trunk:
        return shade(bark, 0.8 + 0.4 * noise.noise(co * 4.0))
    # within each tier: dark at the skirt's lower edge, lighter toward its apex; upper tiers a bit lighter
    base = max(z for z in tier_z if z <= co.z + 0.4 + 1e-6) if co.z + 0.4 >= tier_z[0] else tier_z[0]
    k = 0
    for i, z in enumerate(tier_z):
        if co.z >= z - 0.4:
            k = i
    local = max(0.0, min(1.0, (co.z - (tier_z[k] - 0.25)) / (tiers[k][2] + 0.25)))
    t = local * 0.7 + (k / len(tiers)) * 0.25 + max(0.0, normal.z) * 0.1
    return shade(lerp(lo, hi, t), 0.85 + 0.3 * noise.noise(co * 2.3 + Vector((9, 1, 4))))


paint(bm, colour)
obj = new_object("pine", bm)
export_glb("pine", [obj])
