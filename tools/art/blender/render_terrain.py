"""Seamless terrain textures rendered from small 3D scenes.

Each texture is a TILE_M x TILE_M metre patch of ground (512 px at game scale)
seen straight down. Everything in the patch is placed toroidally (objects near
an edge are duplicated on the opposite side) and the soil images are periodic,
so the rendered tile repeats without seams. The render covers a little more
than one tile and is cropped back, which keeps the denoiser honest at the edges.
"""
import math

import bpy
import numpy as np
from mathutils import Vector

import lib

TEX_PX = 512
TILE_M = TEX_PX / lib.PX_PER_M
OVERSCAN = 0.08
SAMPLES = 48


# --------------------------------------------------------------------------
# Building blocks
# --------------------------------------------------------------------------

def setup():
    lib.reset_scene(samples=SAMPLES, transparent=False, sky=(0.62, 0.70, 0.82), sky_strength=1.0)
    lib.add_sun(strength=4.0, angle_deg=3.0, direction=lib.SUN_DIR_TERRAIN)
    return lib.frame_top_down(TILE_M, OVERSCAN)


def wrapped_positions(n, seed, margin=0.6):
    """n random points in the tile plus their wrap-around copies near edges."""
    r = np.random.default_rng(seed)
    pts = r.uniform(0, TILE_M, (n, 2))
    lo, hi = -TILE_M * OVERSCAN - margin, TILE_M * (1 + OVERSCAN) + margin
    out, idx = [], []
    for dx in (-TILE_M, 0.0, TILE_M):
        for dy in (-TILE_M, 0.0, TILE_M):
            q = pts + (dx, dy)
            keep = (q[:, 0] > lo) & (q[:, 0] < hi) & (q[:, 1] > lo) & (q[:, 1] < hi)
            out.append(q[keep])
            idx.append(np.nonzero(keep)[0])
    return np.concatenate(out), np.concatenate(idx)


def patch_value(pos, seed, beta=3.0, n=128):
    """Smooth periodic noise (0-1) sampled at tile positions; wrapped copies agree."""
    field = np.clip(0.5 + lib.tile_noise(n, seed, beta) * 0.35, 0, 1)
    u = ((pos[:, 0] / TILE_M) % 1.0 * n).astype(int) % n
    v = ((1.0 - (pos[:, 1] / TILE_M) % 1.0) * n).astype(int) % n
    return field[v, u]


def ground(color_arr, bump_arr=None, bump=0.25, rough=0.9, name="Ground"):
    """Flat ground plane with periodic colour/bump images."""
    color_img = lib.image_from_array(name + "_col", color_arr)
    bump_img = lib.image_from_array(name + "_bump", np.repeat(bump_arr[..., None], 3, 2)) if bump_arr is not None else None
    mat = lib.image_material(name + "_mat", color_img, bump_img, bump=bump, rough=rough, tile_m=TILE_M,
                             normal_strength=0.05)
    size = TILE_M * (1 + 2 * OVERSCAN) + 2
    bpy.ops.mesh.primitive_plane_add(size=size, location=(TILE_M / 2, TILE_M / 2, 0))
    plane = bpy.context.object
    plane.name = name
    # Object coordinates must equal world XY for the periodic mapping.
    plane.location = (0, 0, 0)
    me = plane.data
    for v in me.vertices:
        v.co.x += TILE_M / 2
        v.co.y += TILE_M / 2
    plane.data.materials.append(mat)
    return plane


