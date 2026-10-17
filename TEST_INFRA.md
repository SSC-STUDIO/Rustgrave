# E2E Test Infra: Rustgrave Character Attributes & Equipment System

## Test Philosophy
- Opaque-box, requirement-driven. Derived strictly from `ORIGINAL_REQUEST.md` and user-facing game behaviors.
- Methodology: Category-Partition + Boundary Value Analysis (BVA) + Pairwise Combinatorial Testing + Real-World Workload Testing.
- Framework: Native Godot 4.7 test runner (`tests/run_tests.gd` + `tests/test_case.gd`) executed via `tools/run_tests.ps1`.
- Mandatory Pass Criterion: 100% test pass with 0 engine errors and 0 warnings/crashes across the entire test suite.

## Feature Inventory
| # | Feature | Source (requirement) | Tier 1 | Tier 2 | Tier 3 |
|---|---------|---------------------|:------:|:------:|:------:|
| 1 | Attribute Model & Calculation | ORIGINAL_REQUEST §R1 | 5 | 5 | ✓ |
| 2 | Melee Attack Scaling | ORIGINAL_REQUEST §R1 | 5 | 5 | ✓ |
| 3 | Defense & Damage Mitigation | ORIGINAL_REQUEST §R1 | 5 | 5 | ✓ |
| 4 | Toxin Resistance & Decay | ORIGINAL_REQUEST §R1 | 5 | 5 | ✓ |
| 5 | Movement Speed Scaling | ORIGINAL_REQUEST §R1 | 5 | 5 | ✓ |
| 6 | Equipment Resource & Catalog | ORIGINAL_REQUEST §R2 | 5 | 5 | ✓ |
| 7 | Slot Management & Inventory | ORIGINAL_REQUEST §R2 | 5 | 5 | ✓ |
| 8 | Starter Gear & Set Synergy | ORIGINAL_REQUEST §R2 | 5 | 5 | ✓ |
| 9 | World Equipment Pickup & Drop | ORIGINAL_REQUEST §R2 | 5 | 5 | ✓ |
| 10 | SaveData Serialization | ORIGINAL_REQUEST §R4 | 5 | 5 | ✓ |
| 11 | Legacy Save Backward Compatibility | ORIGINAL_REQUEST §R4 | 5 | 5 | ✓ |
| 12 | Respawn & Level Transition Retention | ORIGINAL_REQUEST §R4 | 5 | 5 | ✓ |
| 13 | Character & Equipment UI Panel | ORIGINAL_REQUEST §R3 | 5 | 5 | ✓ |
| 14 | Tab/I Hotkey & Pause Arbitration | ORIGINAL_REQUEST §R3 | 5 | 5 | ✓ |
| 15 | PauseMenu Integration | ORIGINAL_REQUEST §R3 | 5 | 5 | ✓ |
| 16 | Multi-Input Support | ORIGINAL_REQUEST §R3 | 5 | 5 | ✓ |

## Test Architecture
- **Runner**: `powershell -ExecutionPolicy Bypass -File .\tools\run_tests.ps1 -TimeoutSeconds 300`
- **Driver**: `tests/run_tests.gd` headless execution of all `tests/*_test.gd`
- **Test Case Base**: `tests/test_case.gd` (`ok`, `eq`, `almost`, `flush`, `spawn_player`, `build_floor`)
- **Suite Files**:
  - `tests/character_stats_test.gd` (Tier 1: Formula, defaults, boundary clamps, aggregation)
  - `tests/equipment_inventory_test.gd` (Tier 2: Slot restrictions, swaps, bag limits, invalid entries)
  - `tests/stats_combat_integration_test.gd` (Tier 3: In-engine combat coupling, hitbox damage, hurtbox defense floor, toxin meter, movement speed)
  - `tests/equipment_e2e_test.gd` (Tier 4: Full save/load cycle, legacy save upgrade, death respawn, UI toggle & pause arbitration, pickup drop lifecycle)

## Real-World Application Scenarios (Tier 4)
| # | Scenario | Features Exercised | Complexity |
|---|----------|--------------------|------------|
| 1 | Full Save & Load Roundtrip | F6, F7, F8, F10, F12 | High |
| 2 | Legacy Save Backward Compatibility Upgrade | F1, F6, F7, F8, F11 | Medium |
| 3 | Death Respawn & Checkpoint Recovery | F1, F7, F8, F10, F12 | High |
| 4 | UI Toggle, Hotkeys (Tab/I) & Pause State Arbitration | F13, F14, F15, F16 | High |
| 5 | World Pickup, Consumption & Banner Announcement | F6, F7, F9 | Medium |
| 6 | Full Combat Gameplay Loop with Gear & Toxin | F1, F2, F3, F4, F5, F8 | High |

## Coverage Thresholds
- Tier 1: ≥5 test cases per feature
- Tier 2: ≥5 boundary and corner cases per feature
- Tier 3: Pairwise combinations across attributes, combat, equipment, and environment
- Tier 4: ≥6 realistic application scenarios
- Zero regressions on existing 85 test suites (`inventory_test`, `combat_rules_test`, `health_test`, `save_test`, etc.)
