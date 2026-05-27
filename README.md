# Shinobi no Satori means "Ninja's Enlightenment" in Japanese.
This mod adds ninja armour and weapons to the game.

# Features
## New Boss Arena
Adds a new big Japanese-styled arena for the quest.

## New Quest
A new quest to obtain the special ninja armour.

## New Armour with abilities
- **Headwear of Shinobi** (sns:epic_headwear): Grants night vision, and by pressing `Sneak + Right-click` on a wall, the player can pass through it.
- **Chestplate of Shinobi** (sns:epic_chestplate): Grants an attack bonus and reduces fall damage (configurable, see: Configuration).
- **Hakama of Shinobi** (sns:epic_hakama): Grants a speed boost (also configurable) and the ability to sprint across water.

## New Weapons
- **Shuriken of Fire** (sns:fire_shuriken): Can be thrown, burns enemies on hit.
- **Shuriken of Ice** (sns:ice_shuriken): Same as fire shuriken, but instead freezes enemies.
- **Shuriken of Thunder** (sns:lightning_shuriken): Stuns the primary target and arcs to up to 2 nearby enemies, dealing reduced chain damage to each.

# New Dungeon
After the player has completed the main quest, the player may access a custom dungeon.

## How to Enter and Complete the Dungeon

1. **Type `/dungeon` in chat** to enter the Shinobi Dungeon. The first time the player uses this command, a dungeon will be generated 100 blocks below the player's current position. The player will be teleported to the entrance.
2. **Survive and progress through the dungeon** by avoiding or overcoming traps and hazards. Use your ninja skills and equipment to your advantage!
3. **Reach the reward chest** at the end. Each player can claim the reward only once.
4. **Leave the dungeon**: The player's progress and rewards are saved. If the player leaves the dungeon area or disconnects, the player's special privileges (fly/noclip) will be restored automatically.

### Tips for Players
- Watch your step! Many floors and walls are trapped.
- Some obstacles (like sand walls) can only be bypassed with the Headwear of Shinobi.
- The player cannot fly or noclip inside the dungeon — face the challenge head-on.

## Dungeon Traps & Mechanics

The dungeon is filled with unique traps and mechanics:

- **sns:spike_floor** — Spike Floor: Deals damage to players standing on it (bypasses armour).
- **sns:collapse_floor** — Crumbling Floor: Collapses 1.5 seconds after a player steps near it.
- **sns:dart_wall** — Dart Trap Wall: Periodically shoots darts in the direction it faces (set with facedir).
- **sns:sand_trigger** — Sand Ceiling Trigger: Invisible node on the ceiling. When a player approaches from below, a sand wall falls, blocking the corridor (can only be passed with the Headwear of Shinobi).
- **sns:dungeon_zone** — Dungeon Zone Marker: Invisible node marking the dungeon area. While inside, players lose fly and noclip privileges (restored on exit).
- **sns:dungeon_chest** — Dungeon Reward Chest: One-time reward chest. Each player can claim elite armour, shurikens, and the JONIN rank once.

### Dungeon Mechanics

