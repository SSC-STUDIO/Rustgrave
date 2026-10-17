# Project: Rustgrave Character Attributes & Equipment System

## Architecture
- **Attributes Component** (`scripts/player/character_stats.gd`):
  Lightweight numerical model managing base attributes, equipment bonuses, and computed effective attributes:
  - `max_hp`: Base 5, modified by equipment.
  - `attack`: Base 0, adds directly to melee swing active hitbox damage (`hitbox.damage`).
  - `defense`: Base 0, subtracts from received damage in `Hurtbox`/`Health` with a strict floor of 1 damage.
  - `toxin_resist`: Base 0.0 (clamped [0.0, 0.8]), reduces toxin accumulation from `ToxinMeter.expose()`.
  - `toxin_decay`: Base 0.0, multiplies natural toxin drain rate in `ToxinMeter._process()`.
  - `speed_mult`: Base 1.0, scales player horizontal and dash speeds in `PlayerController`.
  - Harmonious with existing ember resonance (`Resonance`) and toxin bands (`cold`, `warm`, `hot`, `overflow`).
- **Equipment Component** (`scripts/data/equipment_item.gd`, `scripts/data/equipment_catalog.gd`, `scripts/player/equipment_inventory.gd`):
  - 3 Distinct slots: `weapon`, `armor`, `trinket`.
  - Equipment bag: Array of inventory items (capacity: 16).
  - Starter set: "Broken Knight" set (`broken_sword`, `broken_armor`, `broken_pendant`).
  - Set synergy: 2-piece and 3-piece set bonuses calculated and applied to total stats.
  - World pickups: `EquipmentPickup` (`Interactable` on collision layer 64 / mask 2), `SaveData.consumed` integration, HUD banner announcement.
- **Persistence & Migration** (`scripts/autoload/save_data.gd`):
  - Section `[equipment]` in `rustgrave_save.cfg`: `weapon`, `armor`, `trinket`, `bag`.
  - 100% backward compatible: Missing `[equipment]` in legacy saves safely initializes default Broken Knight starter gear without errors.
  - Full lifecycle preservation: Restored upon game load, death respawn, and cross-level scene travel.
- **UI & Controls Integration** (`scripts/ui/character_equipment_panel.gd`, `scripts/ui/pause_menu.gd`):
  - Standalone HUD / CanvasLayer UI panel (`layer = 21` or embedded in PauseMenu).
  - Toggled via `Tab` / `I` shortcut or from `PauseMenu` item `ID_EQUIPMENT := &"equipment"`.
  - Handles game pause (`get_tree().paused = true`), focus capture, and resume on close.
  - Full keyboard, mouse, and touch interaction.

