# Audio

Game code never refers to sound files directly. It asks the `Audio` autoload
(`scripts/autoload/audio.gd`) for a **name**, and
[`data/audio/audio.json`](../data/audio/audio.json) maps names to files:

```json
{
  "sfx": { "coins": "res://assets/audio/sfx/coins.ogg",
           "door_open": ["res://.../door_a.ogg", "res://.../door_b.ogg"] },
  "music": { "village": "res://assets/audio/music/village.ogg" },
  "ambience": { "outdoors": "res://assets/audio/ambience/outdoors.ogg" }
}
```

A list picks one file at random each time. To replace a sound, overwrite the file or
point the name at another `.ogg`/`.wav`. Files outside the project (`user://...`) work
for `.ogg`. A missing file logs one warning and is otherwise skipped.

| Call | Use |
|---|---|
| `Audio.play_sfx("coins")` | One-shot effect (slightly varied pitch). |
| `Audio.play_music("village")` | Crossfades to a looping track; `""` stops. |
| `Audio.play_ambience("outdoors")` | Same, for the background loop. |

Maps choose their music and ambience with `"music"` and `"ambience"` (see
[MAPS.md](MAPS.md)). Effects currently in use: `ui_click`, `ui_open`, `item_pickup`,
`item_drop`, `equip`, `equip_armor`, `coins`, `potion`, `chest_open`, `door_open`, `locked`,
`unlock`, `save`, `error`.

There are three buses, `Music`, `SFX` and `Ambience`, created at start-up if the project
has none, with volumes in decibels from `audio_volume_db` in `game_config.json`.

## Placeholder sounds

Everything in `assets/audio/` is synthesised by
`tools/audio/generate_placeholder_audio.py` (numpy, scipy and soundfile): filtered-noise
rustles and creaks, small metal "clinks" for coins and gear, Karplus-Strong plucked
strings for the village and hearth music loops, a slow organ pad with a chant line and
long stone-hall echoes for the temple, and wind, birdsong and fire crackle for the
ambience loops. `python3 tools/audio/generate_placeholder_audio.py temple` regenerates
one group (`sfx`, `music`, `temple`, `ambience`) and leaves the others alone. They are there to prove the hooks work; real recordings will sound far better.
