extends Node
## Windowed diagnostic probe for the 3D title bring-up: builds the real TitleScreen,
## skips the intro and prints what the pixel stage / 3D world actually contain and
## whether the render target is drawing. Not an acceptance gate — a debug tool.
##
##   godot --windowed --path . res://scenes/tools/Title3DProbe.tscn
##
## Prints one block per frame after `--frames=N` (default 30) and saves a PNG next
## to the project (res://screenshots/probe/title3d_probe.png).

const TITLE := preload("res://scenes/ui/TitleScreen.tscn")

var _frames := 30
var _title: TitleScreen
var _count := 0
var _out := "res://screenshots/probe"


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Title3DProbe needs a render target")
		get_tree().quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--frames="):
			_frames = maxi(3, int(arg.trim_prefix("--frames=")))
		elif arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	var win := get_tree().root
	win.mode = Window.MODE_WINDOWED
	win.size = Vector2i(1280, 720)
	win.position = Vector2i(-12000, -12000)
	_title = TITLE.instantiate() as TitleScreen
	add_child(_title)
	await get_tree().process_frame
	_title._skip_intro()
	for i in _frames:
		await get_tree().process_frame
	await _dump()
	await RenderingServer.frame_post_draw
	var image := win.get_texture().get_image()
	image.save_png(_out + "/title3d_probe.png")
	print("PROBE_SAVED ", _out, "/title3d_probe.png")
	get_tree().quit(0)


func _dump() -> void:
	var stage = _title.get("_stage")
	var world: TitleWorld3D = _title.world()
	print("PROBE stage=", stage, " world=", world)
	if stage != null:
		var vp: SubViewport = stage.viewport
		print("PROBE viewport_size=", vp.size, " update_mode=", vp.render_target_update_mode,
				" own_world=", vp.own_world_3d, " world3d=", vp.world_3d,
				" find_world=", vp.find_world_3d(), " camera3d=", vp.get_camera_3d(),
				" disable_3d=", vp.disable_3d, " clear_mode=", vp.render_target_clear_mode,
				" transparent_bg=", vp.transparent_bg)
		print("PROBE stage_internal=", stage.internal_size, " render_scale=", stage.render_scale,
				" pixel_scale=", stage.pixel_scale, " image_visible=", stage.image.visible,
				" image_scale=", stage.image.scale, " image_pos=", stage.image.position,
				" image_modulate=", stage.image.modulate)
		print("PROBE keyart_alpha=", _title._keyart.modulate.a if _title._keyart != null else -1.0,
				" keyart_visible=", _title._keyart.visible if _title._keyart != null else false,
				" stage_visible_in_tree=", stage.is_visible_in_tree())
		print("PROBE draw_calls=", vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
				" objects=", vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_OBJECTS_IN_FRAME))
	if world == null:
		return
	var meshes := world.find_children("*", "MeshInstance3D", true, false)
	var cameras := world.find_children("*", "Camera3D", true, false)
	var lights := world.find_children("*", "Light3D", true, false)
	print("PROBE world_children=", world.get_child_count(), " meshes=", meshes.size(),
			" cameras=", cameras.size(), " lights=", lights.size())
	for camera in cameras:
		var cam := camera as Camera3D
		print("PROBE camera ", cam.name, " current=", cam.current, " projection=", cam.projection,
				" fov=", cam.fov, " pos=", cam.global_position, " basis_z=", cam.global_transform.basis.z,
				" near=", cam.near, " far=", cam.far, " cull_mask=", cam.cull_mask)
	var shown := 0
	for mesh in meshes:
		var mi := mesh as MeshInstance3D
		if String(mi.get_path()).find("BlenderHall") >= 0:
			print("PROBE blender ", mi.name, " aabb=", mi.get_aabb(), " xform=", mi.global_transform)
			shown += 1
			if shown >= 14:
				break
	print("PROBE blender_meshes=", meshes.filter(func(m): return String(m.get_path()).find("BlenderHall") >= 0).size())
	shown = 0
	for mesh in meshes:
		var mi := mesh as MeshInstance3D
		if shown < 8:
			print("PROBE mesh ", mi.get_path(), " visible=", mi.is_visible_in_tree(),
					" pos=", mi.global_position, " aabb=", mi.get_aabb(), " mat=", mi.material_override)
			shown += 1
	print("PROBE lighting=", world.find_children("*", "WorldEnvironment", true, false).size(),
			" environment=", _env_info(world))
	await _title_viewport_probe(stage)
	_minimal_3d_probe()


