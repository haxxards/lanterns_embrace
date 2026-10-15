#!/usr/bin/env python3
"""Create or validate Lantern's Embrace character sheets (JSON).

Character sheets live in data/characters/<id>.json (or user://characters/ at
runtime) and are loaded by the game on start-up. This script fills in the
derived numbers (hit points, armour class, saving throws, starting kit) from
simple 5e SRD-style class/ancestry tables, so a new party member is one
command away. The tables are deliberately small and easy to extend below.

Examples:
    # Fully specified scores
    python3 tools/make_character.py --id brena --name "Brena Holt" \\
        --class ranger --ancestry human --abilities 12,16,14,10,14,8

    # Standard array (15,14,13,12,10,8) assigned by class priority
    python3 tools/make_character.py --id pip --name "Pip" --class bard \\
        --ancestry halfling --standard-array

    # Roll 4d6-drop-lowest (seeded for reproducibility)
    python3 tools/make_character.py --id rook --name "Rook" --class fighter \\
        --ancestry dwarf --roll --seed 7 --level 3

    # Validate existing sheets
    python3 tools/make_character.py --validate data/characters/*.json

Ability order everywhere is: str, dex, con, int, wis, cha.
"""
import argparse
import json
import random
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCHEMA_VERSION = 1
ABILITIES = ["str", "dex", "con", "int", "wis", "cha"]
STANDARD_ARRAY = [15, 14, 13, 12, 10, 8]

# hit_die, saving throws, ability priority (for array/roll assignment),
# spellcasting ability (or None), starting kit, armour/weapon proficiencies,
# level-1 features, placeholder sprite.
CLASSES = {
    "barbarian": dict(hit_die=12, saves=["str", "con"], priority=["str", "con", "dex", "wis", "cha", "int"],
                      spell_ability=None, armor=None, shield=False, main_hand="greataxe", off_hand=None,
                      armor_prof=["light", "medium", "shields"], weapon_prof=["simple", "martial"],
                      features=["rage", "unarmored_defense"], sprite="fighter", unarmored="con"),
    "bard": dict(hit_die=8, saves=["dex", "cha"], priority=["cha", "dex", "con", "wis", "int", "str"],
                 spell_ability="cha", armor="leather", shield=False, main_hand="rapier", off_hand=None,
                 armor_prof=["light"], weapon_prof=["simple", "hand_crossbow", "longsword", "rapier", "shortsword"],
                 features=["bardic_inspiration"], sprite="rogue"),
    "cleric": dict(hit_die=8, saves=["wis", "cha"], priority=["wis", "con", "str", "cha", "dex", "int"],
                   spell_ability="wis", armor="chain_mail", shield=True, main_hand="mace", off_hand=None,
                   armor_prof=["light", "medium", "heavy", "shields"], weapon_prof=["simple"],
                   features=["divine_domain"], sprite="cleric"),
    "druid": dict(hit_die=8, saves=["int", "wis"], priority=["wis", "con", "dex", "int", "cha", "str"],
                  spell_ability="wis", armor="leather", shield=True, main_hand="quarterstaff", off_hand=None,
                  armor_prof=["light", "medium", "shields"], weapon_prof=["simple"],
                  features=["druidic"], sprite="wizard"),
    "fighter": dict(hit_die=10, saves=["str", "con"], priority=["str", "con", "dex", "wis", "int", "cha"],
                    spell_ability=None, armor="chain_mail", shield=True, main_hand="longsword", off_hand=None,
                    armor_prof=["light", "medium", "heavy", "shields"], weapon_prof=["simple", "martial"],
                    features=["fighting_style_defense", "second_wind"], sprite="fighter"),
    "monk": dict(hit_die=8, saves=["str", "dex"], priority=["dex", "wis", "con", "str", "int", "cha"],
                 spell_ability=None, armor=None, shield=False, main_hand="quarterstaff", off_hand=None,
                 armor_prof=[], weapon_prof=["simple", "shortsword"],
                 features=["unarmored_defense", "martial_arts"], sprite="rogue", unarmored="wis"),
    "paladin": dict(hit_die=10, saves=["wis", "cha"], priority=["str", "cha", "con", "wis", "dex", "int"],
                    spell_ability="cha", armor="chain_mail", shield=True, main_hand="longsword", off_hand=None,
                    armor_prof=["light", "medium", "heavy", "shields"], weapon_prof=["simple", "martial"],
                    features=["divine_sense", "lay_on_hands"], sprite="fighter"),
    "ranger": dict(hit_die=10, saves=["str", "dex"], priority=["dex", "wis", "con", "str", "int", "cha"],
                   spell_ability="wis", armor="leather", shield=False, main_hand="shortsword", off_hand="shortsword",
                   armor_prof=["light", "medium", "shields"], weapon_prof=["simple", "martial"],
                   features=["favored_enemy", "natural_explorer"], sprite="rogue"),
    "rogue": dict(hit_die=8, saves=["dex", "int"], priority=["dex", "con", "int", "wis", "cha", "str"],
                  spell_ability=None, armor="leather", shield=False, main_hand="shortsword", off_hand="dagger",
                  armor_prof=["light"], weapon_prof=["simple", "hand_crossbow", "longsword", "rapier", "shortsword"],
                  features=["expertise", "sneak_attack", "thieves_cant"], sprite="rogue"),
    "sorcerer": dict(hit_die=6, saves=["con", "cha"], priority=["cha", "con", "dex", "wis", "int", "str"],
                     spell_ability="cha", armor=None, shield=False, main_hand="dagger", off_hand=None,
                     armor_prof=[], weapon_prof=["dagger", "dart", "sling", "quarterstaff", "light_crossbow"],
                     features=["sorcerous_origin"], sprite="wizard"),
    "warlock": dict(hit_die=8, saves=["wis", "cha"], priority=["cha", "con", "dex", "wis", "int", "str"],
                    spell_ability="cha", armor="leather", shield=False, main_hand="dagger", off_hand=None,
                    armor_prof=["light"], weapon_prof=["simple"],
                    features=["otherworldly_patron", "pact_magic"], sprite="wizard"),
    "wizard": dict(hit_die=6, saves=["int", "wis"], priority=["int", "con", "dex", "wis", "cha", "str"],
                   spell_ability="int", armor=None, shield=False, main_hand="quarterstaff", off_hand=None,
                   armor_prof=[], weapon_prof=["dagger", "dart", "sling", "quarterstaff", "light_crossbow"],
                   features=["arcane_recovery"], sprite="wizard"),
}

