extends Node3D

var player
var hero
var arena
var camera: Camera3D
var ui: CanvasLayer
var status_label: Label
var detail_label: Label
var notice_label: Label
var hp_bar: ProgressBar
var charge_bar: ProgressBar
var help_panel: PanelContainer
var weapon_buttons: Array[Button] = []
var zone_buttons: Array[Button] = []
var audio_players: Array[AudioStreamPlayer] = []
var rope_mesh: MeshInstance3D
var rope_material: StandardMaterial3D
var debug_mesh: MeshInstance3D
var debug_material: StandardMaterial3D
var font: Font
var current_zone: int = 0
var slow: bool = false
var muted: bool = false
var show_debug: bool = false
var show_help: bool = false
var attackers: bool = false
var shake: float = 0.0
var notice_t: float = 0.0
var hit_count: int = 0
var damage_total: float = 0.0
var last_action: String = ""
var last_attack_id: int = -1
var presentation_ready: bool = false
var frame_n: int = 0
var capture_mode: bool = false
var capture_frames: int = 0
var capture_path: String = ""
const INK := Color("111c2c")
const PAPER := Color("e5dfcd")
const MUTED := Color("91a6b6")
const TEAL := Color("78d4cd")
const GOLD := Color("dfb86b")
const WEAPON_NAMES := ["일반검", "대검", "세검"]

func _ready() -> void:
	Engine.max_fps = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_inputs()
	font = load("res://assets/fonts/NotoSansKR.otf")
	_setup_environment()
	arena = load("res://scripts/arena.gd").new()
	arena.name = "Arena"
	add_child(arena)
	player = load("res://scripts/player.gd").new()
	player.name = "Player"
	add_child(player)
	hero = load("res://scripts/hero_visual.gd").new()
	hero.name = "Visual"
	player.add_child(hero)
	if arena.has_method("configure_player"):
		arena.configure_player(player)
	player.combat_hit.connect(_on_combat_hit)
	player.player_hurt.connect(_on_player_hurt)
	player.notice.connect(_notice)
	player.motion_event.connect(_on_motion_event)
	_setup_camera()
	_setup_rope()
	_setup_audio()
	_setup_ui()
	_go_zone(0)
	presentation_ready = true
	_notice("A / D 이동 · J 공격 · 1 / 2 / 3 무기 변경 · H 조작 안내")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			capture_mode = true
			capture_path = arg.trim_prefix("--capture=")
		if arg.begins_with("--capture-frames="):
			capture_frames = int(arg.trim_prefix("--capture-frames="))
	if capture_mode and capture_frames == 0:
		capture_frames = 90

func _setup_inputs() -> void:
	var bindings = {
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"walk": [KEY_SHIFT], "jump": [KEY_SPACE], "dodge": [KEY_K, KEY_CTRL],
		"attack": [KEY_J], "strong": [KEY_L], "guard": [KEY_I], "wire": [KEY_E],
		"up": [KEY_W, KEY_UP], "down": [KEY_S, KEY_DOWN],
		"weapon1": [KEY_1], "weapon2": [KEY_2], "weapon3": [KEY_3]
	}
	for action in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for keycode in bindings[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = keycode
			InputMap.action_add_event(action, ev)
	for item in [["attack", MOUSE_BUTTON_LEFT], ["strong", MOUSE_BUTTON_RIGHT]]:
		var ev := InputEventMouseButton.new()
		ev.button_index = item[1]
		InputMap.action_add_event(item[0], ev)

func _setup_environment() -> void:
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("101a28")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b7c8dc")
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env_node.environment = env
	add_child(env_node)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-32, -32, -15)
	light.light_color = Color("fff0ce")
	light.light_energy = 1.1
	light.shadow_enabled = false
	add_child(light)

func _setup_camera() -> void:
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = 6.5
	camera.near = 0.1
	camera.far = 90.0
	camera.position = Vector3(-1, 2.2, 16)
	camera.current = true
	add_child(camera)

