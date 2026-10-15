class_name NpcDef
extends RefCounted
## One townsperson from data/npcs/npcs.json (see docs/NPCS_AND_QUESTS.md).

var id: String = ""
var display_name: String = ""
## Shown under the name in dialogue ("Innkeeper").
var title: String = ""
var portrait_path: String = ""
## Sprite sheet description (assets/characters/<look>_anim.json).
var animation_path: String = ""
var sprite_path: String = ""
var dialogue_path: String = ""
## How far from their spot they stroll, in hexes (0 = stands still).
var wander_radius: int = 0
## Shop: {"stock": [{"item", "qty"}], "markup": 1.0, "buy_rate": 0.5}; empty = not a vendor.
var vendor: Dictionary = {}


static func from_dict(npc_id: String, d: Dictionary) -> NpcDef:
	var n := NpcDef.new()
	n.id = npc_id
	n.display_name = str(d.get("name", npc_id.capitalize()))
	n.title = str(d.get("title", ""))
	n.portrait_path = str(d.get("portrait", "res://assets/portraits/default.png"))
	n.animation_path = str(d.get("animation", ""))
	n.sprite_path = str(d.get("sprite", ""))
	n.dialogue_path = str(d.get("dialogue", ""))
	n.wander_radius = maxi(0, int(d.get("wander", 0)))
	n.vendor = d.get("vendor", {}) if d.get("vendor") is Dictionary else {}
	return n


func is_vendor() -> bool:
	return not vendor.is_empty()


## Buy and sell rates for InventoryOps: what the party pays, and what it gets.
func trade_terms() -> Dictionary:
	return {"markup": float(vendor.get("markup", 1.0)), "buy_rate": float(vendor.get("buy_rate", 0.5)),
			"vendor": display_name}