def heightfield(height, color_arr, amp, rough=0.85, res=360, name="Heightfield", spec=0.3):
    """Displaced grid whose heights come from a periodic height image."""
    n = height.shape[0]
    lo, hi = -TILE_M * OVERSCAN - 0.5, TILE_M * (1 + OVERSCAN) + 0.5
    xs = np.linspace(lo, hi, res)
    gx, gy = np.meshgrid(xs, xs)
    u = (gx / TILE_M) % 1.0 * n
    v = (1.0 - (gy / TILE_M) % 1.0) * n  # image row 0 = top = high y
    i0 = np.floor(u).astype(int) % n
    j0 = np.floor(v).astype(int) % n
    fu, fv = u - np.floor(u), v - np.floor(v)
    i1, j1 = (i0 + 1) % n, (j0 + 1) % n
    h = (height[j0, i0] * (1 - fu) * (1 - fv) + height[j0, i1] * fu * (1 - fv)
         + height[j1, i0] * (1 - fu) * fv + height[j1, i1] * fu * fv)
    verts = np.stack([gx.ravel(), gy.ravel(), (h * amp).ravel()], axis=1)
    faces = []
    for r in range(res - 1):
        base = r * res
        for c in range(res - 1):
            a = base + c
            faces.append((a, a + 1, a + 1 + res, a + res))
    color_img = lib.image_from_array(name + "_col", color_arr)
    mat = lib.image_material(name + "_mat", color_img, rough=rough, tile_m=TILE_M, spec=spec)
    return lib.mesh_object(name, verts, faces, mat=mat, smooth=True)


def unit_icosphere(subdiv=1):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdiv, radius=1.0)
    obj = bpy.context.object
    verts = np.array([v.co[:] for v in obj.data.vertices])
    faces = [tuple(p.vertices) for p in obj.data.polygons]
    bpy.data.objects.remove(obj)
    return verts, faces


def scatter_pebbles(count, seed, size=(0.03, 0.09), colors=("#8b8478", "#9e968a", "#6f685e", "#a39a88"),
                    flat=0.55, name="Pebbles", rough=0.7):
    base_v, base_f = unit_icosphere(1)
    pos, idx = wrapped_positions(count, seed)
    r = np.random.default_rng(seed + 1)
    per = len(idx)
    scales = r.uniform(size[0], size[1], count)
    squash = r.uniform(0.6, 1.0, (count, 2))
    rot = r.uniform(0, 2 * np.pi, count)
    jitter = r.normal(0, 0.18, (count, len(base_v), 3))
    cols = [lib.lin(c) for c in colors]
    tone = r.uniform(0.8, 1.15, count)
    cidx = r.integers(len(cols), size=count)
    verts, faces, vcols = [], [], []
    for k in range(per):
        i = idx[k]
        s = scales[i]
        local = base_v * (1 + jitter[i]) * np.array([s * squash[i, 0], s * squash[i, 1], s * flat])
        c, sn = math.cos(rot[i]), math.sin(rot[i])
        rx = local[:, 0] * c - local[:, 1] * sn
        ry = local[:, 0] * sn + local[:, 1] * c
        off = len(verts) * 0 + k * len(base_v)
        verts.append(np.stack([rx + pos[k, 0], ry + pos[k, 1], local[:, 2] + s * flat * 0.35], axis=1))
        faces.extend(tuple(off + a for a in f) for f in base_f)
        vcols.append(np.tile(np.array(cols[cidx[i]]) * tone[i], (len(base_v), 1)))
    mat = lib.material(name + "_mat", (1, 1, 1), rough=rough, vcol=True, bump=0.3, bump_scale=60)
    return lib.mesh_object(name, np.concatenate(verts), faces, colors=np.concatenate(vcols), mat=mat, smooth=True)


