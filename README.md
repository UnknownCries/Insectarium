# Insectarium

A top-down, procedurally generated dungeon crawler built in Godot 4, with an insect theme: play as a spider fighting through bug-infested floors toward three unique bosses.

## Gameplay

- **Procedural dungeons** — each floor is generated from a pool of hand-authored room templates (1x1, 1x2, 2x2, L-shaped, with obstacle variants), stitched together into a connected layout with a guaranteed boss room and item room.
- **Room-by-room combat** — doors lock once you enter a room with enemies; clear it to unlock and move on, Isaac-style (camera locked to the current room, no scrolling between rooms).
- **Enemies** — melee, ranged, and jumping types, each with their own AI.
- **Three bosses** — a segmented worm boss, a jumping ambush boss, and a minion-summoning hive queen.
- **Pickups** — hearts to heal, and stat-up items (health, damage, speed, fire rate, range) after clearing a boss room.
- **Floor progression** — descend through multiple floors, each with more rooms than the last, until a final win screen.

## Controls

| Action | Input |
|---|---|
| Move | `WASD` / Arrow keys |
| Aim & Shoot | Mouse position / Left click |
| Pause | `Esc` |

## Running the project

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