## Is the title's own SubViewport actually rendering? Drop an unshaded debug cube in
## front of the shot camera and read the render target back.
func _title_viewport_probe(stage) -> void:
	var vp: SubViewport = stage.viewport
	print("PROBE title_world_3d_match=", stage.world.get_world_3d() == vp.find_world_3d(),
			" node_world=", stage.world.get_world_3d(), " viewport_world=", vp.find_world_3d(),
			" texture=", vp.get_texture().get_size())
	var cam := vp.get_camera_3d()
	if cam != null:
		print("PROBE camera_frustum_near=", cam.get_frustum()[0], " camera_global=", cam.global_position)
		print("PROBE rig_cam fov=", cam.fov, " size=", cam.size, " keep=", cam.keep_aspect,
				" proj=", cam.projection, " h=", cam.h_offset, " v=", cam.v_offset,
				" foff=", cam.frustum_offset, " xform=", cam.global_transform,
				" matrix=", cam.get_camera_projection())
		await RenderingServer.frame_post_draw
		print("PROBE rig_cam_after_frame xform=", cam.global_transform,
				" fov=", cam.fov, " current=", cam.current)
		cam.make_current()
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		print("PROBE after_make_current draw_calls=", vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME))
		cam.current = false
		await RenderingServer.frame_post_draw
		cam.current = true
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		print("PROBE after_current_toggle draw_calls=", vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME))
		print("PROBE rig_flags visible=", cam.visible, " visible_in_tree=", cam.is_visible_in_tree(),
				" is_current=", cam.is_current(), " viewport_ok=", cam.get_viewport() == vp,
				" process=", cam.is_processing(), " process_mode=", cam.process_mode,
				" env=", cam.environment, " attrs=", cam.attributes)
		for i in 4:
			await RenderingServer.frame_post_draw
			print("PROBE trace", i, " cam=", vp.get_camera_3d(), " mask=", cam.cull_mask,
					" near=", cam.near, " far=", cam.far, " fov=", cam.fov,
					" pos=", cam.global_position, " draws=",
					vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME))
		print("PROBE worlds cam_world=", cam.get_world_3d(), " vp_world=", vp.find_world_3d(),
				" match=", cam.get_world_3d() == vp.find_world_3d(),
				" top_level=", cam.top_level,
				" mesh_world_match=", (stage.world.find_children("*", "MeshInstance3D", true, false)[0] as Node3D).get_world_3d() == vp.find_world_3d())
		# Same pose, plain camera: does the transform position work at all?
		var rig_xform: Transform3D = cam.global_transform
		cam.current = false
		var twin := Camera3D.new()
		twin.name = "ProbeTwinCamera"
		twin.fov = cam.fov
		twin.near = cam.near
		twin.far = cam.far
		twin.keep_aspect = cam.keep_aspect
		stage.world.add_child(twin)
		twin.global_transform = rig_xform
		twin.current = true
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		print("PROBE twin_camera draws=", vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
				" center=", vp.get_texture().get_image().get_pixel(vp.size.x / 2, vp.size.y / 2))
		twin.queue_free()
		cam.current = true
	var dbg := MeshInstance3D.new()
	dbg.name = "DebugCube"
	var box := BoxMesh.new()
	box.size = Vector3(2, 2, 2)
	dbg.mesh = box
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.0, 1.0, 0.2)
	mat.no_depth_test = true
	dbg.material_override = mat
	if cam != null:
		dbg.global_position = cam.global_position + cam.global_transform.basis.z * 4.0
	stage.world.add_child(dbg)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	print("PROBE with_cube draw_calls=", vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
			" objects=", vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_OBJECTS_IN_FRAME))
	var img := vp.get_texture().get_image()
	print("PROBE with_cube center_pixel=", img.get_pixel(img.get_width() / 2, img.get_height() / 2))
	dbg.queue_free()
	await _nested_viewport_probe(stage)