func _setup_rope() -> void:
	rope_mesh = MeshInstance3D.new()
	rope_material = StandardMaterial3D.new()
	rope_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rope_material.albedo_color = Color("e9c783")
	rope_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	rope_mesh.material_override = rope_material
	add_child(rope_mesh)
	debug_mesh = MeshInstance3D.new()
	debug_material = StandardMaterial3D.new()
	debug_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	debug_material.albedo_color = Color("83fff2")
	debug_mesh.material_override = debug_material
	add_child(debug_mesh)

func _setup_audio() -> void:
	for i in 10:
		var ap := AudioStreamPlayer.new()
		ap.volume_db = -8.0
		add_child(ap)
		audio_players.append(ap)

func _style(bg: Color, border: Color = Color.TRANSPARENT, radius: int = 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1 if border.a > 0 else 0)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb

func _label(text: String, size: int = 16, color: Color = PAPER) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _button(text: String, callback: Callable, width: float = 90) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(width, 35)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_color", PAPER)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_stylebox_override("normal", _style(Color("1a293b"), Color("35485c")))
	b.add_theme_stylebox_override("hover", _style(Color("2a4154"), TEAL))
	b.add_theme_stylebox_override("pressed", _style(Color("305b61"), TEAL))
	b.pressed.connect(callback)
	return b