# Extra starting items per class (item ids from data/items/items.json).
CLASS_KIT = {
    "cleric": ["holy_symbol"], "paladin": ["holy_symbol"], "rogue": ["thieves_tools"],
    "wizard": ["spellbook"], "ranger": ["shortbow"], "bard": ["lantern"],
}

# SRD ancestries: walking speed in feet and size.
ANCESTRIES = {
    "human": dict(speed=30, size="medium"),
    "elf": dict(speed=30, size="medium"),
    "half-elf": dict(speed=30, size="medium"),
    "half-orc": dict(speed=30, size="medium"),
    "dragonborn": dict(speed=30, size="medium"),
    "tiefling": dict(speed=30, size="medium"),
    "dwarf": dict(speed=25, size="medium"),
    "gnome": dict(speed=25, size="small"),
    "halfling": dict(speed=25, size="small"),
}

# Armour: base AC, max dex bonus (None = unlimited).
ARMOR = {
    "leather": (11, None),
    "studded_leather": (12, None),
    "hide": (12, 2),
    "chain_shirt": (13, 2),
    "scale_mail": (14, 2),
    "chain_mail": (16, 0),
    "splint": (17, 0),
    "plate": (18, 0),
}

# SRD experience thresholds for levels 1-20.
XP_THRESHOLDS = [0, 300, 900, 2700, 6500, 14000, 23000, 34000, 48000, 64000,
                 85000, 100000, 120000, 140000, 165000, 195000, 225000, 265000, 305000, 355000]