def scatter_blades(count, seed, length=(0.12, 0.3), width=(0.012, 0.022), lean=(0.2, 1.1),
                   base_col="#3f5a22", tip_cols=("#7da246", "#6a9a3a", "#93ad52", "#5e8a32"), clump=0.0,
                   name="Grass", dry_col=None, patch_seed=None, sparse=0.0):
    """Grass blades: each a bent strip (base quad + tip triangle)."""
    r = np.random.default_rng(seed)
    if clump > 0:
        n_clumps = max(1, int(count / 40))
        centers, cidx = wrapped_positions(n_clumps, seed + 7)
        pts_list, idx_list = [], []
        for k in range(len(centers)):
            # Per-cluster RNG so wrapped copies of a clump are identical.
            cr = np.random.default_rng(seed * 7919 + int(cidx[k]))
            m = cr.poisson(40)
            d = cr.normal(0, clump, (m, 2))
            pts_list.append(centers[k] + d)
            idx_list.append(np.full(m, cidx[k] * 100000) + np.arange(m))
        pos = np.concatenate(pts_list)
        ids = np.concatenate(idx_list)
        _, ids = np.unique(ids, return_inverse=True)
        n = ids.max() + 1
    else:
        pos, ids = wrapped_positions(count, seed)
        n = count
    if patch_seed is not None and sparse > 0:
        # Thin out blades where the patch field is low (bare, trodden spots).
        keep_p = np.clip(patch_value(pos, patch_seed + 1) * (1 + sparse) - sparse * 0.35, 0, 1)
        keep = np.random.default_rng(seed + 99).random(n)[ids] < keep_p
        pos, ids = pos[keep], ids[keep]
    L = r.uniform(*length, n)
    W = r.uniform(*width, n)
    yaw = r.uniform(0, 2 * np.pi, n)
    tilt = r.uniform(*lean, n)
    tips = [lib.lin(c) for c in tip_cols]
    tip_c = np.array(tips)[r.integers(len(tips), size=n)] * r.uniform(0.75, 1.15, (n, 1))
    base_c = np.array(lib.lin(base_col))
    m = len(ids)
    i = ids
    tip_i = tip_c[i]
    if dry_col is not None and patch_seed is not None:
        dry = patch_value(pos, patch_seed)[:, None]
        dry = np.clip((dry - 0.58) * 2.4, 0, 1) * 0.8
        tip_i = tip_i * (1 - dry) + np.array(lib.lin(dry_col)) * dry
    d = np.stack([np.cos(yaw[i]), np.sin(yaw[i])], axis=1)
    pv = np.stack([-d[:, 1], d[:, 0]], axis=1)
    ts = np.array([0.0, 0.0, 0.55, 0.55, 1.0])
    side = np.array([-1, 1, -1, 1, 0])
    wid = np.array([1.0, 1.0, 0.6, 0.6, 0.0])
    verts = np.zeros((m, 5, 3))
    cols = np.zeros((m, 5, 3))
    for k in range(5):
        t = ts[k]
        reach = L[i] * np.sin(tilt[i]) * t ** 1.6
        hgt = L[i] * np.cos(tilt[i] * t) * t
        verts[:, k, 0] = pos[:, 0] + d[:, 0] * reach + pv[:, 0] * W[i] * wid[k] * side[k] * 0.5
        verts[:, k, 1] = pos[:, 1] + d[:, 1] * reach + pv[:, 1] * W[i] * wid[k] * side[k] * 0.5
        verts[:, k, 2] = hgt
        cols[:, k] = base_c * (1 - t) + tip_i * t
    base = (np.arange(m) * 5)[:, None]
    quads = np.concatenate([base + [0, 1, 3, 2]])
    tris = base + [2, 3, 4]
    faces = [tuple(q) for q in quads] + [tuple(t) for t in tris]
    mat = lib.material(name + "_mat", (1, 1, 1), rough=0.6, vcol=True, spec=0.25, subsurface=0.0)
    obj = lib.mesh_object(name, verts.reshape(-1, 3), faces, colors=cols.reshape(-1, 3), mat=mat)
    return obj


