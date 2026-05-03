# Shinobi no Satori means Ninja in Japanese
This mod adds a new quest and ninja armour.

# Features
## New Boss Arena:
Adds a new big Japanese-styled arena for the quest.

## New Quest
A new quest to obtain the special ninja armour.

## New Armour with abilities
- **Headwear of Shinobi** (shinobi_no_satori:epic_headwear): Grants night vision and by pressing Sneak/Shift+Rightclick on a wall, you will clip through it.
- **Chestplate of Shinobi** (shinobi_no_satori:epic_chestplate): Grants an attack bonus (can be configured in settings, see: Configuration).
- **Hakama of Shinobi** (shinobi_no_satori:epic_hakama): Grants a speed boost (can be configured) and the ability to sprint across water.

## New Weapons
- **Fire Shuriken** (shinobi_no_satori:fire_shuriken): Can be thrown, burns enemies on hit.
- **Ice Shuriken** (shinobi_no_satori:ice_shuriken): Same as fire shuriken, but instead freezes enemies.

# Configuration

### Armour settings

- **Hide armour from creative inventory**: removes armour set from creative inventory. Default: true
- **Armour heal chance per piece**: Heal chance for each armour piece (percentage out of 100). With all 3 pieces equipped the total is 3× this value. Default: 18
- **Armour colour**: Two options: `cyan` or `orange`. Default: cyan, looks more ancient.
- **Chestplate damage multiplier**: multiplies damage bonus. Default: 1,8
- **Hakama speed boost**: multiplies hakama speed boost. Default: 1.6
- **Night vision brightness**: multiplies night vision brightness when headwear is equipped. Default: 1.6

### Shuriken settings

^ means the setting applies to both shuriken types

- **Shuriken speed**: Speed of the shuriken when thrown. Default: 22 blocks/second^
- **Shuriken range**: Maximum range before the shuriken turns back/falls (blocks). Default: 18^
- **Shuriken damage**: Damage the shuriken deals upon striking. Default: 15^
- **Freeze duration**: Duration of freeze effect (in seconds). Default: 5
- **Burn duration**: Duration of burn effect (in seconds). Default: 4
- **Hit radius**: Hit radius around the shuriken (blocks). Default: 1.8
- **Throw cooldown**: Cooldown between throws (in seconds). Default: 1
- **Shuriken flight mode**: Behaviour when the shuriken hits a wall or reaches its maximum range.
`drop` — (default) sticks in a wall for ~2 seconds then drops as an item, or falls to the ground if shuriken range is reached mid-air.
`return` — boomerang: curves back and returns to the thrower's inventory.

### Armour set bonus settings

- **Bonus granted when all three armour pieces are equipped at the same time.**
Options:
`nameonly`   — the player's nametag is hidden from other players
`invisible`  — the player's body becomes invisible to other players
`both`       — both name and body are hidden
`scout`      — activates a spy ghost: your decoy body stays in place while your shadow goes through the world; press Sneak/Shift+Jump to activate and return.