func _setup_ui() -> void:
	ui = CanvasLayer.new()
	ui.layer = 10
	add_child(ui)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)
	var top := PanelContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 20
	top.offset_right = -20
	top.offset_top = 16
	top.offset_bottom = 105
	top.add_theme_stylebox_override("panel", _style(Color(0.045, 0.075, 0.12, 0.94), Color("304155")))
	root.add_child(top)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	top.add_child(row)
	var title := VBoxContainer.new()
	title.custom_minimum_size.x = 250
	row.add_child(title)
	title.add_child(_label("BLACK CRUSADE / MOTION LAB 05.1", 11, TEAL))
	title.add_child(_label("검은 성전  ·  전환 모션 테스트", 21))
	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(center)
	var weapons := HBoxContainer.new()
	weapons.add_theme_constant_override("separation", 6)
	center.add_child(weapons)
	for i in 3:
		var index: int = i
		var b := _button(str(i + 1) + "  " + WEAPON_NAMES[i], func(): _select_weapon(index), 100)
		weapons.add_child(b)
		weapon_buttons.append(b)
	var zones := HBoxContainer.new()
	zones.add_theme_constant_override("separation", 6)
	center.add_child(zones)
	var zone_names := ["F1 기본 전투", "F2 벽 이동", "F3 와이어", "F4 방어 훈련"]
	for i in 4:
		var index: int = i
		var b := _button(zone_names[i], func(): _go_zone(index), 98)
		b.custom_minimum_size.y = 29
		b.add_theme_font_size_override("font_size", 12)
		zones.add_child(b)
		zone_buttons.append(b)
	var options := VBoxContainer.new()
	row.add_child(options)
	options.add_child(_button("H 조작 안내", _toggle_help, 105))
	options.add_child(_button("R 다시 시작", func(): _reset_lab(), 105))
	var side := PanelContainer.new()
	side.position = Vector2(20, 126)
	side.custom_minimum_size = Vector2(242, 160)
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	side.add_theme_stylebox_override("panel", _style(Color(0.045, 0.075, 0.12, 0.84), Color("293d51")))
	root.add_child(side)
	var stats := VBoxContainer.new()
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats.add_theme_constant_override("separation", 7)
	side.add_child(stats)
	status_label = _label("일반검 · 준비", 17, PAPER)
	stats.add_child(status_label)
	hp_bar = ProgressBar.new()
	hp_bar.custom_minimum_size = Vector2(218, 8)
	hp_bar.show_percentage = false
	hp_bar.add_theme_stylebox_override("background", _style(Color("223040")))
	hp_bar.add_theme_stylebox_override("fill", _style(Color("a0c4b8")))
	stats.add_child(hp_bar)
	charge_bar = ProgressBar.new()
	charge_bar.custom_minimum_size = Vector2(218, 5)
	charge_bar.show_percentage = false
	charge_bar.add_theme_stylebox_override("background", _style(Color("223040")))
	charge_bar.add_theme_stylebox_override("fill", _style(GOLD))
	stats.add_child(charge_bar)
	detail_label = _label("", 13, MUTED)
	stats.add_child(detail_label)
	var settings := HBoxContainer.new()
	settings.add_theme_constant_override("separation", 5)
	stats.add_child(settings)
	settings.add_child(_button("F5 ½속도", _toggle_slow, 92))
	settings.add_child(_button("T 공격 더미", _toggle_attackers, 108))
	var footer := PanelContainer.new()
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_left = 20
	footer.offset_right = -20
	footer.offset_top = -64
	footer.offset_bottom = -16
	footer.add_theme_stylebox_override("panel", _style(Color(0.035, 0.06, 0.10, 0.95), Color("304155")))
	root.add_child(footer)
	var footer_text := _label("A D 이동   Shift 걷기   Space 점프   J / 좌클릭 공격   L / 우클릭 강공격·차지   K 회피   I 방어·패링   E 와이어", 14, PAPER)
	footer_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_child(footer_text)
	notice_label = _label("", 16, GOLD)
	notice_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	notice_label.offset_left = -350
	notice_label.offset_right = 350
	notice_label.offset_top = 121
	notice_label.offset_bottom = 150
	notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(notice_label)
	help_panel = PanelContainer.new()
	help_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	help_panel.offset_left = -380
	help_panel.offset_right = 380
	help_panel.offset_top = -280
	help_panel.offset_bottom = 280
	help_panel.add_theme_stylebox_override("panel", _style(Color(0.035, 0.06, 0.1, 0.985), TEAL, 12))
	root.add_child(help_panel)
	var help := VBoxContainer.new()
	help.add_theme_constant_override("separation", 10)
	help_panel.add_child(help)
	help.add_child(_label("모션을 직접 연결해 보세요", 25))
	help.add_child(_label("이동 중 방향 전환 · 점프 공격 · 벽차기 · 와이어 이탈 공격", 15, TEAL))
	var instructions := [
		"A / D, ← / →   달리기    |    Shift + 이동   걷기",
		"Space   점프 / 벽차기 / 공중에서 와이어 놓기",
		"J 또는 좌클릭   약공격 연계    |    1 / 2 / 3   무기 변경",
		"L 또는 우클릭   차지 완료 시 자동 공격 · 일찍 놓으면 먼저 발동",
		"W + 공격   공중 상단 공격    |    S + 강공격   낙하 공격",
		"K 또는 Ctrl   회피    |    I   방어 · 누른 직후 패링",
		"E   가까운 고리에 와이어 연결 / 해제",
		"턱에 매달리면 정지 · 벽 쪽 방향을 다시 누르거나 W / ↑로 올라서기",
		"F1~F4   구역 이동    |    T   공격 더미 켜기 / 끄기",
		"F5   ½속도    |    F6   판정 표시    |    M   음소거    |    F11   전체 화면",
		"R   현재 구역 초기화    |    H / Esc   안내 열기 / 닫기"
	]
	for line in instructions:
		help.add_child(_label(line, 16, PAPER))
	help.add_child(_label("와이어 중 일반검·세검은 약공격 가능. 대검은 강공격으로 줄을 놓고 공격합니다.", 13, GOLD))
	help.add_child(_button("계속하기", _toggle_help, 180))
	help_panel.visible = false

