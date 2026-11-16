extends SceneTree
# Sprite capture for the pixel-art pipeline.
#
# Drives the real Player controller + HeroVisual exactly as the game does
# (same input buffering, combo queueing, blending and IK), advances the
# simulation one physics tick (1/60 s) at a time, and saves one PNG per tick
# from an orthographic camera locked to the player's feet. Because the camera
# follows the player origin, the sprite is in player-local space: the engine
# applies the body movement, the sprite only carries the pose.
#
# Run (needs a display; use xvfb-run on Linux):
#   godot --path . --rendering-driver opengl3 --fixed-fps 60 \
#     --script res://tools/capture_motion.gd -- --weapon=0 --sequence=combo \
#     --px_per_m=56.25 --msaa=0 --toon=hard --out=res://capture_raw/sword_combo_hard
#
# Options (all optional):
#   --weapon=0|1|2        0 sword, 1 greatsword, 2 rapier
#   --sequence=combo|single|idle
#   --px_per_m=56.25      pixel density. 56.25 = a 640x360 screen showing the
#                         lab's 6.4 m vertical span (hero ~103 px tall)
#   --canvas_m=3.4x2.9    capture area in metres (width x height)
#   --feet_px=12          pixels between the bottom edge and the feet
#   --msaa=0|2|4|8        3D multisample anti-aliasing (0 = off)
#   --toon=hard|soft      hard = hero_toon_pixel.gdshader, soft = game shader
#   --trail=0|1           keep the game's sword-tip trail mesh (default off)
#   --tail=24             extra ticks captured after returning to idle
#   --out=res://capture_raw/<name>

const PixelToon = preload("res://shaders/hero_toon_pixel.gdshader")

var opts := {
	"weapon": "0", "sequence": "combo", "px_per_m": "56.25", "canvas_m": "3.4x2.9",
	"feet_px": "12", "msaa": "0", "toon": "hard", "trail": "0", "tail": "24",
	"out": "res://capture_raw/capture",
}
var player
var hero
var vp: SubViewport
var cam: Camera3D
var frames_meta: Array = []

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and "=" in arg:
			var kv := arg.substr(2).split("=", true, 1)
			opts[kv[0]] = kv[1]
	call_deferred("_run")

func _input_set(values: Dictionary = {}) -> void:
	player.set_test_input(values)

func _tick(record: bool) -> void:
	# One physics tick, then pose the visual for that tick, then render it.
	await physics_frame
	hero.update_state(player.get_visual_state(), 1.0 / 60.0)
	cam.global_position = Vector3(player.global_position.x + _cam_offset_x(), player.global_position.y + _cam_offset_y(), 8.0)
	await RenderingServer.frame_post_draw
	if record:
		_save_frame()

func _cam_offset_x() -> float:
	return 0.0

func _cam_offset_y() -> float:
	var h := _canvas_size().y
	var ppm := float(opts.px_per_m)
	return (h * 0.5 - float(opts.feet_px)) / ppm

func _canvas_size() -> Vector2i:
	var parts: PackedStringArray = String(opts.canvas_m).split("x")
	var ppm := float(opts.px_per_m)
	return Vector2i(int(round(float(parts[0]) * ppm)), int(round(float(parts[1]) * ppm)))

func _save_frame() -> void:
	var idx := frames_meta.size()
	var img := vp.get_texture().get_image()
	var path := "%s/f_%04d.png" % [opts.out, idx]
	img.save_png(path)
	var s: Dictionary = player.get_visual_state()
	frames_meta.append({
		"frame": idx, "file": path.get_file(), "action": s.get("action"),
		"action_t": s.get("action_t"), "attack_index": s.get("attack_index"),
		"attack_kind": s.get("attack_kind"), "attack_phase": s.get("attack_phase"),
		"attack_progress": s.get("attack_progress"), "facing": s.get("facing"),
		"player_x": player.global_position.x,
	})

func _setup_world() -> Node3D:
	for action in ["move_left", "move_right", "walk", "jump", "dodge", "attack", "strong", "guard", "wire", "down", "up", "weapon1", "weapon2", "weapon3"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	var size := _canvas_size()
	vp = SubViewport.new()
	vp.size = size
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_taa = false
	var msaa := int(opts.msaa)
	vp.msaa_3d = {0: Viewport.MSAA_DISABLED, 2: Viewport.MSAA_2X, 4: Viewport.MSAA_4X, 8: Viewport.MSAA_8X}.get(msaa, Viewport.MSAA_DISABLED)
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	root.add_child(vp)
	var world := Node3D.new()
	vp.add_child(world)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = float(size.y) / float(opts.px_per_m)
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.near = 0.1
	cam.far = 30.0
	world.add_child(cam)
	cam.current = true
	var floor_body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(200, 1, 8)
	collider.shape = shape
	floor_body.position.y = -0.5
	floor_body.add_child(collider)
	world.add_child(floor_body)
	return world

func _swap_toon() -> void:
	if String(opts.toon) != "hard":
		return
	for mat in hero.materials:
		var col: Color = mat.get_shader_parameter("base_color")
		mat.shader = PixelToon
		mat.set_shader_parameter("base_color", col)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(opts.out))
	var world := _setup_world()
	player = load("res://scripts/player.gd").new()
	world.add_child(player)
	hero = load("res://scripts/hero_visual.gd").new()
	hero.name = "Visual"
	player.add_child(hero)
	await process_frame
	_swap_toon()
	if hero.trail_node and String(opts.trail) != "1":
		hero.trail_node.visible = false
	# Settle: reset, select weapon, face right, return to a calm idle.
	_input_set()
	player.reset_at(Vector3.ZERO)
	player.weapon = int(opts.weapon)
	for i in range(15): await _tick(false)
	_input_set({"move": 1.0})
	for i in range(2): await _tick(false)
	_input_set()
	for i in range(40): await _tick(false)

	var seq := String(opts.sequence)
	var expected: int = [3, 4, 4][int(opts.weapon)] if seq == "combo" else 1
	if seq == "idle":
		for i in range(int(round(hero._clip_length("sword_idle") * 60.0))):
			await _tick(true)
	else:
		_input_set({"attack": true})
		await _tick(true)
		_input_set()
		var queued := {}
		var returned_at := -1
		for i in range(600):
			var s: Dictionary = player.get_visual_state()
			var idx := int(s.get("attack_index", 0))
			if String(s.get("attack_phase")) == "active" and idx < expected - 1 and not queued.has(idx):
				_input_set({"attack": true})
				queued[idx] = true
			else:
				_input_set()
			await _tick(true)
			var action := String(player.get_visual_state().get("action"))
			if i > 10 and action in ["idle", "move"] and returned_at < 0:
				returned_at = frames_meta.size()
			if returned_at >= 0 and frames_meta.size() - returned_at >= int(opts.tail):
				break

	var info := {
		"engine": Engine.get_version_info().string,
		"options": opts,
		"canvas_px": [vp.size.x, vp.size.y],
		"feet_px_from_bottom": int(opts.feet_px),
		"tick_seconds": 1.0 / 60.0,
		"frame_count": frames_meta.size(),
		"frames": frames_meta,
	}
	var f := FileAccess.open("%s/capture.json" % opts.out, FileAccess.WRITE)
	f.store_string(JSON.stringify(info, "\t"))
	print("CAPTURE_DONE ", opts.out, " frames=", frames_meta.size(), " canvas=", vp.size)
	quit(0)