## Same minimal 3D viewport, but parented inside the title's Node2D/Control/CanvasLayer
## chain, to tell "scene hierarchy" from "stage configuration".
func _nested_viewport_probe(stage) -> void:
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.size = Vector2i(160, 90)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	stage.add_child(vp)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0, 4)
	cam.current = true
	vp.add_child(cam)
	var box := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1, 1, 1)
	box.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.1, 0.4, 1.0)
	box.material_override = mat
	vp.add_child(box)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	print("PROBE nested draw_calls=", vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
			" center=", vp.get_texture().get_image().get_pixel(80, 45))
	# Re-arm the title viewport: a resize or update-mode toggle is the cheapest way to
	# force a full redraw of a render target that may have been skipped.
	var title_vp: SubViewport = stage.viewport
	title_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	title_vp.size = title_vp.size + Vector2i(1, 1)
	await RenderingServer.frame_post_draw
	title_vp.size = title_vp.size - Vector2i(1, 1)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	print("PROBE rearmed draw_calls=", title_vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
			" center=", title_vp.get_texture().get_image().get_pixel(title_vp.size.x / 2, title_vp.size.y / 2))
	# Bisect: is it the Environment, the rig camera, or the viewport size?
	var wenvs: Array = stage.world.find_children("*", "WorldEnvironment", true, false)
	var env_backup: Environment = null
	if not wenvs.is_empty():
		env_backup = (wenvs[0] as WorldEnvironment).environment
		(wenvs[0] as WorldEnvironment).environment = null
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		print("PROBE no_env draw_calls=", title_vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME))
		(wenvs[0] as WorldEnvironment).environment = env_backup
	var rig := title_vp.get_camera_3d()
	var rig_current := rig.current if rig != null else false
	if rig != null:
		rig.current = false
	var plain := Camera3D.new()
	plain.name = "ProbePlainCamera"
	plain.position = Vector3(0, 4.3, 20)
	plain.fov = 30.0
	plain.current = true
	stage.world.add_child(plain)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	print("PROBE plain_camera draw_calls=", title_vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
			" center=", title_vp.get_texture().get_image().get_pixel(title_vp.size.x / 2, title_vp.size.y / 2))
	plain.queue_free()
	if rig != null:
		rig.current = rig_current
	# Fresh viewport at the same 1288x728 size inside the same chain.
	var big := SubViewport.new()
	big.own_world_3d = true
	big.size = Vector2i(1288, 728)
	big.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	stage.add_child(big)
	var bcam := Camera3D.new()
	bcam.position = Vector3(0, 0, 4)
	bcam.current = true
	big.add_child(bcam)
	var bbox := MeshInstance3D.new()
	var bmesh := BoxMesh.new()
	bmesh.size = Vector3(1, 1, 1)
	bbox.mesh = bmesh
	big.add_child(bbox)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	print("PROBE big_nested draw_calls=", big.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
			" center=", big.get_texture().get_image().get_pixel(644, 364))
	big.queue_free()
	vp.queue_free()


## Isolate the renderer itself: a fresh SubViewport with its own 3D world, one camera
## and one unshaded box. If this draws nothing either, the problem is the Forward+
## SubViewport pipeline, not the title world.
func _minimal_3d_probe() -> void:
	var vp := SubViewport.new()
	vp.name = "MinimalProbe"
	vp.own_world_3d = true
	vp.size = Vector2i(160, 90)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0, 4)
	cam.current = true
	vp.add_child(cam)
	var box := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1, 1, 1)
	box.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0.2, 0.2)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	box.material_override = mat
	vp.add_child(box)
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.texture = vp.get_texture()
	add_child(sprite)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	print("PROBE minimal viewport=", vp.size, " world3d=", vp.world_3d,
			" find_world=", vp.find_world_3d(), " camera3d=", vp.get_camera_3d())
	print("PROBE minimal draw_calls=", vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
			" objects=", vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_OBJECTS_IN_FRAME))
	var img := vp.get_texture().get_image()
	var center := img.get_pixel(img.get_width() / 2, img.get_height() / 2)
	print("PROBE minimal center_pixel=", center)
	vp.queue_free()


func _env_info(world: TitleWorld3D) -> String:
	var hosts := world.find_children("*", "WorldEnvironment", true, false)
	if hosts.is_empty():
		return "none"
	var env: Environment = (hosts[0] as WorldEnvironment).environment
	if env == null:
		return "no Environment resource"
	return "bg=%d ambient=%d glow=%s ssao=%s fog=%s" % [
		env.background_mode, env.ambient_light_source, str(env.glow_enabled),
		str(env.ssao_enabled), str(env.volumetric_fog_enabled)]