func _process(dt: float) -> void:
	if not presentation_ready:
		return
	frame_n += 1
	var state: Dictionary = player.get_visual_state()
	player.controls_locked = show_help
	var hovered := get_viewport().gui_get_hovered_control()
	player.ui_pointer_blocked = hovered != null and hovered is Button
	var frozen: bool = bool(state.get("hitstop", false))
	hero.update_state(state, 0.0 if frozen or show_help else dt)
	arena.set_frozen(frozen or show_help)
	player.process_mode = Node.PROCESS_MODE_DISABLED if show_help else Node.PROCESS_MODE_INHERIT
	var wire_view: bool = current_zone == 2 or player.rope_connected
	var desired := Vector3(player.position.x + player.facing * 1.35, maxf(3.5 if wire_view else 2.2, player.position.y + 1.15), 16.0)
	var follow := 1.0 - exp(-dt * 7.0)
	camera.position = camera.position.lerp(desired, follow)
	camera.size = lerpf(camera.size, 7.5 if wire_view else 6.5, follow)
	if shake > 0:
		camera.h_offset = sin(Time.get_ticks_msec() * 0.13) * shake
		camera.v_offset = cos(Time.get_ticks_msec() * 0.19) * shake * 0.5
		shake = maxf(0, shake - dt * 0.7)
	else:
		camera.h_offset = 0
		camera.v_offset = 0
	_update_rope(state)
	_update_debug()
	status_label.text = WEAPON_NAMES[clampi(player.weapon, 0, 2)] + " · " + str(state.get("motion_label", state.get("action", "준비")))
	hp_bar.value = float(player.health)
	charge_bar.value = float(state.get("charge_ratio", 0.0)) * 100
	detail_label.text = "명중 %d회  ·  누적 피해 %d\n%s%s" % [hit_count, int(damage_total), "½속도  ·  " if slow else "", "공격 더미 ON" if attackers else "공격 더미 OFF"]
	if show_debug:
		detail_label.text += "\n%.2f m/s · %s · %d FPS" % [player.velocity.x, str(state.get("attack_phase", "")), Engine.get_frames_per_second()]
	for i in weapon_buttons.size():
		weapon_buttons[i].modulate = TEAL if i == player.weapon else Color.WHITE
	for i in zone_buttons.size():
		zone_buttons[i].modulate = GOLD if i == current_zone else Color.WHITE
	if notice_t > 0:
		notice_t -= dt
		notice_label.modulate.a = minf(1.0, notice_t * 2.0)
	else:
		notice_label.text = ""
	var action: String = str(state.get("action", ""))
	var current_attack_id: int = int(state.get("attack_id", -1))
	if action == "attack" and (last_action != "attack" or (current_attack_id >= 0 and current_attack_id != last_attack_id)):
		_play_audio("sword_whoosh_A.wav", -16, 1.15 if player.weapon == 1 else 1.8)
	last_action = action
	last_attack_id = current_attack_id
	if player.position.y < -8:
		_go_zone(current_zone)
		_notice("연습 위치로 돌아왔습니다")
	if capture_mode and frame_n >= capture_frames:
		capture_mode = false
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(capture_path)
		get_tree().quit()

func _update_rope(state: Dictionary) -> void:
	rope_mesh.visible = bool(state.get("rope_connected", false))
	if not rope_mesh.visible:
		return
	var from: Vector3 = hero.get_wire_hand()
	var to: Vector3 = state.get("rope_anchor", Vector3.ZERO)
	from.z = 0.40
	to.z = 0.40
	var direction := to - from
	var normal := Vector3(-direction.y, direction.x, 0).normalized() * 0.009
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in [from + normal, from - normal, to + normal, from - normal, to - normal, to + normal]:
		mesh.surface_add_vertex(v)
	mesh.surface_end()
	rope_mesh.mesh = mesh

func _update_debug() -> void:
	debug_mesh.visible = show_debug
	if not show_debug:
		return
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var points: Array = hero.get_blade_segment()
	if points.size() >= 2:
		for point in points:
			var v: Vector3 = point
			v.z = 0.7
			mesh.surface_add_vertex(v)
	var base: Vector3 = player.global_position
	var corners := [base + Vector3(-0.24, 0, 0.7), base + Vector3(0.24, 0, 0.7), base + Vector3(0.24, 1.78, 0.7), base + Vector3(-0.24, 1.78, 0.7)]
	for i in 4:
		mesh.surface_add_vertex(corners[i])
		mesh.surface_add_vertex(corners[(i + 1) % 4])
	mesh.surface_end()
	debug_mesh.mesh = mesh

