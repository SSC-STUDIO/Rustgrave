# Project: Rustgrave Character Origin Selection & Starting Loadout System

## Architecture
- **Origin Model & Catalog** (`scripts/data/character_origin.gd`, `scripts/data/origin_catalog.gd`):
  - 3 Distinct character origins:
    - **Ember Vanguard (余烬重骑)**: `max_hp +1`, `defense +1`. Focus: Sturdy defense and attrition.
    - **Scrap Scavenger (废料剑客)**: `attack +1`, `speed_mult +10%` (+0.10). Focus: High mobility slash and agile evasions.
    - **Rust Automaton (锈械学者)**: `toxin_resist +20%` (+0.20), `toxin_decay +50%` (+0.50). Focus: Corrosive fluid immunity and toxic mire combat.
  - Data-driven definition: ID, title, lore description, combat focus, stat modifiers, preset weapon & armor IDs, allowed trinket pool.
  - Static preview helper: `OriginCatalog.calculate_preview_stats(origin_id, weapon_id, armor_id, trinket_id) -> Dictionary` ensuring mathematical parity between UI preview and runtime `CharacterStats`.

- **Equipment & Starting Loadout System** (`scripts/data/equipment_catalog.gd`, `scripts/player/equipment_inventory.gd`):
  - Trinket pool:
    - `broken_pendant` ("破损挂坠", toxin_resist +0.05, Broken Knight set).
    - `bone_amulet` / `bone_charm` ("白骨护身符", max_hp +1, speed_mult +0.05). Symmetrically aliased in `EquipmentCatalog.for_id()` for 100% backward compatibility with existing tests.
    - `toxic_filter_talisman` / `toxic_ward` ("滤毒符印", toxin_resist +0.15, toxin_decay +0.50). Symmetrically aliased in `EquipmentCatalog.for_id()`.
  - Origin starting equipment:
    - Ember Vanguard: `broken_sword` (atk +1), `broken_armor` (def +1, max_hp +1).
    - Scrap Scavenger: `scavenger_blade` (atk +1), `scavenger_rags` (def +1).
    - Rust Automaton: `scholar_probe` (atk +1), `scholar_cowl` (def +1, toxin_resist +0.05).

- **Character Stats Integration** (`scripts/player/character_stats.gd`):
  - Bare default stats remain unadjusted (HP 5, ATK 0, DEF 0, RES 0.0, DEC 0.0, SPD 1.0) when origin is `""` to preserve existing lifecycle tests.
  - `apply_origin(origin_id: StringName) -> void` dynamically adjusts base stats and emits `stats_changed`.
  - Strict clamping: Toxin resist `[0.0, 0.8]`, speed mult `[0.1, 3.0]`, damage floor `>= 1`.

- **Title Screen to Gameplay Flow** (`scripts/ui/title_screen.gd`, `scenes/ui/CharacterSelectScreen.tscn`, `scripts/ui/character_select_screen.gd`):
  - `CharacterSelectScreen` modal built with `Modal.build()` on `CanvasLayer` at `layer = 8`.
  - TitleScreen menu rail keeps exactly 5 items (strictly adhering to `tests/title_screen_test.gd`).
  - Interception:
    - "点燃余烬 (New Game)": If save exists, prompt overwrite confirmation. Upon overwrite, open `CharacterSelectScreen`. If no save exists, open `CharacterSelectScreen` directly.
    - Cancellation: Esc or "取消" closes `CharacterSelectScreen` and restores `TitleScreen._menu.active = true` safely.
    - Embarkation: "点燃启程" calls `SaveData.init_new_game(origin_id, loadout)` and transitions via `Director.fade_to(GameContext.WORLD_PATH, FADE_OUT)` to `Level01_Static`.

- **Persistence & Player Lifecycle** (`scripts/autoload/save_data.gd`, `scripts/player/player.gd`):
  - `SaveData.init_new_game(origin_id, loadout)` initializes memory state and saves to disk immediately, so `has_save()` returns true.
  - ConfigFile `[player]` section persists `origin = "<id>"`.
  - 100% backward compatible: Missing `origin` key in legacy saves safely defaults without crashing.
  - In `SaveData.apply_player(player)`: Correct restoration order:
    1. Apply origin to `player.stats`
    2. Apply equipment to `player.equipment`
    3. Apply health and toxin with clamping to effective max values
    4. Restore facing and cores

