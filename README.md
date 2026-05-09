# Shinobi no Satori means "Ninja's Enlightenment" in Japanese.
This mod adds ninja armour and weapons to the game.

# Features
## New Boss Arena
Adds a new big Japanese-styled arena for the quest.

## New Quest
A new quest to obtain the special ninja armour.

## New Armour with abilities
- **Headwear of Shinobi** (shinobi_no_satori:epic_headwear): Grants night vision, and by pressing `Sneak/Shift + Right-click` on a wall, you can pass through it.
- **Chestplate of Shinobi** (shinobi_no_satori:epic_chestplate): Grants an attack bonus (configurable, see: Configuration).
- **Hakama of Shinobi** (shinobi_no_satori:epic_hakama): Grants a speed boost (also configurable) and the ability to sprint across water.

## New Weapons
- **Shuriken of Fire** (shinobi_no_satori:fire_shuriken): Can be thrown, burns enemies on hit.
- **Shuriken of Ice** (shinobi_no_satori:ice_shuriken): Same as fire shuriken, but instead freezes enemies.

# Configuration

### Armour settings

- **Hide armour from creative inventory**: removes the armour set from creative inventory. Default: true
- **Armour heal chance per piece**: Heal chance for each armour piece (percentage out of 100). With all 3 pieces equipped the total is 3× this value. Default: 18
- **Armour colour**: Two options: `cyan` or `orange`. Default: cyan, looks more ancient.
- **Chestplate damage multiplier**: multiplies damage bonus. Default: 1.8
- **Hakama speed boost**: speed multiplier added to base speed. Default: 0.6
- **Wall-walk speed**: movement speed while passing through walls with the headwear. Default: 4.0
- **Night vision brightness**: brightness when headwear is equipped (0.0 = dark, 1.0 = full daylight). Default: 0.6

### Shuriken settings

^ means the setting applies to both shuriken types

- **Shuriken speed**: speed of the shuriken when thrown. Default: 22 blocks/second^
- **Shuriken range**: maximum range before the shuriken turns back/falls (blocks). Default: 18^
- **Shuriken damage**: damage the shuriken deals upon striking. Default: 15^
- **Freeze duration**: duration of freeze effect (in seconds). Default: 5
- **Burn duration**: duration of burn effect (in seconds). Default: 4
- **Hit radius**: hit radius around the shuriken (blocks). Default: 1.8^
- **Throw cooldown**: cooldown between throws (in seconds). Default: 1^
- **Shuriken flight mode**: behaviour when the shuriken hits a wall or reaches its maximum range.
`drop` — (default) sticks in a wall for ~2 seconds, then drops as an item, or falls to the ground if shuriken range is reached mid-air.
`return` — boomerang: curves back and returns to the thrower's inventory. Default: drop^

### Armour set bonus settings

- **Bonus granted when all three armour pieces are equipped at the same time.**
Options:
- `nameonly`   — the player's nametag is hidden from other players,
- `invisible`  — the player's body becomes invisible to other players,
- `both`       — both name and body are hidden,
- `scout`      — activates a spy ghost: your decoy body stays in place while your shadow goes through the world; press Sneak/Shift+Jump to activate and return.

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