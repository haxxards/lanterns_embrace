#!/usr/bin/env python3
"""Generates the Millbrook building interiors (data/maps/millbrook_*.json).

Each interior is exactly the size of its building's footprint outside (8x6
for a cottage, 12x8 for the inn), uses a pre-rendered room backdrop from
assets/interiors/backdrops.json (written by tools/art/blender/render_interiors.py)
and has a "door_exit" on the bottom row that leads back outside to the
building's door. Furniture and containers (with their contents) are listed
per room below; edit and re-run:

    python3 tools/maps/generate_interiors.py
"""
import json
import sys
from pathlib import Path

ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[2]
OUTSIDE = "res://data/maps/millbrook_outskirts.json"


def item(item_id, qty=1):
    return {"item": item_id, "qty": qty}


# Footprints of the furniture types, [cols, rows] (1x1 when not listed).
RECTS = {"table": (2, 2), "bed": (2, 1), "bar_counter": (4, 1), "rug": (3, 2)}
GROUND = {"rug"}

ROOMS = [
    dict(id="millbrook_miller", name="Miller's Cottage", backdrop="cottage_plaster", props=[
        dict(type="bed", at=[5, 0]),
        dict(type="dresser", at=[7, 0], id="drawers", name="Chest of Drawers",
             items=[item("apple", 5), item("rations", 2)], gold=12),
        dict(type="rug", at=[0, 1]),
        dict(type="table", at=[2, 2]),
        dict(type="chest", at=[0, 4], id="chest", name="Old Chest", variant=1,
             items=[item("leather_boots"), item("torch", 3)]),
        dict(type="crates", at=[7, 3]),
        dict(type="barrels", at=[7, 4]),
    ]),
    dict(id="millbrook_reeve", name="Reeve's House", backdrop="cottage_timber", props=[
        dict(type="cupboard", at=[0, 0], id="cupboard", name="Cupboard", items=[item("rations", 3), item("torch", 2)]),
        dict(type="bed", at=[4, 0]),
        dict(type="chest", at=[7, 1], id="strongbox", name="Reeve's Strongbox", locked=True, lock_dc=15,
             key="reeve_key", items=[item("ring_of_protection"), item("garnet", 2)], gold=60),
        dict(type="rug", at=[2, 2]),
        dict(type="table", at=[1, 3]),
        dict(type="dresser", at=[7, 3], id="desk", name="Reeve's Drawers",
             items=[item("reeve_key"), item("silver_amulet")], gold=8),
    ]),
    dict(id="millbrook_herbalist", name="Herbalist's Cottage", backdrop="cottage_stone", props=[
        dict(type="cupboard", at=[3, 0], variant=1, id="remedies", name="Shelf of Remedies",
             items=[item("potion_of_healing", 2), item("potion_of_greater_healing")]),
        dict(type="cupboard", at=[4, 0], variant=1, id="jars", name="Shelf of Jars",
             items=[item("apple", 3), item("leather_gloves")]),
        dict(type="table", at=[2, 2]),
        dict(type="dresser", at=[7, 2], id="drawers", name="Chest of Drawers", items=[item("rations")], gold=5),
        dict(type="bed", at=[0, 4]),
        dict(type="barrels", at=[7, 4]),
    ]),
    dict(id="millbrook_smithy", name="Smithy", backdrop="smithy", props=[
        dict(type="chest", at=[0, 1], id="chest", name="Tool Chest",
             items=[item("warhammer"), item("chain_shirt"), item("iron_helm")]),
        dict(type="anvil", at=[4, 2]),
        dict(type="chest", at=[7, 2], id="locked_chest", name="Locked Chest", variant=1, locked=True, lock_dc=12,
             items=[item("shortbow"), item("arrows", 20)]),
        dict(type="barrels", at=[0, 3]),
        dict(type="crates", at=[7, 4]),
    ]),
    dict(id="millbrook_inn", name="The Lantern & Thistle", backdrop="inn_hall", props=[
        dict(type="cupboard", at=[4, 0], id="pantry", name="Pantry",
             items=[item("rations", 4), item("torch", 5), item("lantern")]),
        dict(type="barrels", at=[5, 0]),
        dict(type="chest", at=[7, 0], id="cashbox", name="Cash Box", locked=True, lock_dc=12,
             items=[item("garnet")], gold=35),
        dict(type="barrels", at=[8, 0]),
        dict(type="table", at=[1, 1]),
        dict(type="rug", at=[9, 1]),
        dict(type="bar_counter", at=[5, 2]),
        dict(type="table", at=[1, 4]),
        dict(type="table", at=[9, 4]),
        dict(type="table", at=[6, 5]),
        dict(type="chest", at=[11, 7], id="sea_chest", name="Traveller's Chest",
             items=[item("cloak_of_protection"), item("studded_leather")]),
        dict(type="dresser", at=[0, 7], id="linen", name="Linen Drawers", items=[item("rations", 2)], gold=3),
    ]),
]


