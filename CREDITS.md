# Credits

## Rules

This work includes material taken from the System Reference Document 5.1 ("SRD 5.1") by
Wizards of the Coast LLC, available at https://dnd.wizards.com/resources/systems-reference-document.
The SRD 5.1 is licensed under the Creative Commons Attribution 4.0 International License,
available at https://creativecommons.org/licenses/by/4.0/legalcode.

Only game mechanics and terms from the SRD are used (ability scores and modifiers,
proficiency bonus, experience thresholds, class hit dice, armour values). No setting,
characters or trademarked names are used.

## Art

Terrain, props and character sprites were generated for this project: they are
procedural 3D scenes rendered with [Blender](https://www.blender.org) (GPL; the rendered
images are not covered by Blender's licence) via `tools/art/blender/`. No third-party
textures or models are included.

### Portraits

The portraits in `assets/portraits/` are crops of public-domain paintings from
[The Metropolitan Museum of Art](https://www.metmuseum.org), whose Open Access
programme releases these images under
[CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/). Attribution is not
required, but here they are, with the Met object number (see
`www.metmuseum.org/art/collection/search/<number>`). `tools/art/portraits/make_portraits.py`
recreates every crop from `tools/art/portraits/portraits.json`.

| Portrait | Painting | Artist | Date | Met object |
|---|---|---|---|---|
| `garrick.png` | Portrait of Walter Devereux, First Earl of Essex | British painter | 1572 | 33284 |
| `elowen.png` | Saint Catherine of Alexandria | Bernardo Cavallino | ca. 1645 | 435861 |
| `odran.png` | Study Head of an Old Man with a White Beard | Anthony van Dyck | ca. 1617-20 | 436260 |
| `wren.png` | Boy with a Lute | Frans Hals | ca. 1625 | 436626 |
| `npc_veteran.png` | Man in Armor (Mars?) | Rembrandt (style of) | 17th century | 437416 |
| `npc_pickpocket.png` | The Fortune-Teller | Georges de La Tour | probably 1630s | 436838 |
| `npc_elder.png` | Portrait of an Old Man | Hans Memling | ca. 1475 | 437055 |
| `npc_merchant.png` | Portrait of an Old Man | Hugo van der Goes | ca. 1470-75 | 440840 |
| `npc_priest.png` | Saint Jerome as Scholar | El Greco | ca. 1610 | 459088 |
| `npc_monk.png` | Portrait of a Carthusian | Petrus Christus | 1446 | 435896 |
| `npc_sage.png` | Study Head of an Old Man | Rembrandt (style of) | 17th century | 437421 |
| `npc_noble.png` | Man in a Red Cloak | Rembrandt (style of) | 17th century | 437413 |
| `npc_villager.png` | Sibylle | Camille Corot | ca. 1870 | 435984 |
| `npc_young_knight.png` | Sir John Shurley of Isfield | British painter | 1588 | 435778 |
| `npc_warrior.png` | Bellona | Rembrandt | 1633 | 437389 |
| `npc_bard.png` | Lute Player | Valentin de Boulogne | ca. 1625-26 | 439933 |

`default.png` (the fallback silhouette) was drawn for this project.


## Audio

All sounds, music and ambience in `assets/audio/` were synthesised for this project by
`tools/audio/generate_placeholder_audio.py`. No recordings or samples are included.

## Engine

Built with [Godot Engine](https://godotengine.org) (MIT licence).
