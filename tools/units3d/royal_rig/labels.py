"""Phase 1d step 4-5: the Tripo parts' ids onto the fused mesh `royal` as the int attribute
`part` (nearest aligned part point, then a 3-pass neighbour majority), and the thin straps
found by thickness. Run after common.py in the same namespace:

    exec(open(".../common.py").read(), G); exec(open(".../labels.py").read(), G)
    G["transfer"]()
"""
import csv
from mathutils import kdtree

ROLES = os.path.join(os.path.dirname(os.path.abspath(globals().get("__file__") or ROOT + "tools/units3d/royal_rig/labels.py")), "parts.csv")


def roles():
    with open(ROLES) as f:
        return {int(r["part"]): r for r in csv.DictReader(f)}


def neighbours(me):
    nb = [[] for _ in me.vertices]
    for e in me.edges:
        a, b = e.vertices
        nb[a].append(b); nb[b].append(a)
    return nb


def transfer(passes=3):
    o = mesh()
    ps = parts()
    pts, ids = [], []
    for p in ps:
        n = int(p.name.split("_")[-1])
        c = co(p)
        pts.append(c); ids += [n] * len(c)
    P = np.vstack(pts)
    kd = kdtree.KDTree(len(P))
    for i, p in enumerate(P):
        kd.insert(p, i)
    kd.balance()
    V = co(o)
    lab = np.array([ids[kd.find(v)[1]] for v in V])
    nb = neighbours(o.data)
    for _ in range(passes):
        new = lab.copy()
        for i, ns in enumerate(nb):
            if not ns:
                continue
            vals, cnt = np.unique(lab[ns], return_counts=True)
            k = np.argmax(cnt)
            if vals[k] != lab[i] and cnt[k] > len(ns) / 2:
                new[i] = vals[k]
        lab = new
    write_int(o, "part", lab)
    u, c = np.unique(lab, return_counts=True)
    return {int(a): int(b) for a, b in zip(u, c)}


def write_int(o, name, values):
    at = o.data.attributes.get(name) or o.data.attributes.new(name, "INT", "POINT")
    at.data.foreach_set("value", [int(x) for x in values])


def read_int(o, name):
    at = o.data.attributes[name]
    a = np.empty(len(at.data), dtype=np.int64)
    at.data.foreach_get("value", a)
    return a


STRAPS = (41, 42, 36, 38)          # the reins (parts.csv role `strap`)
THIN_M = 0.035


def thin_mask(o):
    """Each vertex whose surface has another surface within THIN_M straight behind it."""
    from mathutils.bvhtree import BVHTree
    bm = bmesh.new(); bm.from_mesh(o.data)
    tree = BVHTree.FromBMesh(bm)
    bm.free()
    out = np.zeros(len(o.data.vertices), bool)
    for v in o.data.vertices:
        n = v.normal
        hit = tree.ray_cast(v.co - n * 0.002, -n, THIN_M)
        out[v.index] = hit[0] is not None
    return out


def straps(seed_r=0.03):
    """Phase 1d step 5: a strap is thinner than the alignment error, so nearest-part gave
    most of it to the neck. Seed from the strap parts' points and their X-mirror, then flood
    over connected THIN vertices; they become label 1000 + the seeding strap part."""
    o = mesh()
    lab = read_int(o, "part")
    rt = roles()
    # never flood into the rider or what he carries: the sword's blade is as thin as a rein and
    # touches the fist the right rein runs into (it bent like a rein in GARRISON)
    thin = thin_mask(o) & np.array([n >= 1000 or rt[int(n)]["role"] not in ("rider", "rprop") for n in lab])
    V = co(o)
    seeds = {}
    kd = kdtree.KDTree(len(V))
    for i, p in enumerate(V):
        kd.insert(p, i)
    kd.balance()
    for n in STRAPS:
        P = co(bpy.data.objects["tripo_part_%d" % n])
        for p in np.vstack([P, P * np.array([-1, 1, 1])]):
            for (_, i, d) in kd.find_range(p, seed_r):
                if thin[i]:
                    seeds.setdefault(i, n)
    nb = neighbours(o.data)
    strap = {}
    stack = list(seeds.items())
    while stack:
        i, n = stack.pop()
        if i in strap:
            continue
        strap[i] = n
        for j in nb[i]:
            if thin[j] and j not in strap:
                stack.append((j, n))
    for i, n in strap.items():
        lab[i] = 1000 + n
    write_int(o, "part", lab)
    return {"thin": int(thin.sum()), "seeds": len(seeds), "strap_verts": len(strap)}


ROLE_COL = {"mount": (0.6, 0.6, 0.6), "rider": (0.15, 0.35, 0.95), "prop": (0.95, 0.8, 0.1),
            "rprop": (0.2, 0.85, 0.3), "mixed": (1.0, 0.45, 0.0), "strap": (0.9, 0.1, 0.1)}


def paint(colours, name="debug_col"):
    """A per-vertex colour (N x 3) as a byte colour attribute, shown with the Workbench."""
    o = mesh()
    at = o.data.color_attributes.get(name) or o.data.color_attributes.new(name, "BYTE_COLOR", "POINT")
    rgba = np.ones((len(colours), 4))
    rgba[:, :3] = colours
    at.data.foreach_set("color", rgba.ravel())
    o.data.color_attributes.active_color = at
    sc = bpy.context.scene
    sc.display.shading.color_type = "VERTEX"
    return name


def role_map():
    o = mesh()
    rt = roles()
    lab = read_int(o, "part")
    cols = np.array([ROLE_COL["strap"] if n >= 1000 else ROLE_COL[rt[int(n)]["role"]] for n in lab])
    return paint(cols)