- **In-Game UI Polish & Color Coding** (`scripts/ui/character_equipment_panel.gd`):
  - Top-left header displays selected origin badge: `身份 · 余烬重骑`.
  - Chromatic color hierarchy for attributes:
    - Attack: Warm yellow (`#FFC14A`)
    - Defense: Metallic iron grey (`#BAC4CC`)
    - Toxin Resist & Decay: Teal/cyan (`#5CE1B6`)
    - Speed Multiplier: Agility blue (`#5CB3FF`)
    - Max HP: Vitality green (`#76E074` or warm amber)
  - Tooltips formatted with detailed calculation formulas and mitigation explanations.
  - Pixel-perfect layout across resolutions, gamepad/keyboard/mouse support.

## Code Layout
- `scripts/data/character_origin.gd`: Origin resource definition.
- `scripts/data/origin_catalog.gd`: Origin registry, metadata, and static preview calculations.
- `scripts/data/equipment_catalog.gd`: Catalog registry with aliasing (`bone_amulet`, `toxic_filter_talisman`) and origin starter gear.
- `scripts/player/character_stats.gd`: Origin modifier integration and dynamic calculation.
- `scripts/autoload/save_data.gd`: `init_new_game()`, `origin` serialization, and `apply_player()` sequencing.
- `scripts/ui/character_select_screen.gd`: Modal UI for origin selection, trinket picking, 6-stat live preview, and embarkation.
- `scenes/ui/CharacterSelectScreen.tscn`: Modal scene for character selection.
- `scripts/ui/title_screen.gd`: New Game flow interception, modal activation, Esc safety.
- `scripts/ui/character_equipment_panel.gd`: Origin title badge, chromatic stat color hierarchy, tooltips.
- `tests/character_origin_test.gd`: Origin data, catalog, and stat calculation unit tests.
- `tests/character_select_flow_test.gd`: Title flow, modal interaction, Esc cancellation, and embarkation tests.
- `tests/origin_persistence_lifecycle_test.gd`: SaveData serialization, legacy compatibility, and player lifecycle tests.

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | Origin Resource & Catalog | 3 Origins (Ember Vanguard, Scrap Scavenger, Rust Automaton) with stats, lore, and loadouts | M1 | ORIGINAL_REQUEST §R1 |
| 2 | Starter Loadout & Trinket Aliasing | Origin gear definitions and dual-aliasing for `bone_amulet` and `toxic_filter_talisman` | M1 | ORIGINAL_REQUEST §R2 |
| 3 | Dynamic 6-Stat Preview Model | Static calculation helper producing preview stats matching CharacterStats | M1 | ORIGINAL_REQUEST §R2 |
| 4 | CharacterStats Origin Integration | `apply_origin()` on CharacterStats without regressing unassigned bare stats | M1 | ORIGINAL_REQUEST §R1 |
| 5 | CharacterSelectScreen Modal | Origin tabs, loadout display, trinket picker, dynamic 6-stat preview | M2 | ORIGINAL_REQUEST §R2, §R3 |
| 6 | TitleScreen New Game Flow Interception | Overwrite confirmation if save exists -> CharacterSelectScreen modal | M2 | ORIGINAL_REQUEST §R3 |
| 7 | Esc & Cancel Safe Return | Cleanly dismiss CharacterSelectScreen and reactivate TitleScreen menu | M2 | ORIGINAL_REQUEST §R3 |
| 8 | Embarkation & Transition | "点燃启程" calls init_new_game and transitions to Level01_Static via Director | M2 | ORIGINAL_REQUEST §R3 |
| 9 | SaveData Origin Persistence | ConfigFile [player] origin serialization and backward-compatible fallback | M3 | ORIGINAL_REQUEST §R3, §R4 |
| 10 | SaveData init_new_game() | Atomic creation of fresh save with origin and loadout written to disk | M3 | ORIGINAL_REQUEST §R3 |
| 11 | Player Lifecycle State Restoration | `apply_player()` sequencing: origin -> equipment -> health & toxin clamping | M3 | ORIGINAL_REQUEST §R3 |
| 12 | In-Game Origin Badge Header | Top-left header displays `身份 · <Origin Title>` | M4 | ORIGINAL_REQUEST §R4 |
| 13 | Chromatic Stat Color Grading | Distinct color hierarchy: yellow attack, grey defense, teal toxin, blue speed | M4 | ORIGINAL_REQUEST §R4 |
| 14 | In-Game Stat Tooltips & Layout | Detailed formula tooltips, pixel alignment across resolutions and input modes | M4 | ORIGINAL_REQUEST §R4 |
| 15 | E2E Test Suite (Tiers 1-4) | Comprehensive test coverage for origins, loadouts, title flow, and lifecycle | E2E_Track | ORIGINAL_REQUEST §Acceptance |
| 16 | Final Verification & Hardening | 100% full-suite pass, 0 engine errors, zero regressions, Tier 5 adversarial hardening | M5 | ORIGINAL_REQUEST §Acceptance |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M1 | Origin Models, Catalog & Stat Calculation | `character_origin.gd`, `origin_catalog.gd`, `equipment_catalog.gd` aliasing & loadout gear, `character_stats.gd` origin integration | none | DONE |
| M2 | CharacterSelectScreen & Title Flow | `character_select_screen.gd`, `CharacterSelectScreen.tscn`, `title_screen.gd` interception, Esc cancellation, embarkation flow | M1 | DONE |
| M3 | SaveData & Player Lifecycle Integration | `save_data.gd` `init_new_game()`, `origin` serialization, `apply_player()` restoration, level transition retention | M1, M2 | DONE |
| M4 | In-Game UI Polish & Visuals | `character_equipment_panel.gd` origin badge header, chromatic color hierarchy, stat tooltips | M1, M3 | DONE |
| E2E | E2E Testing Track | Design & implement comprehensive automated tests across Tiers 1-4 | M1, M2, M3, M4 | DONE |
| M5 | Final Milestone: 100% Pass & Hardening | Full test runner execution (`run_tests.ps1`), 0 engine errors, Phase 2 adversarial coverage hardening | M1, M2, M3, M4, E2E | IN_PROGRESS |