def o2a(c, r):
    return (c - (r - (r & 1)) // 2, r)


def a2o(q, r):
    return (q + (r - (r & 1)) // 2, r)


def neighbours(c, r):
    q, rr = o2a(c, r)
    return [a2o(q + dq, rr + dr) for dq, dr in ((1, 0), (1, -1), (0, -1), (-1, 0), (-1, 1), (0, 1))]


def cells_of(p):
    cols, rows = RECTS.get(p["type"], (1, 1))
    return [(p["at"][0] + dc, p["at"][1] + dr) for dr in range(rows) for dc in range(cols)]


def build(room, backdrops):
    bd = backdrops[room["backdrop"]]
    cols, rows = bd["size"]
    exit_col, exit_row = bd["exit"]
    entry = [exit_col, exit_row - 1]
    blocked = set()
    for p in room["props"]:
        for (c, r) in cells_of(p):
            assert 0 <= c < cols and 0 <= r < rows, (room["id"], p, (c, r))
            if p["type"] not in GROUND:
                assert (c, r) not in blocked, (room["id"], "overlap", p, (c, r))
                blocked.add((c, r))
    for cell in ((exit_col, exit_row), tuple(entry)):
        assert cell not in blocked, (room["id"], "door blocked", cell)
    # Everything walkable must be reachable from the door.
    seen, todo = {tuple(entry)}, [tuple(entry)]
    while todo:
        cur = todo.pop()
        for n in neighbours(*cur):
            if 0 <= n[0] < cols and 0 <= n[1] < rows and n not in blocked and n not in seen:
                seen.add(n)
                todo.append(n)
    free = {(c, r) for r in range(rows) for c in range(cols)} - blocked
    assert free <= seen, (room["id"], "unreachable floor", sorted(free - seen))
    props = [dict(p) for p in room["props"]]
    props.append({"type": "door_exit", "at": [exit_col, exit_row], "name": "Way out", "map": OUTSIDE,
                  "entry": room["id"]})
    return {
        "schema_version": 1,
        "id": room["id"],
        "name": room["name"],
        "background_color": "#0b0907",
        "fog": False,
        "music": "hearth",
        "ambience": "fireplace",
        "backdrop": {"texture": bd["texture"], "origin": bd["origin"]},
        "spawns": {"party": entry},
        "entries": {"door": entry},
        "terrain": ["_" * cols for _ in range(rows)],
        "props": props,
    }


def write(path, data):
    lines = ["{"]
    keys = list(data)
    for i, k in enumerate(keys):
        comma = "," if i < len(keys) - 1 else ""
        v = data[k]
        if k in ("terrain", "props"):
            lines.append(f'\t"{k}": [')
            lines += [f"\t\t{json.dumps(x)}" + ("," if j < len(v) - 1 else "") for j, x in enumerate(v)]
            lines.append("\t]" + comma)
        else:
            lines.append(f'\t"{k}": {json.dumps(v)}{comma}')
    lines.append("}")
    path.write_text("\n".join(lines) + "\n")


def main():
    backdrops = json.loads((ROOT / "assets/interiors/backdrops.json").read_text())
    for room in ROOMS:
        out = ROOT / "data/maps" / f"{room['id']}.json"
        write(out, build(room, backdrops))
        print("wrote", out)


if __name__ == "__main__":
    main()