def scatter_flowers(count, seed, cols=("#f2efe2", "#f0d24a", "#c9a0d8"), name="Flowers"):
    """Tiny flower heads: small coloured discs a few centimetres above ground."""
    r = np.random.default_rng(seed)
    pos, ids = wrapped_positions(count, seed)
    palette = np.array([lib.lin(c) for c in cols])
    col = palette[r.integers(len(palette), size=count)]
    size = r.uniform(0.018, 0.03, count)
    verts, faces, vcols = [], [], []
    for k, i in enumerate(ids):
        base = len(verts) * 0 + k * 6
        for a in range(6):
            ang = a * math.pi / 3
            verts.append((pos[k, 0] + math.cos(ang) * size[i], pos[k, 1] + math.sin(ang) * size[i], 0.2))
            vcols.append(col[i])
        faces.append(tuple(range(base, base + 6)))
    mat = lib.material(name + "_mat", (1, 1, 1), rough=0.6, vcol=True)
    return lib.mesh_object(name, verts, faces, colors=vcols, mat=mat)


def scatter_leaves(count, seed, cols=("#7a4a1e", "#9a6a2a", "#5e3a1a", "#a8842e", "#6b5a24"), size=(0.05, 0.11),
                   name="Leaves"):
    r = np.random.default_rng(seed)
    pos, ids = wrapped_positions(count, seed)
    n = count
    s = r.uniform(*size, n)
    rot = r.uniform(0, 2 * np.pi, n)
    curl = r.uniform(0.0, 0.4, n)
    palette = np.array([lib.lin(c) for c in cols])
    col = palette[r.integers(len(palette), size=n)] * r.uniform(0.7, 1.1, (n, 1))
    shape = np.array([[-1.0, 0.0], [0.0, -0.45], [1.0, 0.0], [0.0, 0.45]])
    verts, faces, vcols = [], [], []
    for k, i in enumerate(ids):
        c, sn = math.cos(rot[i]), math.sin(rot[i])
        pts = shape * s[i]
        x = pts[:, 0] * c - pts[:, 1] * sn + pos[k, 0]
        y = pts[:, 0] * sn + pts[:, 1] * c + pos[k, 1]
        z = 0.006 + np.array([curl[i], 0, curl[i], 0]) * s[i] * 0.5 + k * 1e-6
        verts.append(np.stack([x, y, z], axis=1))
        faces.append(tuple(range(4 * k, 4 * k + 4)))
        vcols.append(np.tile(col[i], (4, 1)))
    mat = lib.material(name + "_mat", (1, 1, 1), rough=0.75, vcol=True)
    return lib.mesh_object(name, np.concatenate(verts), faces, colors=np.concatenate(vcols), mat=mat)


def scatter_twigs(count, seed, name="Twigs"):
    r = np.random.default_rng(seed)
    pos, ids = wrapped_positions(count, seed)
    mat = lib.material(name + "_mat", lib.lin("#4a3622"), rough=0.85, bump=0.4, bump_scale=80)
    objs = []
    for k, i in enumerate(ids):
        a = r.uniform(0, 2 * np.pi)
        ln = r.uniform(0.15, 0.45)
        p0 = Vector((pos[k, 0], pos[k, 1], 0.012))
        p1 = p0 + Vector((math.cos(a) * ln, math.sin(a) * ln, 0.0))
        objs.append(lib.cylinder_between(f"{name}{k}", p0, p1, 0.01, 0.006, mat=mat, sides=6))
    return objs


def soil(seed, stops, spread=0.22, fine=0.25, n=512):
    v = (0.6 * np.clip(0.5 + lib.tile_noise(n, seed, 2.6) * spread, 0, 1)
         + 0.4 * np.clip(0.5 + lib.tile_noise(n, seed + 1, 1.2) * fine, 0, 1))
    return lib.colorize(v, [(p, lib.srgb_to_linear(lib.hexcol(c))) for p, c in stops])


def bump_noise(seed, n=512, beta=1.6):
    return np.clip(0.5 + lib.tile_noise(n, seed, beta) * 0.25, 0, 1)