## Interface Contracts
### OriginCatalog ↔ CharacterStats
- `character_origin.gd`:
  - `id: StringName` (`&"ember_vanguard"`, `&"scrap_scavenger"`, `&"rust_automaton"`)
  - `title: String` ("余烬重骑", "废料剑客", "锈械学者")
  - `lore: String`
  - `combat_focus: String`
  - `stat_modifiers: Dictionary` (`{"max_hp": int, "attack": int, "defense": int, "toxin_resist": float, "toxin_decay": float, "speed_mult": float}`)
  - `default_weapon: StringName`
  - `default_armor: StringName`
  - `allowed_trinkets: Array[StringName]`
- `origin_catalog.gd`:
  - `static func get_all_origins() -> Array[CharacterOrigin]`
  - `static func get_origin(id: StringName) -> CharacterOrigin`
  - `static func calculate_preview_stats(origin_id: StringName, weapon_id: StringName, armor_id: StringName, trinket_id: StringName) -> Dictionary`
- `character_stats.gd`:
  - `apply_origin(origin_id: StringName) -> void`
  - `get_origin_id() -> StringName`

### TitleScreen ↔ CharacterSelectScreen
- `CharacterSelectScreen`:
  - `signal embark_requested(origin_id: StringName, loadout: Dictionary)`
  - `signal cancelled()`
  - `open() -> void`
  - `close() -> void`
- `TitleScreen`:
  - Intercept `ID_NEW` -> open confirmation if save exists -> open `CharacterSelectScreen`
  - On `cancelled` -> reactivate `_menu.active = true`
  - On `embark_requested` -> call `SaveData.init_new_game(origin_id, loadout)` -> `Director.fade_to(GameContext.WORLD_PATH, FADE_OUT)`

### SaveData ↔ Player & Systems
- `save_data.gd`:
  - `func init_new_game(origin_id: StringName, loadout: Dictionary) -> void`
  - `func get_current_origin() -> StringName`
  - ConfigFile `[player]` key `origin: String` (defaults safely to `""` for legacy saves)
  - `apply_player(player: Node) -> void`:
    Order: `origin` -> `equipment` -> `health & toxin` -> `facing & cores`
