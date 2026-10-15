#!/usr/bin/env python3
"""Generates data/maps/millbrook_outskirts.json (the sample map).

The map file is ordinary data and can be edited by hand; this script is how
the sample was laid out (river, roads, village, scatter) and is kept so the
layout can be re-tuned and regenerated. Usage:

    python3 tools/maps/generate_millbrook.py
"""
import json, math, random, sys
from pathlib import Path
import numpy as np

W, H = 84, 56
rng = random.Random(7)
ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[2]

def o2a(c, r): return (c - (r - (r & 1)) // 2, r)
def a2o(q, r): return (q + (r - (r & 1)) // 2, r)
DIRS = [(1,0),(1,-1),(0,-1),(-1,0),(-1,1),(0,1)]
def nbrs(c, r):
    q, rr = o2a(c, r)
    return [a2o(q+dq, rr+dr) for dq, dr in DIRS]
def inb(c, r): return 0 <= c < W and 0 <= r < H
def xcol(c, r):  # visual column position (odd rows shifted)
    return c + 0.5 * (r & 1)

T = [['.' for _ in range(W)] for _ in range(H)]
P = [[' ' for _ in range(W)] for _ in range(H)]
reserved = set()
road = set()

def vnoise(seed, scale):
    g = np.random.default_rng(seed).random((H//scale+3, W//scale+3))
    def f(c, r):
        x, y = c/scale, r/scale; x0, y0 = int(x), int(y); tx, ty = x-x0, y-y0
        tx, ty = tx*tx*(3-2*tx), ty*ty*(3-2*ty)
        a = g[y0, x0]*(1-tx) + g[y0, x0+1]*tx; b = g[y0+1, x0]*(1-tx) + g[y0+1, x0+1]*tx
        return a*(1-ty) + b*ty
    return f
n1 = vnoise(1, 6); n2 = vnoise(2, 3)

# river
def river_x(r): return 34 + 3.0*math.sin(r/7.0) - 0.12*r
for r in range(H):
    for c in range(W):
        d = abs(xcol(c, r) - river_x(r))
        if d <= 1.5: T[r][c] = '~'
        elif d <= 2.5 and n2(c, r) > 0.45: T[r][c] = ':'

# forest NW
for r in range(H):
    for c in range(W):
        d = math.hypot(c/30.0, r/22.0)
        if d + (n1(c, r)-0.5)*0.4 < 1.0 and T[r][c] == '.':
            T[r][c] = 'f'
# rocks SW
for r in range(H):
    for c in range(W):
        d = math.hypot(c/12.0, (H-1-r)/10.0)
        if d + (n2(c, r)-0.5)*0.5 < 1.0:
            T[r][c] = '^'

def paint_road(cells, sym=','):
    for (c, r) in cells:
        if inb(c, r) and T[r][c] in '.f:^':
            T[r][c] = sym
        road.add((c, r))

# main road west -> bridge -> square
ROAD_R = 30
west = []
for c in range(0, 58):
    rr = ROAD_R + (round(1.2*math.sin(c/8.0)) if c < 18 else 0)
    west += [(c, rr), (c, rr+1)]
for (c, r) in west:
    if T[r][c] not in '~:':
        paint_road([(c, r)])
    road.add((c, r))
# bridge over the river at rows 30-31
water_cols = [c for r in (ROAD_R, ROAD_R+1) for c in range(W) if T[r][c] == '~']
b0 = min(water_cols) - 2
BRIDGE = (b0, ROAD_R, 8, 2)
assert max(water_cols) <= b0 + 7, (water_cols, b0)
for r in (ROAD_R, ROAD_R+1):
    for c in range(b0, b0 + 8):
        T[r][c] = '=' if T[r][c] == '~' else ','

# square
SQ = (58, 23, 71, 36)
for r in range(SQ[1], SQ[3]+1):
    for c in range(SQ[0], SQ[2]+1):
        T[r][c] = '#'
# east road
paint_road([(c, r) for c in range(72, W) for r in (ROAD_R, ROAD_R+1)])

# ford + footpath
for r in (47, 48):
    for c in range(W):
        if T[r][c] == '~': T[r][c] = '-'
def line(a, b):
    (ac, ar), (bc, br) = a, b
    n = max(abs(bc-ac), abs(br-ar))
    return [(round(ac+(bc-ac)*i/n), round(ar+(br-ar)*i/n)) for i in range(n+1)]
wb = min(c for c in range(W) if T[47][c] == '-') - 1
eb = max(c for c in range(W) if T[47][c] == '-') + 1
fp = line((14, 32), (wb, 47)) + line((eb, 47), (52, 47)) + line((52, 47), (57, 37))
paint_road(fp + [(c+1, r) for (c, r) in fp])

# structures
props = []
def rect_cells(at, cols, rows): return [(at[0]+dc, at[1]+dr) for dr in range(rows) for dc in range(cols)]
def place(kind, cells, at, margin=1, allowed='.f#,:', **extra):
    for (c, r) in cells:
        assert inb(c, r), (kind, at, c, r)
        assert P[r][c] == ' ' and (c, r) not in reserved and T[r][c] in allowed, (kind, at, (c, r), T[r][c])
    for (c, r) in cells:
        P[r][c] = '@'; reserved.add((c, r))
    if margin:
        ring = set(cells)
        for _ in range(margin):
            ring |= {n for (c, r) in ring for n in nbrs(c, r)}
        reserved.update(ring)
    e = {"type": kind, "at": list(at)}; e.update(extra); props.append(e)

# Door position across the front, as a fraction of the width, per look
# (see COTTAGE_STYLES / inn in tools/art/blender/render_props.py).
DOOR_FRACTION = {("house_small", 0): 3.5 / 6, ("house_small", 1): 2.5 / 6, ("house_small", 2): 4.5 / 6,
                 ("house_large", 0): 4.5 / 9}

def building(kind, at, cols, rows, variant, name, building_id):
    """A house with an interior map (tools/maps/generate_interiors.py writes it)."""
    door_col = at[0] + int(DOOR_FRACTION[(kind, variant)] * cols)
    cells = rect_cells(at, cols, rows)
    place(kind, cells, at, margin=2, name=name, variant=variant, id=building_id,
          interior=f"res://data/maps/{building_id}.json", entry="door")
    # keep ground in front of the door clear and paved
    dr = at[1] + rows
    paint_road([(door_col, dr), (door_col + 1, dr), (door_col, dr + 1)])
    return (door_col, dr)

inn_door = building("house_large", (59, 15), 12, 8, 0, "The Lantern & Thistle", "millbrook_inn")
a_door = building("house_small", (47, 21), 8, 6, 0, "Miller's Cottage", "millbrook_miller")
b_door = building("house_small", (75, 20), 8, 6, 2, "Reeve's House", "millbrook_reeve")
c_door = building("house_small", (46, 40), 8, 6, 1, "Herbalist's Cottage", "millbrook_herbalist")
d_door = building("house_small", (66, 40), 8, 6, 1, "Smithy", "millbrook_smithy")
# paths from doors to the square
paint_road(line(a_door, (58, 28)) + line((a_door[0], a_door[1]+1), (58, 29)))
paint_road(line(b_door, (71, 27)) + line((b_door[0], b_door[1]+1), (71, 28)))
paint_road(line((c_door[0], c_door[1]+1), (56, 47)))
paint_road(line(d_door, (75, 46)) + line((75, 46), (75, 37)) + line((76, 46), (76, 37)) + line((75, 37), (71, 36)))
place("bridge_wood", rect_cells((b0, ROAD_R), 8, 2), (b0, ROAD_R), margin=0, allowed="=,:.")
place("well", [(64, 30)], (64, 30))
place("sign", [(4, 27)], (4, 27), title="Weathered Signpost",
      text="WEST ROAD\n\nMillbrook lies east, across the Brightwater.\nTravellers welcome. Mind the wolves after dark.")
place("sign", [(b0 - 3, 28)], (b0 - 3, 28), title="Bridge Notice",
      text="BRIGHTWATER BRIDGE\n\nBy order of the reeve: no toll this season.\nThe southern ford is shallow but slow going.")
place("sign", [(60, 34)], (60, 34), title="Village Notice Board",
      text="MILLBROOK\n\nThe Lantern & Thistle serves supper at dusk.\nBrother Odran asks that the old temple road be cleared.")

# --- set dressing around the village (explicit, so doors and paths stay clear)
def dress(kind, cell, **extra):
    """Places a one-hex prop at `cell`, nudged to the nearest free non-road hex."""
    def ok(c, r):
        return inb(c, r) and P[r][c] == ' ' and T[r][c] in '.f#:' and (c, r) not in road
    candidates = [cell] + nbrs(*cell) + [n2 for n in nbrs(*cell) for n2 in nbrs(*n)]
    for (c, r) in candidates:
        if ok(c, r):
            P[r][c] = '@'
            e = {"type": kind, "at": [c, r]}; e.update(extra); props.append(e)
            return
    raise AssertionError((kind, cell))

for kind, cell in (("crates", (57, 21)), ("hay", (56, 19)), ("barrels", (46, 26)), ("hay", (45, 24)),
                   ("crates", (74, 25)), ("barrels", (83, 23)), ("hay", (45, 44)), ("barrels", (54, 45)),
                   ("crates", (65, 45)), ("barrels", (74, 43))):
    dress(kind, cell)
for cell in ((58, 23), (71, 23), (58, 36), (71, 36), (33, 29)):
    dress("lamp_post", cell)
# A crate of apples by the market that can be opened (a container outdoors).
dress("crates", (70, 29), interaction="container", id="apple_crate", name="Crate of Apples",
      items=[{"item": "apple", "qty": 8}])
for at, variant in (((66, 25), 0), ((67, 33), 1)):
    cells = rect_cells(at, 3, 2)
    for (c, r) in cells:
        assert P[r][c] == ' ' and T[r][c] == '#', ("market_stall", at, (c, r))
        P[r][c] = '@'
    props.append({"type": "market_stall", "at": list(at), "variant": variant})
for (c, r) in rect_cells((72, 21), 2, 1):
    assert P[r][c] == ' ', ("cart", (c, r))
    P[r][c] = '@'
props.append({"type": "cart", "at": [72, 21]})

spawn = (4, 30)
for cell in road: reserved.add(cell)
for r in range(H):
    for c in range(W):
        if T[r][c] in '#=-': reserved.add((c, r))
for r in range(27, 35):
    for c in range(0, 9): reserved.add((c, r))

for r in range(H):
    for c in range(W):
        if (c, r) in reserved or P[r][c] != ' ': continue
        t = T[r][c]; x = rng.random()
        near_water = any(inb(*n) and T[n[1]][n[0]] in '~-' for n in nbrs(c, r))
        if t in '.:' and near_water:
            if x < 0.45: P[r][c] = 'r'
            elif t == ':' and x < 0.5: P[r][c] = 'o'
        elif t == 'f':
            clearing = math.hypot(c-14, r-9) < 3.5
            if not clearing and x < 0.28: P[r][c] = 'P' if rng.random() < 0.45 else 'T'
            elif x < 0.33: P[r][c] = 'b'
            elif x < 0.43: P[r][c] = 'n'
            elif x < 0.445: P[r][c] = 'L'
            elif x < 0.455: P[r][c] = 's'
        elif t == '.':
            near_rock = any(inb(*n) and T[n[1]][n[0]] == '^' for n in nbrs(c, r))
            if near_rock and x < 0.3: P[r][c] = 'o'
            elif c > 78 and x < 0.16: P[r][c] = 'P'
            elif x < 0.02: P[r][c] = 'T' if rng.random() < 0.65 else 'B'
            elif x < 0.04: P[r][c] = 'b'
            elif x < 0.05: P[r][c] = 'o'
            elif x < 0.085: P[r][c] = 'w'
            elif x < 0.0865: P[r][c] = 's'
        elif t == ':' and x < 0.05: P[r][c] = 'o'
for r in range(H):
    for c in range(W):
        if P[r][c] == '@': P[r][c] = ' '

data_rows_t = [''.join(row) for row in T]
data_rows_p = [''.join(row) for row in P]
out = ROOT / "data/maps/millbrook_outskirts.json"
L = ['{', '\t"schema_version": 1,', '\t"id": "millbrook_outskirts",', '\t"name": "Millbrook Outskirts",',
     '\t"background_color": "#141a10",', '\t"music": "village",', '\t"ambience": "outdoors",',
     f'\t"spawns": {{"party": {json.dumps(list(spawn))}}},', '\t"terrain": [']
L += [f'\t\t{json.dumps(r)}' + (',' if i < H-1 else '') for i, r in enumerate(data_rows_t)]
L += ['\t],', '\t"prop_legend": {"T": "tree_oak", "P": "tree_pine", "B": "tree_birch", "b": "bush", "o": "rock", "r": "reeds", "n": "fern", "w": "flowers", "L": "log", "s": "stump"},', '\t"prop_layer": [']
L += [f'\t\t{json.dumps(r)}' + (',' if i < H-1 else '') for i, r in enumerate(data_rows_p)]
L += ['\t],', '\t"props": [']
L += [f'\t\t{json.dumps(p)}' + (',' if i < len(props)-1 else '') for i, p in enumerate(props)]
L += ['\t]', '}']
out.write_text('\n'.join(L) + '\n')
json.loads(out.read_text())
print("wrote", out, "with", len(props), "placed props")