def voronoi(n, count, seed):
    r = np.random.default_rng(seed)
    pts = r.uniform(0, n, (count, 2))
    yy, xx = np.mgrid[0:n, 0:n].astype(float)
    f1 = np.full((n, n), 1e9)
    f2 = np.full((n, n), 1e9)
    idx = np.zeros((n, n), dtype=int)
    for i, (px, py) in enumerate(pts):
        dx = np.abs(xx - px)
        dx = np.minimum(dx, n - dx)
        dy = np.abs(yy - py)
        dy = np.minimum(dy, n - dy)
        d = np.sqrt(dx * dx + dy * dy)
        closer = d < f1
        f2 = np.where(closer, f1, np.minimum(f2, d))
        idx = np.where(closer, i, idx)
        f1 = np.where(closer, d, f1)
    return f1, f2, idx


def finish(name):
    crop = (OVERSCAN / (1 + 2 * OVERSCAN), OVERSCAN / (1 + 2 * OVERSCAN),
            (1 + OVERSCAN) / (1 + 2 * OVERSCAN), (1 + OVERSCAN) / (1 + 2 * OVERSCAN))
    size = round(TEX_PX * (1 + 2 * OVERSCAN)) * lib.SUPERSAMPLE
    bpy.context.scene.render.resolution_x = size
    bpy.context.scene.render.resolution_y = size
    path = lib.ASSETS / "terrain" / f"{name}.png"
    img = lib.render(path, res=(TEX_PX, TEX_PX), crop=crop)
    img.convert("RGB").save(path)
    print("wrote", path)


# --------------------------------------------------------------------------
# Terrains
# --------------------------------------------------------------------------

def grass():
    setup()
    ground(soil(101, [(0, "#30361a"), (0.5, "#404622"), (1, "#56582e")]), bump_noise(102), bump=0.3)
    scatter_blades(56000, 103, tip_cols=("#6f9a3a", "#82aa44", "#5e8a36", "#90b04e", "#9cb456"),
                   base_col="#2f4e1a", dry_col="#a8a85a", patch_seed=110, sparse=0.25)
    scatter_blades(9000, 104, length=(0.08, 0.16), lean=(0.6, 1.3),
                   tip_cols=("#98ac54", "#acb262", "#84a046"), base_col="#3f5622", name="Short",
                   dry_col="#bfae68", patch_seed=110)
    scatter_flowers(140, 106)
    scatter_pebbles(60, 105, size=(0.02, 0.05))
    finish("grass")


def forest_floor():
    setup()
    moss = np.clip((lib.tile_noise(512, 207, 2.4) - 0.3) * 1.2, 0, 1)[..., None]
    base = soil(201, [(0, "#1e1a10"), (0.5, "#2c2616"), (0.8, "#3a3220"), (1, "#40381f")])
    base = base * (1 - 0.45 * moss) + np.array(lib.lin("#283e1a")) * 0.45 * moss
    ground(base, bump_noise(202), bump=0.45)
    scatter_leaves(1500, 203, cols=("#6b4a24", "#7a5a2c", "#4f3a1e", "#8a6a34", "#5a4a24"), size=(0.07, 0.13))
    scatter_twigs(90, 204)
    scatter_blades(14000, 205, length=(0.12, 0.3), clump=0.14, tip_cols=("#4f6a2a", "#3d5a22", "#5a7030"),
                   base_col="#1f2a12")
    scatter_pebbles(60, 206, size=(0.04, 0.1), colors=("#5e5a50", "#6b665a", "#4f4b42"))
    finish("grass_dark")


def dirt_road():
    setup()
    n = 512
    h = (0.55 * np.clip(0.5 + lib.tile_noise(n, 301, 2.6) * 0.3, 0, 1)
         + 0.45 * np.clip(0.5 + lib.tile_noise(n, 305, 0.9) * 0.3, 0, 1))
    col = soil(302, [(0, "#3f3021"), (0.45, "#5e4a32"), (0.8, "#7a6343"), (1, "#8f7a56")], spread=0.3, fine=0.35)
    heightfield(h, col, amp=0.12, rough=0.95, res=380, name="Dirt")
    scatter_pebbles(900, 303, size=(0.03, 0.09), colors=("#7d776c", "#958c7c", "#605a50", "#a89f8c", "#6e5e48"))
    scatter_blades(2500, 304, length=(0.06, 0.18), clump=0.08, tip_cols=("#6d8238", "#86904a"), base_col="#3e4420",
                   patch_seed=306, sparse=0.6)
    finish("dirt_road")