- **/dungeon** — Teleports the player into the dungeon.
- **Progress saving** — The player's dungeon progress and claimed rewards are saved per player.
- **Privilege restoration** — Fly/noclip privileges are automatically restored when the player leaves the dungeon or disconnects.
- **Reward chest** — Grants a full set of elite armour, 50 of each shuriken type, and the JONIN rank (displayed in the player's nametag).

#### Example trap nodes in a dungeon schematic:
```
sns:spike_floor      # spike floor
sns:collapse_floor   # crumbling floor
sns:dart_wall        # dart trap wall (face toward corridor)
sns:sand_trigger     # sand ceiling trigger
sns:dungeon_zone     # zone markers (hidden in walls/floor/ceiling)
sns:dungeon_chest    # reward chest
```

All trap parameters (damage, intervals, rewards) can be configured via settingtypes.txt or minetest.conf.

# Configuration

### Armour settings

- **Hide armour from creative inventory**: removes the armour set from creative inventory. Default: true
- **Armour heal chance per piece**: Heal chance for each armour piece (percentage out of 100). With all 3 pieces equipped the total is 3× this value. Default: 18
- **Armour colour**: Two options: `cyan` or `orange`. Default: cyan, looks more ancient.
- **Chestplate damage multiplier**: multiplies damage bonus. Default: 1.8
- **Chestplate fall damage reduction**: fraction of fall damage absorbed (0.0 = none, 1.0 = immune). Default: 0.5
- **Hakama speed boost**: speed multiplier added to base speed. Default: 0.6
- **Wall-walk speed**: movement speed while passing through walls with the headwear. Default: 4.0
- **Night vision brightness**: brightness when headwear is equipped (0.0 = dark, 1.0 = full daylight). Default: 0.6

### Shuriken settings

^ means the setting applies to all shuriken types

- **Shuriken speed**: speed of the shuriken when thrown. Default: 22 blocks/second^
- **Shuriken range**: maximum range before the shuriken turns back/falls (blocks). Default: 18^
- **Shuriken damage**: damage the fire/ice shuriken deals upon striking. Default: 15^
- **Freeze duration**: duration of freeze effect (in seconds). Default: 5
- **Burn duration**: duration of burn effect (in seconds). Default: 4
- **Hit radius**: hit radius around the shuriken (blocks). Default: 1.8^
- **Throw cooldown**: cooldown between throws (in seconds). Default: 1^
- **Shuriken flight mode**: behaviour when the shuriken hits a wall or reaches its maximum range.
`drop` — (default) sticks in a wall for ~2 seconds, then drops as an item, or falls to the ground if shuriken range is reached mid-air.
`return` — boomerang: curves back and returns to the thrower's inventory. Default: drop^

### Thunder Shuriken settings

- **Lightning shuriken damage**: damage dealt to the primary target. Default: 8
- **Lightning stun duration**: how long (seconds) the primary target is stunned. Default: 0.8
- **Lightning chain target count**: maximum number of additional targets the chain arc jumps to. Default: 2
- **Lightning chain range**: search radius (blocks) around the primary hit for chain targets. Default: 6
- **Lightning chain damage multiplier**: fraction of primary damage dealt to each chained target. Default: 0.5

### Dungeon trap settings
- **Dart trap fire interval**: How often (seconds) a dart wall fires a dart. Default: 3
- **Dart speed**: Speed of the dart projectile (blocks/second). Default: 20
- **Dart damage**: Damage dealt by a dart on hit. Default: 4

### Elite Armour stat settings
- **Elite armour heal**: Heal chance per tick for the elite armour (higher = faster natural regen; base is 18). Default: 30
- **Elite hakama speed boost**: Speed multiplier bonus from the elite hakama (stacks with normal physics; base is 0.6). Default: 0.9
- **Elite full-set max HP**: Maximum HP when wearing the full elite armour set (default player max is 20). Default: 30

### Armour set bonus settings

- **Bonus granted when all three armour pieces are equipped at the same time.**
Options:
- `nameonly`   — the player's nametag is hidden from other players,
- `invisible`  — the player's body becomes invisible to other players,
- `both`       — both name and body are hidden,
- `scout`      — activates a spy ghost: the player's decoy body stays in place while the player's shadow goes through the world; press Sneak/Shift+Jump to activate and return.

# Chat Commands

All commands require the `server` privilege.

| Command | Description |
|---|---|
| `/shintp` | Teleport to the quest chest, or to the arena corner if no chest is found. |
| `/rquest [player_name]` | Reset quest progress for yourself or another player. |
| `/shindebug` | Print full quest state and boss pool to chat. |
| `/shinspawn` | Force-respawn the boss immediately (only works while in `fighting_boss` stage). |

# Credits

- Mod is made from scratch.
- Mod developer: Scottii
- Inspired by: [Shinobi no Satori - a mod for The Legend of Zelda: Tears of the Kingdom by Catzy](https://gamebanana.com/mods/641335)

# Release log

### Initial release v1.1.0