func _unhandled_key_input(event: InputEvent) -> void:
	if not presentation_ready or not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_F1: _go_zone(0)
		KEY_F2: _go_zone(1)
		KEY_F3: _go_zone(2)
		KEY_F4: _go_zone(3)
		KEY_F5: _toggle_slow()
		KEY_F6:
			show_debug = not show_debug
			_notice("판정 표시 " + ("ON" if show_debug else "OFF"))
		KEY_T: _toggle_attackers()
		KEY_R: _reset_lab()
		KEY_H, KEY_ESCAPE: _toggle_help()
		KEY_M:
			muted = not muted
			_notice("효과음 " + ("OFF" if muted else "ON"))
		KEY_F11:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)

func _select_weapon(index: int) -> void:
	Input.action_press("weapon" + str(index + 1))
	await get_tree().physics_frame
	Input.action_release("weapon" + str(index + 1))

func _go_zone(zone: int) -> void:
	current_zone = zone
	if player == null or arena == null:
		return
	player.reset_at(arena.get_spawn(zone))
	if camera != null:
		camera.position = Vector3(player.position.x + 1.35, maxf(2.2, player.position.y + 1.15), 16)
	if arena.has_method("set_attackers_enabled"):
		arena.set_attackers_enabled(attackers)
	if notice_label != null:
		_notice(["3번 세검 · L을 계속 눌러 세 표적 관통 돌진", "매달린 뒤 방향을 다시 누르거나 W / ↑로 올라서기", "와이어 · 점프 후 E, 강공격으로 이탈 공격", "방어 훈련 · T로 공격 더미를 켜세요"][zone])

func _reset_lab() -> void:
	hit_count = 0
	damage_total = 0
	if arena.has_method("reset_dummies"):
		arena.reset_dummies()
	_go_zone(current_zone)

func _toggle_help() -> void:
	show_help = not show_help
	help_panel.visible = show_help
	player.controls_locked = show_help

func _toggle_slow() -> void:
	slow = not slow
	Engine.time_scale = 0.5 if slow else 1.0
	_notice("½속도로 모션을 확인합니다" if slow else "정상 속도로 돌아왔습니다")

func _toggle_attackers() -> void:
	attackers = not attackers
	arena.set_attackers_enabled(attackers)
	_notice("공격 더미 ON · I로 막거나 패링해 보세요" if attackers else "공격 더미 OFF")

func _notice(message: String) -> void:
	if notice_label == null:
		return
	notice_label.text = message
	notice_t = 3.0

func _on_combat_hit(data: Dictionary) -> void:
	hit_count += 1
	damage_total += float(data.get("damage", 0))
	shake = maxf(shake, 0.07 if player.weapon == 1 else 0.035)
	var fx = load("res://scripts/impact_fx.gd").new()
	fx.setup(data)
	add_child(fx)
	_play_audio("metal_hit_heavy.wav" if player.weapon == 1 else "metal_hit_light.wav", -7 if player.weapon == 1 else -11, 1.05 if player.weapon == 2 else 1.0)
	_play_audio("wood_hit_A.wav", -9, 0.85 if player.weapon == 1 else 1.0)

func _on_player_hurt(_data: Dictionary) -> void:
	shake = maxf(shake, 0.07)
	_play_audio("wood_hit_B.wav", -8, 0.85)

func _on_motion_event(kind: String, _position: Vector3) -> void:
	match kind:
		"jump", "wall_jump":
			_play_audio("footstep_A.wav", -13, 1.1)
		"land":
			_play_audio("footstep_B.wav", -11, 0.9)
		"land_hard", "plunge":
			_play_audio("wood_hit_B.wav", -10, 0.75)
		"wire_attach", "wire_release", "weapon":
			_play_audio("metal_hit_light.wav", -19, 1.3)
		"parry":
			_play_audio("metal_hit_heavy.wav", -8, 1.4)
		"dodge":
			_play_audio("sword_whoosh_A.wav", -16, 0.8)

func _play_audio(filename: String, volume: float = -10.0, pitch: float = 1.0) -> void:
	if muted:
		return
	var path := "res://assets/audio/" + filename
	if not ResourceLoader.exists(path):
		return
	for ap in audio_players:
		if not ap.playing:
			ap.stream = load(path)
			ap.volume_db = volume
			ap.pitch_scale = pitch
			ap.play()
			return
