#!/usr/bin/env python3
"""Generates data/maps/old_temple_road.json: the overgrown road east of
Millbrook that climbs into the hills to a ruined temple.

Bandits have made camp where the road crosses a clearing, and the dead walk
among the temple's broken walls. The road leaves the map at its west edge,
back to Millbrook's east road. Usage:

    python3 tools/maps/generate_old_temple_road.py
"""
import json
import math
import random
import sys
from pathlib import Path

import numpy as np

W, H = 52, 40
rng = random.Random(23)
ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[2]
VILLAGE = "res://data/maps/millbrook_outskirts.json"


def o2a(c, r): return (c - (r - (r & 1)) // 2, r)
def a2o(q, r): return (q + (r - (r & 1)) // 2, r)
DIRS = [(1, 0), (1, -1), (0, -1), (-1, 0), (-1, 1), (0, 1)]
def nbrs(c, r):
    q, rr = o2a(c, r)
    return [a2o(q + dq, rr + dr) for dq, dr in DIRS]
def inb(c, r): return 0 <= c < W and 0 <= r < H


T = [['.' for _ in range(W)] for _ in range(H)]
P = [[' ' for _ in range(W)] for _ in range(H)]
reserved = set()
road = set()


def vnoise(seed, scale):
    g = np.random.default_rng(seed).random((H // scale + 3, W // scale + 3))
    def f(c, r):
        x, y = c / scale, r / scale; x0, y0 = int(x), int(y); tx, ty = x - x0, y - y0
        tx, ty = tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty)
        a = g[y0, x0] * (1 - tx) + g[y0, x0 + 1] * tx; b = g[y0 + 1, x0] * (1 - tx) + g[y0 + 1, x0 + 1] * tx
        return a * (1 - ty) + b * ty
    return f
n1 = vnoise(31, 6); n2 = vnoise(32, 3)


def line(a, b):
    (ac, ar), (bc, br) = a, b
    n = max(abs(bc - ac), abs(br - ar), 1)
    return [(round(ac + (bc - ac) * i / n), round(ar + (br - ar) * i / n)) for i in range(n + 1)]


# --- ground: hills of bare rock to the north and south, woods between ----------------
for r in range(H):
    for c in range(W):
        n = n1(c, r)
        if (r < 3 and c < 30) or (r > H - 4 and n > 0.35) or (n2(c, r) > 0.82 and (r < 14 or r > 32)):
            T[r][c] = '^'
        elif n > 0.58 and not (30 < c and r < 16):
            T[r][c] = 'f'

# --- the road: in from the west, through the bandits' clearing, up to the ruin -------
WAYPOINTS = [(0, 30), (8, 30), (14, 27), (20, 24), (27, 21), (32, 17), (36, 15), (40, 13)]
for a, b in zip(WAYPOINTS, WAYPOINTS[1:]):
    for (c, r) in line(a, b):
        for cc in (c, c + 1):
            if inb(cc, r):
                T[r][cc] = ','
                road.add((cc, r))

# --- the bandit camp: a clearing around the road ---------------------------------------
CAMP = (20, 21)
for r in range(H):
    for c in range(W):
        if math.hypot(c - CAMP[0], (r - CAMP[1]) * 1.1) < 6.5 and T[r][c] != ',':
            T[r][c] = '.'

# --- the ruined temple: a flagged courtyard on the hilltop ----------------------------
RUIN = (35, 3, 47, 12)  # c0, r0, c1, r1
for r in range(RUIN[1] - 1, RUIN[3] + 3):
    for c in range(RUIN[0] - 2, RUIN[2] + 3):
        if inb(c, r):
            T[r][c] = '.' if T[r][c] in '^f' else T[r][c]
for r in range(RUIN[1] + 1, RUIN[3] + 1):
    for c in range(RUIN[0] + 1, RUIN[2]):
        T[r][c] = '#'

props = []


def rect_cells(at, cols, rows):
    return [(at[0] + dc, at[1] + dr) for dr in range(rows) for dc in range(cols)]


def place(kind, cells, at, margin=0, allowed='.f#,:', **extra):
    for (c, r) in cells:
        assert inb(c, r), (kind, at, c, r)
        assert P[r][c] == ' ' and (c, r) not in reserved and T[r][c] in allowed, (kind, at, (c, r), T[r][c], P[r][c])
    for (c, r) in cells:
        P[r][c] = '@'
        reserved.add((c, r))
    if margin:
        ring = set(cells)
        for _ in range(margin):
            ring |= {n for (c, r) in ring for n in nbrs(c, r)}
        reserved.update(ring)
    e = {"type": kind, "at": list(at)}
    e.update(extra)
    props.append(e)


def one(kind, cell, **extra):
    place(kind, [cell], cell, **extra)


# Camp: two tents, a fire with log seats, supplies and the bandits' strongbox.
place("tent", rect_cells((15, 17), 2, 2), (15, 17), margin=1)
place("tent", rect_cells((22, 16), 2, 2), (22, 16), margin=1)
one("campfire", (19, 20))
one("log", (17, 21))
one("log", (21, 19))
one("crates", (25, 19))
one("barrels", (13, 21))
one("chest", (18, 18), id="bandit_chest", name="Bandits' Strongbox", locked=True, lock_dc=13,
    items=[{"item": "potion_of_healing", "qty": 2}, {"item": "garnet", "qty": 1}, {"item": "arrows", "qty": 20},
           {"item": "scroll_of_burning_hands", "qty": 1}, {"item": "gauntlets_of_ogre_power", "qty": 1},
           {"item": "potion_of_hill_giant_strength", "qty": 1}], gold=45,
    trap={"name": "poison needle", "find_dc": 13, "disarm": {"dc": 13, "ability": "dex", "tool": "thieves_tools"},
          "save": "con", "save_dc": 12, "damage": "2d6", "damage_type": "poison", "half_on_save": True})

# Ruin: broken walls along the back, columns down the sides, an open front.
place("ruined_wall", rect_cells((36, 3), 3, 1), (36, 3), variant=0)
place("ruined_wall", rect_cells((39, 3), 3, 1), (39, 3), variant=1)
place("ruined_wall", rect_cells((43, 3), 3, 1), (43, 3), variant=0)
for k, r in enumerate((5, 7, 9, 11)):
    one("broken_column", (35, r), variant=k % 2)
    one("broken_column", (47, r), variant=(k + 1) % 2)
place("altar", rect_cells((40, 5), 2, 1), (40, 5))
one("standing_stone", (44, 6), title="Carved Stone",
    text="The runes are old, older than the temple. Odran can make out a few of them:\n\n"
         "\"...the lamp that was lit at the first dawn... carried into the hills... it will not go out "
         "while one who keeps it still walks...\"\n\nThe rest is worn smooth.")
one("chest", (37, 5), id="ruin_chest", name="Mouldering Chest", variant=1,
    items=[{"item": "potion_of_greater_healing", "qty": 1}, {"item": "silver_amulet", "qty": 1},
           {"item": "garnet", "qty": 2}, {"item": "scroll_of_magic_missile", "qty": 1},
           {"item": "longsword_plus_one", "qty": 1}, {"item": "amulet_of_health", "qty": 1}], gold=60,
    trap={"name": "fire glyph", "find_dc": 15, "disarm": {"dc": 14, "ability": "int", "skill": "arcana"},
          "save": "dex", "save_dc": 13, "damage": "3d6", "damage_type": "fire", "half_on_save": True})
for cell in ((38, 8), (43, 10), (45, 8), (39, 11)):
    one("rubble", cell)

# The way back to Millbrook, and the road's start.
one("waymarker", (1, 28), name="Road to Millbrook", map=VILLAGE, entry="east_road")

# --- foes --------------------------------------------------------------------------------
creatures = []


def creature(kind, cell, group, spawn_id, wander=1):
    c, r = cell
    assert inb(c, r) and P[r][c] == ' ' and T[r][c] in '.f#,:', (spawn_id, cell, T[r][c], P[r][c])
    P[r][c] = '@'
    reserved.add(cell)
    creatures.append({"id": spawn_id, "type": kind, "at": [c, r], "group": group, "wander": wander})


creature("bandit", (18, 22), "road_bandits", "bandit_1")
creature("bandit", (21, 21), "road_bandits", "bandit_2")
creature("bandit_archer", (24, 18), "road_bandits", "bandit_archer_1", 0)
creature("bandit_archer", (14, 19), "road_bandits", "bandit_archer_2", 0)
creature("skeleton", (39, 8), "temple_dead", "skeleton_1")
creature("skeleton", (42, 9), "temple_dead", "skeleton_2")
creature("skeleton_archer", (42, 6), "temple_dead", "skeleton_archer_1", 0)

SPAWN = (3, 30)
reserved.update(road)
for (c, r) in line((0, 28), (6, 32)):
    reserved.add((c, r))
for r in range(27, 34):
    for c in range(0, 7):
        reserved.add((c, r))

# --- scatter: trees in the woods, bushes and flowers on the grass, stones by the rocks --
for r in range(H):
    for c in range(W):
        if (c, r) in reserved or P[r][c] != ' ':
            continue
        t = T[r][c]
        x = rng.random()
        near_rock = any(inb(*n) and T[n[1]][n[0]] == '^' for n in nbrs(c, r))
        in_ruin = RUIN[0] - 2 <= c <= RUIN[2] + 2 and RUIN[1] - 1 <= r <= RUIN[3] + 2
        in_camp = math.hypot(c - CAMP[0], (r - CAMP[1]) * 1.1) < 6.5
        if in_ruin or in_camp:
            if t == '.' and x < 0.04:
                P[r][c] = 'w'
            continue
        if t == 'f':
            if x < 0.3:
                P[r][c] = 'P' if rng.random() < 0.55 else 'T'
            elif x < 0.38:
                P[r][c] = 'b'
            elif x < 0.47:
                P[r][c] = 'n'
            elif x < 0.48:
                P[r][c] = 'L'
        elif t == '.':
            if near_rock and x < 0.25:
                P[r][c] = 'o'
            elif x < 0.03:
                P[r][c] = 'T' if rng.random() < 0.5 else 'P'
            elif x < 0.06:
                P[r][c] = 'b'
            elif x < 0.1:
                P[r][c] = 'w'
            elif x < 0.105:
                P[r][c] = 's'
for r in range(H):
    for c in range(W):
        if P[r][c] == '@':
            P[r][c] = ' '


# --- checks: everything reachable from the spawn ------------------------------------------
_blocked = set()
SIZES = {"tent": (2, 2), "ruined_wall": (3, 1), "altar": (2, 1)}
for p in props:
    cols, rows = SIZES.get(p["type"], (1, 1))
    if p["type"] == "rubble":
        continue
    for cell in rect_cells(p["at"], cols, rows):
        _blocked.add(cell)
TREES = set("TPBbo")
seen, todo = {SPAWN}, [SPAWN]
while todo:
    cur = todo.pop()
    for n in nbrs(*cur):
        c, r = n
        if n in seen or not inb(c, r) or T[r][c] in '~^' or n in _blocked or P[r][c] in TREES:
            continue
        seen.add(n)
        todo.append(n)
for cr in creatures:
    assert tuple(cr["at"]) in seen, ("unreachable creature", cr)
for p in props:
    if p["type"] in ("chest", "standing_stone", "waymarker"):
        assert any(n in seen for n in nbrs(*p["at"])), ("unreachable", p)

out = ROOT / "data/maps/old_temple_road.json"
L = ['{', '\t"schema_version": 1,', '\t"id": "old_temple_road",', '\t"name": "The Old Temple Road",',
     '\t"background_color": "#12160e",', '\t"music": "village",', '\t"ambience": "outdoors",',
     f'\t"spawns": {{"party": {json.dumps(list(SPAWN))}}},',
     f'\t"entries": {{"west": {json.dumps(list(SPAWN))}}},', '\t"terrain": [']
L += [f'\t\t{json.dumps("".join(row))}' + (',' if i < H - 1 else '') for i, row in enumerate(T)]
L += ['\t],', '\t"prop_legend": {"T": "tree_oak", "P": "tree_pine", "B": "tree_birch", "b": "bush", "o": "rock", '
      '"r": "reeds", "n": "fern", "w": "flowers", "L": "log", "s": "stump"},', '\t"prop_layer": [']
L += [f'\t\t{json.dumps("".join(row))}' + (',' if i < H - 1 else '') for i, row in enumerate(P)]
L += ['\t],', '\t"creatures": [']
L += [f'\t\t{json.dumps(c)}' + (',' if i < len(creatures) - 1 else '') for i, c in enumerate(creatures)]
L += ['\t],', '\t"props": [']
L += [f'\t\t{json.dumps(p)}' + (',' if i < len(props) - 1 else '') for i, p in enumerate(props)]
L += ['\t]', '}']
out.write_text('\n'.join(L) + '\n')
json.loads(out.read_text())
print("wrote", out, "with", len(props), "props and", len(creatures), "creatures")
