#!/usr/bin/env python3
"""Generates the Millbrook building interiors (data/maps/millbrook_*.json).

Each interior is exactly the size of its building's footprint outside (8x6
for a cottage, 12x8 for the inn), uses a pre-rendered room backdrop from
assets/interiors/backdrops.json (written by tools/art/blender/render_interiors.py)
and has a "door_exit" on the bottom row that leads back outside to the
building's door. Furniture and containers (with their contents) are listed
per room below.

A house can also ask for furnishing **add-ons**, laid out automatically
around whatever is already in the room (see ADDONS below):

    "addons": ["bar", "tables:4"]

on the house placement in the village map (generate_millbrook.py writes it),
or in the room's entry here. Any cottage can become a tavern that way. Edit
and re-run:

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
RECTS = {"table": (2, 2), "bed": (2, 1), "bar_counter": (4, 1), "rug": (3, 2), "bar_back": (3, 1)}
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
        dict(type="cupboard", at=[0, 0], id="pantry", name="Pantry",
             items=[item("rations", 4), item("torch", 5), item("lantern")]),
        dict(type="chest", at=[1, 0], id="cashbox", name="Cash Box", locked=True, lock_dc=12,
             items=[item("garnet")], gold=35),
        dict(type="rug", at=[9, 1]),
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


# --------------------------------------------------------------------------
# Furnishing add-ons
# --------------------------------------------------------------------------

class Layout:
    """Free and blocked cells of a room while furniture is being placed."""

    def __init__(self, cols, rows, entry, exit_cell, keep_clear):
        self.cols, self.rows = cols, rows
        self.entry, self.exit = tuple(entry), tuple(exit_cell)
        self.blocked = set()
        # Never block the door, the hex inside it, or the floor in front of the hearth.
        self.reserved = {self.entry, self.exit} | {(c, 0) for c in keep_clear} | {(c, 1) for c in keep_clear}

    def fits(self, cells, margin=False):
        for (c, r) in cells:
            if not (0 <= c < self.cols and 0 <= r < self.rows) or (c, r) in self.blocked or (c, r) in self.reserved:
                return False
        if margin:  # keep a walkable ring around it (aisles between tables)
            around = {n for cell in cells for n in neighbours(*cell)} - set(cells)
            if any(n in self.blocked for n in around):
                return False
        return self.connected_without(cells)

    def connected_without(self, cells):
        blocked = self.blocked | set(cells)
        seen, todo = {self.entry}, [self.entry]
        while todo:
            cur = todo.pop()
            for n in neighbours(*cur):
                if 0 <= n[0] < self.cols and 0 <= n[1] < self.rows and n not in blocked and n not in seen:
                    seen.add(n)
                    todo.append(n)
        free = {(c, r) for r in range(self.rows) for c in range(self.cols)} - blocked
        return free <= seen

    def add(self, p, ground=False):
        if not ground:
            self.blocked.update(cells_of(p))


def addon_bar(layout, props):
    """A bar: shelves of bottles against the back wall, the counter two rows
    in front of them (room for the barkeep between), and kegs beside it."""
    centre = layout.cols // 2 - 2
    for dc in sorted(range(-layout.cols, layout.cols), key=abs):
        c = centre + dc
        back = dict(type="bar_back", at=[c, 0])
        counter = dict(type="bar_counter", at=[c, 2])
        if layout.fits(cells_of(back)) and layout.fits(cells_of(counter)) \
                and layout.fits(cells_of(back) + cells_of(counter)):
            layout.add(back)
            layout.add(counter)
            props += [back, counter]
            for kc in (c + 3, c - 1):
                kegs = dict(type="barrels", at=[kc, 0])
                if layout.fits(cells_of(kegs)):
                    layout.add(kegs)
                    props.append(kegs)
                    break
            return
    raise AssertionError("no room for a bar")


def addon_tables(layout, props, count):
    """Tables with benches (2x2), spread out with aisles between them."""
    placed = []
    candidates = [(c, r) for r in range(2, layout.rows - 1) for c in range(layout.cols - 1)]
    # Prefer spots far from the tables already placed, then from the door.
    while len(placed) < count:
        best, best_score = None, None
        for (c, r) in candidates:
            t = dict(type="table", at=[c, r])
            if not layout.fits(cells_of(t), margin=True):
                continue
            spread = min([abs(c - pc) + abs(r - pr) for (pc, pr) in placed] or [99])
            score = (spread, -abs(c - layout.exit[0]) - abs(r - layout.exit[1]) * 0.1)
            if best_score is None or score > best_score:
                best, best_score = t, score
        if best is None:
            break
        layout.add(best)
        props.append(best)
        placed.append(tuple(best["at"]))
    assert len(placed) == count, f"room for only {len(placed)} of {count} tables"


ADDONS = {"bar": addon_bar, "tables": addon_tables}


def apply_addons(room, addons, bd, props):
    cols, rows = bd["size"]
    exit_col, exit_row = bd["exit"]
    layout = Layout(cols, rows, [exit_col, exit_row - 1], [exit_col, exit_row], bd.get("keep_clear", []))
    for p in props:
        layout.add(p, ground=p["type"] in GROUND)
    for spec in addons:
        name, _, n = spec.partition(":")
        assert name in ADDONS, f"{room['id']}: unknown add-on '{name}' (known: {', '.join(ADDONS)})"
        if n:
            ADDONS[name](layout, props, int(n))
        else:
            ADDONS[name](layout, props) if name != "tables" else ADDONS[name](layout, props, 2)


def build(room, backdrops, addons=()):
    bd = backdrops[room["backdrop"]]
    cols, rows = bd["size"]
    exit_col, exit_row = bd["exit"]
    entry = [exit_col, exit_row - 1]
    furniture = [dict(p) for p in room["props"]]
    apply_addons(room, list(room.get("addons", [])) + list(addons), bd, furniture)
    blocked = set()
    for p in furniture:
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
    props = furniture
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


def house_addons():
    """Add-ons requested by the houses on the village map, by building id."""
    village = json.loads((ROOT / "data/maps/millbrook_outskirts.json").read_text())
    return {p["id"]: p.get("addons", []) for p in village.get("props", []) if "interior" in p and "id" in p}


def check_addons_fit(backdrops):
    """Every room style must take a bar and two tables, so any house can be a tavern."""
    for name, bd in backdrops.items():
        props = []
        apply_addons({"id": name}, ["bar", "tables:2"], bd, props)
    print("bar + 2 tables fit in every room style:", ", ".join(backdrops))


def main():
    backdrops = json.loads((ROOT / "assets/interiors/backdrops.json").read_text())
    check_addons_fit(backdrops)
    addons = house_addons()
    for room in ROOMS:
        out = ROOT / "data/maps" / f"{room['id']}.json"
        write(out, build(room, backdrops, addons.get(room["id"], [])))
        print("wrote", out, "add-ons:", ", ".join(addons.get(room["id"], [])) or "none")


if __name__ == "__main__":
    main()