def sand():
    setup()
    n = 512
    yy, xx = np.mgrid[0:n, 0:n] / n
    warp = lib.tile_noise(n, 401, 3.0)
    ripples = 0.5 + 0.5 * np.sin(2 * np.pi * (18 * xx + 7 * yy) + 2.2 * warp)
    ripples = ripples ** 1.5
    grain = np.clip(0.5 + lib.tile_noise(n, 402, 0.6) * 0.3, 0, 1)
    h = 0.55 * ripples + 0.25 * grain + 0.2 * np.clip(0.5 + lib.tile_noise(n, 405, 2.6) * 0.3, 0, 1)
    # Damp river sand: muted grey-brown rather than beach yellow.
    col = soil(403, [(0, "#6f6250"), (0.5, "#877a62"), (1, "#a09276")], fine=0.4)
    col *= (0.88 + 0.2 * ripples)[..., None]
    heightfield(h, col, amp=0.09, rough=0.95, res=420, name="Sand")
    scatter_pebbles(220, 404, size=(0.015, 0.045), colors=("#8a8070", "#a49a86", "#d8d0c0", "#6e665a"))
    finish("sand")


def relaxed_voronoi(n, count, seed, iters=3):
    """Voronoi with Lloyd relaxation: evenly sized cells, no slivers."""
    r = np.random.default_rng(seed)
    pts = r.uniform(0, n, (count, 2))
    small = 128
    sc = n / small
    yy, xx = np.mgrid[0:small, 0:small].astype(float) * sc
    for _ in range(iters):
        best = np.full(xx.shape, 1e9)
        owner = np.zeros(xx.shape, dtype=int)
        for i, (px, py) in enumerate(pts):
            dx = np.abs(xx - px)
            dx = np.minimum(dx, n - dx)
            dy = np.abs(yy - py)
            dy = np.minimum(dy, n - dy)
            d = dx * dx + dy * dy
            closer = d < best
            best = np.where(closer, d, best)
            owner = np.where(closer, i, owner)
        for i in range(count):
            m = owner == i
            if not m.any():
                continue
            # circular mean so cells straddling the wrap behave
            ax = np.angle(np.exp(1j * xx[m] / n * 2 * np.pi).mean()) / (2 * np.pi) * n % n
            ay = np.angle(np.exp(1j * yy[m] / n * 2 * np.pi).mean()) / (2 * np.pi) * n % n
            pts[i] = (ax, ay)
    yy, xx = np.mgrid[0:n, 0:n].astype(float)
    f1 = np.full((n, n), 1e9)
    f2 = np.full((n, n), 1e9)
    idx = np.zeros((n, n), dtype=int)
    for i, (px, py) in enumerate(pts):
        dx = np.abs(xx - px)
        dx = np.minimum(dx, n - dx)
        dy = np.abs(yy - py)
        dy = np.minimum(dy, n - dy)
        d = np.sqrt(dx * dx + dy * dy)
        closer = d < f1
        f2 = np.where(closer, f1, np.minimum(f2, d))
        idx = np.where(closer, i, idx)
        f1 = np.where(closer, d, f1)
    return f1, f2, idx


