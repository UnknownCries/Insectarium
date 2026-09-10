# Insectarium



A top-down, procedurally generated dungeon crawler built in Godot 4 with an insect theme.



## Gameplay



- **Procedural dungeons** — Each floor is generated from a pool of hand-authored room templates (1x1, 1x2, 2x2, L-shaped), stitched together into a connected layout with a guaranteed boss room and item room.

- **Room-by-room combat** — Doors lock once you enter a room and defeat enemies to unlock it.

- **Enemies** — Melee, ranged and jumping types, each with their own AI.

- **Three bosses** — Segmented, jumping ambush and minion-summoning.

- **Pickups** — Pick up hearts to heal, and stat-up items (health, damage, speed, fire rate, range).

- **Floor progression** — Descend through multiple floors until you reach the end.



## Controls



| Action | Input |
|---|---|
| Move | `WASD` / Arrow keys |
| Aim & Shoot | Mouse position / Left click |
| Pause | `Esc` |



## Building the project



1. Install [Godot 4.7+](https://godotengine.org/download).

2. Clone the repo and open `project.godot` in Godot.

3. Press **Run** (or `F5`).



## Project structure



```

scripts/dungeon/   GDScript sources (generation, rooms, entities, UI)

resources/          Room template resources (.tres)

rooms/               Base room scenes

assets/              Sprites, tiles, and audio

*.tscn               Entity/UI scenes (player, enemies, bosses, pickups, HUD, menus)

dungeon.tscn         Main scene

```



Dungeon generation is split across `dungeon_generator.gd` (grid layout, no scene instancing) and `dungeon_builder.gd`/`room_auto_builder.gd` (turns a generated layout into actual room scenes, walls, and floor tiles).
