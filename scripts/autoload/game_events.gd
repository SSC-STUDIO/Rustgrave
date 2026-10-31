extends Node
## Autoload signal bus. Keep gameplay modules decoupled.
## Do not give this script a class_name — the autoload name is GameEvents.

signal hit(attacker: Node, target: Node, amount: int)
signal parried(projectile: Node, by_actor: Node)
signal toxin_changed(current: float, maximum: float)
signal core_acquired(core: Resource)
signal core_inserted(core: Resource, socket_index: int)
signal sockets_changed
signal ability_unlocked(ability_id: StringName)
signal interact_prompt(text: String)
signal player_health_changed(current: int, maximum: int)
signal announcement(text: String)
signal player_died
signal player_respawned
signal game_saved
signal rusty_gate_melted
signal swing_started(combo_index: int)
signal dash_performed
signal jumped(is_extra: bool)
signal resonance_changed(active: bool)
signal ending_chosen(kind: StringName)
signal boss_appeared(boss_name: String, current_hp: int, max_hp: int)
signal boss_hp_changed(current_hp: int, max_hp: int)
signal boss_defeated
## Shared staging signals. Emitters: ChapterLevel/Level01 (chapter_started), boss scripts
## (boss_intro_started, boss_phase_changed). Listeners: Music, HUD hints, Director beats.
signal chapter_started(level_id: String)
signal boss_intro_started(boss_name: String)
signal boss_phase_changed(boss_name: String, phase: int)
## ICEY-style multi-room & real-time dynamic narrative signals.
signal room_entered(stage_id: String, room_id: String)
signal battle_wave_started(wave_index: int, total_waves: int)
signal battle_room_cleared(room_id: String)
signal voice_triggered(clip_id: String, force_interrupt: bool)
signal disobedience_triggered(branch_id: String, step: int)
signal truth_fragment_acquired(fragment_id: String)
signal stage_node_unlocked(node_id: String)