def cobblestone():
    setup()
    n = 512
    f1, f2, idx = relaxed_voronoi(n, 520, 501)
    edge = f2 - f1
    dome = np.clip(edge / 7.0, 0, 1) ** 0.6
    h = dome + 0.1 * np.clip(0.5 + lib.tile_noise(n, 502, 1.2) * 0.3, 0, 1)
    r = np.random.default_rng(503)
    tones = r.uniform(0.75, 1.15, idx.max() + 1)
    hues = r.integers(0, 4, idx.max() + 1)
    palette = np.array([lib.srgb_to_linear(lib.hexcol(c)) for c in ("#76706a", "#6a6258", "#827a6e", "#5e5a54")])
    col = palette[hues[idx]] * tones[idx][..., None]
    grime = np.clip(0.5 + lib.tile_noise(n, 504, 1.8) * 0.3, 0, 1)[..., None]
    col *= 0.75 + 0.35 * grime
    mortar = (edge < 2.2)[..., None]
    col = np.where(mortar, np.array(lib.srgb_to_linear(lib.hexcol("#2f2a22"))), col)
    heightfield(h, col, amp=0.07, rough=0.8, res=440, name="Cobble")
    scatter_blades(1200, 505, length=(0.04, 0.1), clump=0.05, tip_cols=("#5f7a34", "#6e8840"), base_col="#2c3a18",
                   patch_seed=506, sparse=0.8)
    finish("cobblestone")


def rock():
    setup()
    n = 512
    f1, f2, idx = voronoi(n, 40, 601)
    base = np.clip(0.5 + lib.tile_noise(n, 602, 2.2) * 0.3, 0, 1)
    detail = np.clip(0.5 + lib.tile_noise(n, 603, 1.0) * 0.3, 0, 1)
    crack = np.clip((f2 - f1) / 6.0, 0, 1)
    h = 0.6 * base + 0.25 * detail + 0.35 * crack
    r = np.random.default_rng(604)
    tones = r.uniform(0.85, 1.15, idx.max() + 1)
    col = lib.colorize(0.4 * base + 0.6 * detail, [(0, lib.srgb_to_linear(lib.hexcol("#4f4c48"))),
                                                   (0.5, lib.srgb_to_linear(lib.hexcol("#6f6b64"))),
                                                   (1, lib.srgb_to_linear(lib.hexcol("#8e8a82")))])
    col *= tones[idx][..., None]
    lichen = np.clip((lib.tile_noise(n, 605, 2.0) - 0.8) * 2.0, 0, 1)[..., None]
    col = col * (1 - 0.6 * lichen) + np.array(lib.srgb_to_linear(lib.hexcol("#7a8a4a"))) * 0.6 * lichen
    col *= (0.55 + 0.45 * crack)[..., None]
    heightfield(h, col, amp=0.45, rough=0.9, res=420, name="Rock")
    finish("rock")