REQUIRED = {
    "schema_version": int, "id": str, "name": str, "ancestry": str, "class": str,
    "level": int, "xp": int, "abilities": dict, "hit_points": dict,
    "armor_class": int, "speed_ft": int, "art": dict,
}


def mod(score):
    return (score - 10) // 2


def assign_by_priority(values, priority):
    vals = sorted(values, reverse=True)
    return {ab: vals[i] for i, ab in enumerate(priority)}


def roll_scores(rng):
    out = []
    for _ in range(6):
        dice = sorted(rng.randint(1, 6) for _ in range(4))
        out.append(sum(dice[1:]))
    return out


def max_hp(cls, level, con_mod):
    die = CLASSES[cls]["hit_die"]
    hp = die + con_mod
    hp += (level - 1) * (die // 2 + 1 + con_mod)
    return max(1, hp)


def armor_class(cls, abilities):
    c = CLASSES[cls]
    dex = mod(abilities["dex"])
    if c["armor"]:
        base, cap = ARMOR[c["armor"]]
        # Heavy armour (cap 0) ignores Dex entirely, penalties included.
        ac = base + (dex if cap is None else 0 if cap == 0 else min(dex, cap))
    elif c.get("unarmored"):
        ac = 10 + dex + mod(abilities[c["unarmored"]])
    else:
        ac = 10 + dex
    return ac + (2 if c["shield"] else 0)


def build_sheet(args):
    cls = args.char_class
    c = CLASSES[cls]
    if args.abilities:
        vals = [int(v) for v in args.abilities.split(",")]
        if len(vals) != 6:
            sys.exit("--abilities needs 6 comma-separated numbers (str,dex,con,int,wis,cha)")
        abilities = dict(zip(ABILITIES, vals))
    elif args.roll:
        abilities = assign_by_priority(roll_scores(random.Random(args.seed)), c["priority"])
    else:
        abilities = assign_by_priority(STANDARD_ARRAY, c["priority"])
    abilities = {ab: abilities[ab] for ab in ABILITIES}

    level = max(1, min(20, args.level))
    hp = max_hp(cls, level, mod(abilities["con"]))
    equipment = {"main_hand": c["main_hand"], "off_hand": c["off_hand"],
                 "armor": c["armor"]}
    if c["shield"]:
        equipment["off_hand"] = "shield"
    inventory = [{"item": "potion_of_healing", "qty": 1}, {"item": "rations", "qty": 2}]
    inventory += [{"item": i, "qty": 1} for i in CLASS_KIT.get(cls, [])]
    sprite = args.sprite or f"res://assets/characters/{c['sprite']}.png"
    portrait = args.portrait or "res://assets/portraits/default.png"
    return {
        "schema_version": SCHEMA_VERSION,
        "id": args.id,
        "name": args.name,
        "ancestry": args.ancestry,
        "class": cls,
        "level": level,
        "xp": XP_THRESHOLDS[level - 1],
        "alignment": args.alignment,
        "abilities": abilities,
        "hit_points": {"max": hp, "current": hp},
        "hit_die": f"d{c['hit_die']}",
        "armor_class": args.armor_class if args.armor_class else armor_class(cls, abilities),
        "speed_ft": ANCESTRIES[args.ancestry]["speed"],
        "size": ANCESTRIES[args.ancestry]["size"],
        "proficiencies": {
            "saving_throws": c["saves"],
            "skills": [s.strip() for s in args.skills.split(",")] if args.skills else [],
            "armor": c["armor_prof"],
            "weapons": c["weapon_prof"],
            "tools": ["thieves_tools"] if cls in ("rogue", "bard") else [],
        },
        "equipment": equipment,
        "inventory": inventory,
        "gold": args.gold,
        "spells": {"ability": c["spell_ability"], "cantrips": [], "known": [], "slots": {}},
        "features": c["features"],
        "art": {"portrait": portrait, "sprite": sprite},
        "bio": args.bio or "",
    }


def validate(path):
    errors = []
    try:
        data = json.loads(Path(path).read_text())
    except (OSError, json.JSONDecodeError) as e:
        return [f"cannot read: {e}"]
    for key, typ in REQUIRED.items():
        if key not in data:
            errors.append(f"missing '{key}'")
        elif not isinstance(data[key], typ):
            errors.append(f"'{key}' should be {typ.__name__}")
    for ab in ABILITIES:
        v = data.get("abilities", {}).get(ab)
        if not isinstance(v, int) or not 1 <= v <= 30:
            errors.append(f"abilities.{ab} must be an integer 1-30")
    hp = data.get("hit_points", {})
    if not isinstance(hp.get("max"), int) or hp.get("max", 0) < 1:
        errors.append("hit_points.max must be a positive integer")
    if data.get("class") not in CLASSES:
        errors.append(f"unknown class '{data.get('class')}' (known: {', '.join(sorted(CLASSES))})")
    if data.get("ancestry") not in ANCESTRIES:
        errors.append(f"unknown ancestry '{data.get('ancestry')}'")
    if isinstance(data.get("level"), int) and not 1 <= data["level"] <= 20:
        errors.append("level must be 1-20")
    for key in ("portrait", "sprite"):
        res = data.get("art", {}).get(key, "")
        if isinstance(res, str) and res.startswith("res://"):
            if not (ROOT / res[len("res://"):]).exists():
                errors.append(f"art.{key} file not found: {res}")
    known = known_items()
    for slot, value in (data.get("equipment") or {}).items():
        item_id = value.get("item") if isinstance(value, dict) else value
        if item_id and item_id not in known:
            errors.append(f"equipment.{slot}: unknown item '{item_id}'")
    for entry in data.get("inventory") or []:
        if entry and entry.get("item") not in known:
            errors.append(f"inventory: unknown item '{entry.get('item')}'")
    return errors


def known_items():
    """Item ids from data/items/items.json (the game's item list)."""
    try:
        return set(json.loads((ROOT / "data/items/items.json").read_text())["items"])
    except (OSError, KeyError, json.JSONDecodeError):
        return set()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--validate", nargs="+", metavar="SHEET", help="validate existing sheet files and exit")
    ap.add_argument("--id")
    ap.add_argument("--name")
    ap.add_argument("--class", dest="char_class", choices=sorted(CLASSES))
    ap.add_argument("--ancestry", choices=sorted(ANCESTRIES), default="human")
    ap.add_argument("--level", type=int, default=1)
    g = ap.add_mutually_exclusive_group()
    g.add_argument("--abilities", help="six scores: str,dex,con,int,wis,cha")
    g.add_argument("--standard-array", action="store_true", help="use 15,14,13,12,10,8 (default)")
    g.add_argument("--roll", action="store_true", help="roll 4d6, drop lowest")
    ap.add_argument("--seed", type=int, default=None)
    ap.add_argument("--armor-class", type=int, default=0, help="override computed AC")
    ap.add_argument("--alignment", default="neutral")
    ap.add_argument("--skills", default="", help="comma-separated skill ids")
    ap.add_argument("--gold", type=int, default=10)
    ap.add_argument("--portrait", help="res:// path to a portrait PNG")
    ap.add_argument("--sprite", help="res:// path to a map sprite PNG")
    ap.add_argument("--bio")
    ap.add_argument("--out", help="output path (default data/characters/<id>.json)")
    ap.add_argument("--stdout", action="store_true", help="print instead of writing a file")
    args = ap.parse_args()

    if args.validate:
        failed = False
        for path in args.validate:
            errs = validate(path)
            print(f"{'OK  ' if not errs else 'FAIL'} {path}")
            for e in errs:
                print(f"     - {e}")
            failed |= bool(errs)
        sys.exit(1 if failed else 0)

    for req in ("id", "name", "char_class"):
        if not getattr(args, req):
            ap.error(f"--{req.replace('char_class', 'class')} is required")
    sheet = build_sheet(args)
    text = json.dumps(sheet, indent="\t") + "\n"
    if args.stdout:
        print(text, end="")
        return
    out = Path(args.out) if args.out else ROOT / "data" / "characters" / f"{args.id}.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(text)
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
