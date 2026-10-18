# E2E Test Infra: Rustgrave Character Origin Selection & Starting Loadout System

## Test Philosophy
- Opaque-box, requirement-driven. Derived strictly from `ORIGINAL_REQUEST.md` (2026-10-18T00:39:46Z).
- Methodology: Category-Partition + Boundary Value Analysis (BVA) + Pairwise Combinatorial Testing + Real-World Workload Testing.
- Framework: Native Godot 4.7 test runner (`tests/run_tests.gd` + `tests/test_case.gd`) executed via `tools/run_tests.ps1`.
- Mandatory Pass Criterion: 100% test pass with 0 engine errors and 0 warnings/crashes across the entire test suite.

## Feature Inventory
| # | Feature | Source (requirement) | Tier 1 | Tier 2 | Tier 3 |
|---|---------|---------------------|:------:|:------:|:------:|
| 1 | Character Origin Selection (3 origins) | ORIGINAL_REQUEST §R1 | 5 | 5 | ✓ |
| 2 | Origin Stat Modifiers & Clamping | ORIGINAL_REQUEST §R1 | 5 | 5 | ✓ |
| 3 | Starting Loadout Presets & Trinket Pool | ORIGINAL_REQUEST §R2 | 5 | 5 | ✓ |
| 4 | Dynamic 6-Stat Preview Model | ORIGINAL_REQUEST §R2 | 5 | 5 | ✓ |
| 5 | CharacterSelectScreen Modal UI | ORIGINAL_REQUEST §R2, §R3 | 5 | 5 | ✓ |
| 6 | Title Screen Flow Interception & Confirmation | ORIGINAL_REQUEST §R3 | 5 | 5 | ✓ |
| 7 | Esc Cancellation & State Safety | ORIGINAL_REQUEST §R3 | 5 | 5 | ✓ |
| 8 | Embarkation & Level01 Scene Transition | ORIGINAL_REQUEST §R3 | 5 | 5 | ✓ |
| 9 | SaveData Origin Persistence & Backward Compatibility | ORIGINAL_REQUEST §R3, §R4 | 5 | 5 | ✓ |
| 10 | Player Node Lifecycle Initialization | ORIGINAL_REQUEST §R3 | 5 | 5 | ✓ |
| 11 | In-Game Origin Header Badge | ORIGINAL_REQUEST §R4 | 5 | 5 | ✓ |
| 12 | Chromatic Stat Color Grading & Tooltips | ORIGINAL_REQUEST §R4 | 5 | 5 | ✓ |

## Test Architecture
- **Runner**: `powershell -ExecutionPolicy Bypass -File .\tools\run_tests.ps1 -TimeoutSeconds 300`
- **Driver**: `tests/run_tests.gd` headless execution of all `tests/*_test.gd`
- **Test Case Base**: `tests/test_case.gd` (`ok`, `eq`, `almost`, `flush`, `spawn_player`, `build_floor`)
- **Suite Files**:
  - `tests/character_origin_test.gd` (Tier 1 & Tier 2: Origins, catalog, stat calculations, clamping boundaries, trinket pool aliasing)
  - `tests/character_select_flow_test.gd` (Tier 2 & Tier 3: Title screen flow, overwrite confirmation, Esc return, preview live sync, embarkation signals)
  - `tests/origin_persistence_lifecycle_test.gd` (Tier 3 & Tier 4: SaveData init_new_game, ConfigFile serialization, legacy fallback, player node spawning, respawn retention)
  - `tests/origin_ui_polish_test.gd` (Tier 1 & Tier 4: CharacterEquipmentPanel origin header, color hierarchy, formula tooltips, multi-input navigation)

## Real-World Application Scenarios (Tier 4)
| # | Scenario | Features Exercised | Complexity |
|---|----------|--------------------|------------|
| 1 | Complete Ember Vanguard Playthrough Start (New Game -> Overwrite -> Select -> Embark -> Level01 Spawn -> In-Game Stats Check) | F1, F3, F4, F6, F8, F9, F10, F11 | High |
| 2 | Scrap Scavenger Mobility & Attack Run (Origin -> Bone Amulet -> Verify Speed 1.15 & Atk 2 -> Combat Melee Damage) | F1, F2, F3, F4, F10, F12 | High |
| 3 | Rust Automaton Toxin Specialization (Origin -> Toxic Ward -> Toxin Exposure in Level01 -> High Decay & Resistance) | F1, F2, F3, F4, F10, F12 | High |
| 4 | Safe Cancellation and Retrying Title Flow (New Game -> Select Screen -> Esc -> Continue Game or Quit) | F5, F6, F7 | Medium |
| 5 | Legacy Save Backward Compatibility Upgrade (Pre-existing save without origin field -> loads cleanly, defaults safely, zero errors) | F9, F10 | Medium |

## Coverage Thresholds
- Tier 1: ≥5 test cases per feature
- Tier 2: ≥5 boundary and corner cases per feature
- Tier 3: Pairwise combinations across origins, loadouts, and gameplay systems
- Tier 4: ≥5 realistic application scenarios
- Zero regressions on all existing 85+ test suites