def water_material(name, deep, shallow, transparent=False):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    out = nt.nodes["Material Output"]
    n = 512
    yy, xx = np.mgrid[0:n, 0:n] / n
    waves = (np.sin(2 * np.pi * (5 * xx + 11 * yy) + 2.0 * lib.tile_noise(n, 701, 3.0))
             + 0.7 * np.sin(2 * np.pi * (-9 * xx + 8 * yy) + 1.5 * lib.tile_noise(n, 702, 3.0))
             + 0.6 * lib.tile_noise(n, 703, 1.4))
    h = np.clip(0.5 + waves * 0.15, 0, 1)
    crest = np.clip((waves - 1.2) * 0.8, 0, 1)
    himg = lib.image_from_array(name + "_h", np.repeat(h[..., None], 3, 2))
    himg.colorspace_settings.name = 'Non-Color'
    depth = np.clip(0.5 + lib.tile_noise(n, 704, 2.6) * 0.3, 0, 1)
    col = lib.colorize(depth, [(0, deep), (1, shallow)])
    col = col * (1 - 0.35 * crest[..., None]) + np.array(lib.srgb_to_linear(lib.hexcol("#9fc4cf"))) * 0.35 * crest[..., None]
    cimg = lib.image_from_array(name + "_c", col)
    coord = nt.nodes.new("ShaderNodeTexCoord")
    mapping = nt.nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (1 / TILE_M, 1 / TILE_M, 1)
    nt.links.new(coord.outputs["Object"], mapping.inputs["Vector"])
    ht = nt.nodes.new("ShaderNodeTexImage")
    ht.image = himg
    ht.interpolation = 'Cubic'
    ct = nt.nodes.new("ShaderNodeTexImage")
    ct.image = cimg
    for t in (ht, ct):
        nt.links.new(mapping.outputs["Vector"], t.inputs["Vector"])
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 1.0
    bump.inputs["Distance"].default_value = 0.35
    nt.links.new(ht.outputs["Color"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    nt.links.new(ct.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.06
    bsdf.inputs["Specular IOR Level"].default_value = 0.8
    if transparent:
        bsdf.inputs["Alpha"].default_value = 0.42
        # Let sunlight through to the riverbed (no caustics in Cycles' path tracer).
        lp = nt.nodes.new("ShaderNodeLightPath")
        tr = nt.nodes.new("ShaderNodeBsdfTransparent")
        tr.inputs["Color"].default_value = (0.85, 0.95, 0.95, 1)
        mix = nt.nodes.new("ShaderNodeMixShader")
        nt.links.new(lp.outputs["Is Shadow Ray"], mix.inputs["Fac"])
        nt.links.new(bsdf.outputs["BSDF"], mix.inputs[1])
        nt.links.new(tr.outputs["BSDF"], mix.inputs[2])
        nt.links.new(mix.outputs["Shader"], out.inputs["Surface"])
    return mat


def water_plane(mat, z):
    size = TILE_M * (1 + 2 * OVERSCAN) + 2
    verts = [(-1 - TILE_M * OVERSCAN, -1 - TILE_M * OVERSCAN, z), (size - 1 - TILE_M * OVERSCAN, -1 - TILE_M * OVERSCAN, z),
             (size - 1 - TILE_M * OVERSCAN, size - 1 - TILE_M * OVERSCAN, z), (-1 - TILE_M * OVERSCAN, size - 1 - TILE_M * OVERSCAN, z)]
    return lib.mesh_object("Water", verts, [(0, 1, 2, 3)], mat=mat)


def gradient_sky():
    """Sky that is brighter towards the horizon, so ripples reflect variation."""
    world = bpy.context.scene.world
    nt = world.node_tree
    bg = nt.nodes["Background"]
    coord = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(coord.outputs["Generated"], sep.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.0
    ramp.color_ramp.elements[0].color = (0.95, 0.95, 0.92, 1)
    ramp.color_ramp.elements[1].position = 0.6
    ramp.color_ramp.elements[1].color = (0.3, 0.42, 0.62, 1)
    nt.links.new(sep.outputs["Z"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bg.inputs["Color"])


def water():
    setup()
    gradient_sky()
    deep = lib.srgb_to_linear(lib.hexcol("#14303f"))
    shallow = lib.srgb_to_linear(lib.hexcol("#24525e"))
    water_plane(water_material("Water", deep, shallow), 0.0)
    finish("water")


def shallows():
    setup()
    gradient_sky()
    h = bump_noise(801, beta=2.2)
    col = soil(802, [(0, "#7a6e50"), (0.5, "#978a64"), (1, "#b2a27a")], fine=0.35)
    heightfield(h, col, amp=0.08, rough=0.9, res=300, name="Bed")
    scatter_pebbles(500, 803, size=(0.03, 0.09), colors=("#6f6a5c", "#857e6c", "#5a5548", "#9a9282"))
    tint_a = lib.srgb_to_linear(lib.hexcol("#3f7f86"))
    tint_b = lib.srgb_to_linear(lib.hexcol("#5f9a98"))
    water_plane(water_material("Shallow", tint_a, tint_b, transparent=True), 0.12)
    finish("shallows")


ALL = {
    "grass": grass,
    "grass_dark": forest_floor,
    "dirt_road": dirt_road,
    "sand": sand,
    "cobblestone": cobblestone,
    "rock": rock,
    "water": water,
    "shallows": shallows,
}


def run(names=None):
    for name in names or ALL:
        ALL[name]()