## Code Layout
- `scripts/data/equipment_item.gd`: Resource definition for equipment items.
- `scripts/data/equipment_catalog.gd`: Static registry and factory for all equipment definitions.
- `scripts/player/character_stats.gd`: Attribute computation and modifier engine.
- `scripts/player/equipment_inventory.gd`: Slot manager and bag container.
- `scripts/interactables/equipment_pickup.gd`: World pickup scene and script.
- `scenes/interactables/EquipmentPickup.tscn`: Pickup scene.
- `scripts/ui/character_equipment_panel.gd`: UI script for attributes and equipment slots/bag.
- `scenes/ui/CharacterEquipmentPanel.tscn`: UI scene.
- `scripts/autoload/save_data.gd`: Save, load, and player restore integration.
- `scripts/combat/melee_combat.gd`: Melee damage integration point.
- `scripts/combat/hurtbox.gd` / `scripts/player/health.gd`: Defense reduction integration point.
- `scripts/player/toxin_meter.gd`: Toxin resistance and decay integration point.
- `scripts/player/player_controller.gd`: Movement speed modifier integration point.
- `scripts/player/player.gd`: Node composition and wiring.
- `scripts/ui/pause_menu.gd`: Submenu entry point.
- `tests/character_stats_test.gd`: Tier 1 tests.
- `tests/equipment_inventory_test.gd`: Tier 2 tests.
- `tests/stats_combat_integration_test.gd`: Tier 3 tests.
- `tests/equipment_e2e_test.gd`: Tier 4 tests.

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | Attribute Model & Calculation | Base attributes, equipment modifiers, and clamped stat getters | M1 | ORIGINAL_REQUEST §R1 |
| 2 | Melee Attack Scaling | Attack attribute directly scales melee active hitbox damage | M1 | ORIGINAL_REQUEST §R1 |
| 3 | Defense & Damage Mitigation | Defense attribute mitigates incoming damage with a 1-damage floor | M1 | ORIGINAL_REQUEST §R1 |
| 4 | Toxin Resistance & Decay | Resist reduces exposure accumulation; decay speeds up drain | M1 | ORIGINAL_REQUEST §R1 |
| 5 | Movement Speed Scaling | Speed multiplier dynamically scales player cruise and dash speeds | M1 | ORIGINAL_REQUEST §R1 |
| 6 | Equipment Resource & Catalog | EquipmentItem resource and EquipmentCatalog factory | M2 | ORIGINAL_REQUEST §R2 |
| 7 | Slot Management & Inventory | 3 Slots (Weapon, Armor, Trinket), bag storage, equip, unequip, swap | M2 | ORIGINAL_REQUEST §R2 |
| 8 | Starter Gear & Set Synergy | Broken Knight starter set with 2pc/3pc synergy bonuses | M2 | ORIGINAL_REQUEST §R2 |
| 9 | World Equipment Pickup & Drop | EquipmentPickup interactable, scrap pile / enemy drop, HUD announcement | M2 | ORIGINAL_REQUEST §R2 |
| 10 | SaveData Serialization | ConfigFile [equipment] section read/write | M3 | ORIGINAL_REQUEST §R4 |
| 11 | Legacy Save Backward Compatibility | Safe default fallback for old saves without [equipment] | M3 | ORIGINAL_REQUEST §R4 |
| 12 | Respawn & Level Transition Retention | Equipment and bag retained across death respawn and level exit | M3 | ORIGINAL_REQUEST §R4 |
| 13 | Character & Equipment UI Panel | Visual overview of stats, 3 slots, bag grid, item tooltips | M4 | ORIGINAL_REQUEST §R3 |
| 14 | Tab/I Hotkey & Pause Arbitration | Open/close with Tab or I, proper tree pause and input focus | M4 | ORIGINAL_REQUEST §R3 |
| 15 | PauseMenu Integration | Equipment entry in PauseMenu with back navigation | M4 | ORIGINAL_REQUEST §R3 |
| 16 | Multi-Input Support | Keyboard, mouse click/hover, and touch support | M4 | ORIGINAL_REQUEST §R3 |
| 17 | E2E Test Suite (Tiers 1-4) | Comprehensive 4-Tier test suite covering all features and boundaries | E2E_Track | ORIGINAL_REQUEST §Acceptance |
| 18 | Final Verification & Hardening | 100% test pass on run_tests.ps1, 0 errors, no regressions, Tier 5 hardening | M5 | ORIGINAL_REQUEST §Acceptance |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M1 | Attributes & Combat Integration | `character_stats.gd`, wiring into `melee_combat.gd`, `hurtbox.gd`/`health.gd`, `toxin_meter.gd`, `player_controller.gd` | none | DONE |
| M2 | Equipment System & Drops | `equipment_item.gd`, `equipment_catalog.gd`, `equipment_inventory.gd`, `EquipmentPickup.tscn`, starter gear, set synergy | M1 | DONE |
| M3 | Persistence & Backward Compatibility | `save_data.gd` integration, legacy save fallback, respawn & level transition retention | M2 | IN_PROGRESS |
| M4 | UI & Pause Menu Integration | `character_equipment_panel.gd`, `CharacterEquipmentPanel.tscn`, `pause_menu.gd` integration, Tab/I hotkey, input focus | M2, M3 | PLANNED |
| E2E | E2E Testing Track | Test infra setup, Tiers 1-4 test scripts, publishes `TEST_READY.md` | M1 interface contracts | DONE |
| M5 | Final Milestone: 100% Pass & Tier 5 Hardening | Pass 100% E2E tests, 0 engine errors, no regression, Phase 2 adversarial hardening | M1, M2, M3, M4, E2E | PLANNED |

## Interface Contracts
### Player ↔ CharacterStats
- `character_stats.gd`:
  - `get_attack_bonus() -> int`
  - `get_defense_reduction() -> int`
  - `get_max_hp_bonus() -> int`
  - `get_toxin_resistance() -> float` (clamped [0.0, 0.8])
  - `get_toxin_decay_bonus() -> float`
  - `get_speed_multiplier() -> float`
  - `recalculate(equipped_items: Array, set_bonuses: Dictionary) -> void`
  - `signal stats_changed()`

### Player ↔ EquipmentInventory
- `equipment_inventory.gd`:
  - `const SLOT_WEAPON := &"weapon"`
  - `const SLOT_ARMOR := &"armor"`
  - `const SLOT_TRINKET := &"trinket"`
  - `var equipped := { SLOT_WEAPON: null, SLOT_ARMOR: null, SLOT_TRINKET: null }`
  - `var bag: Array = []`
  - `func equip_item(item: EquipmentItem, slot: StringName) -> bool`
  - `func unequip_slot(slot: StringName) -> bool`
  - `func swap_item(slot: StringName, bag_index: int) -> bool`
  - `func add_to_bag(item: EquipmentItem) -> bool`
  - `func remove_from_bag(bag_index: int) -> EquipmentItem`
  - `func get_equipped(slot: StringName) -> EquipmentItem`
  - `func get_set_synergies() -> Array[Dictionary]`
  - `signal equipment_changed()`
  - `signal bag_changed()`

### SaveData ↔ Equipment
- Section `[equipment]` in ConfigFile:
  - `weapon`: String (item ID, e.g. `"broken_sword"`)
  - `armor`: String (item ID, e.g. `"broken_armor"`)
  - `trinket`: String (item ID, e.g. `"broken_pendant"`)
  - `bag`: Array[String] (list of item IDs)
- Fallback for missing section/keys:
  - Default `weapon = "broken_sword"`
  - Default `armor = "broken_armor"`
  - Default `trinket = "broken_pendant"`
  - Default `bag = []`
