extends CharacterBody3D

const CombatData = preload("res://scripts/combat_data.gd")
signal combat_hit(data: Dictionary)
signal player_hurt(data: Dictionary)
signal notice(message: String)
signal motion_event(kind: String, position: Vector3)

const WALK_SPEED: float = 1.1
const RUN_SPEED: float = 5.8
const GRAVITY: float = 24.0
const JUMP_SPEED: float = 9.3
const BODY_HEIGHT: float = 1.78
const BUFFER_TIME: float = 0.10
const CLIMB_DURATION: float = 0.60

var weapon: int = 0
var facing: float = 1.0
var health: float = 100.0
var max_health: float = 100.0
var controls_locked: bool = false
var ui_pointer_blocked: bool = false
var god_mode: bool = false
var action: String = "free"
var action_t: float = 0.0
var attack_id: int = 0
var attack_index: int = 0
var attack_kind: String = "ground"
var attack_elapsed: float = 0.0
var attack_spec: Dictionary = {}
var hitstop_remaining: float = 0.0
var rope_connected: bool = false
var rope_anchor: Vector3 = Vector3.ZERO
var rope_length: float = 0.0
var rope_taut: bool = false
var air_dodges_left: int = 1
var wall_dir: float = 0.0
var land_weight: float = 0.0
var total_hits: int = 0
var total_damage: float = 0.0
var parry_success_time: float = 0.0
var spawn_position: Vector3 = Vector3.ZERO
var last_hit_position: Vector3 = Vector3.ZERO

var _input: Dictionary = {}
var _previous_input: Dictionary = {}
var _test_input: Dictionary = {}
var _test_mode: bool = false
var _buffer: Dictionary = {"jump":0.0,"dodge":0.0,"attack":0.0,"strong":0.0,"wire":0.0}
var _coyote: float = 0.0
var _stable_ground: float = 0.0
var _wall_lock: float = 0.0
var _wall_push: float = 0.0
var _land_lock: float = 0.0
var _invulnerable: float = 0.0
var _attack_lock: float = 0.0
var _air_rearm: float = 0.0
var _charge_time: float = 0.0
var _charge_released: bool = false
var _charge_sweep_active: bool = false
var _attack_facing: float = 1.0
var _combo_queued: bool = false
var _was_grounded: bool = false
var _fresh_reset: bool = true
var _just_jumped: bool = false
var _attack_started_air: bool = false
var _hit_ids: Dictionary = {}
var _previous_blade: Array = []
var _plunge_landed: bool = false
var _plunge_recovery_t: float = 0.0
var _dodge_air: bool = false
var _dodge_dir: float = 1.0
var _counter_window: float = 0.0
var _pending_weapon: int = -1
var _fall_speed: float = 0.0
var _rope_node: Node3D
var _ledge_hang: Vector3
var _ledge_grip: Vector3
var _ledge_target: Vector3
var _ledge_lock: float = 0.0
var _climb_start: Vector3
var _motion_name: String = "idle"
var _motion_time: float = 0.0
var _hurt_duration: float = 0.30
var _notice_cooldown: float = 0.0

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.22
	floor_max_angle = deg_to_rad(48.0)
	floor_constant_speed = true
	slide_on_ceiling = false
	var collider := CollisionShape3D.new()
	collider.name = "BodyCollision"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.24
	capsule.height = BODY_HEIGHT
	collider.shape = capsule
	collider.position.y = BODY_HEIGHT * 0.5
	add_child(collider)
	spawn_position = global_position
	add_to_group("player")

func set_test_input(values: Dictionary) -> void:
	_test_mode = true
	_test_input = values.duplicate()

func disable_test_input() -> void:
	_test_mode = false
	_previous_input.clear()

func _pressed(name: String) -> bool:
	return bool(_input.get(name, false))

func _edge(name: String) -> bool:
	return _pressed(name) and not bool(_previous_input.get(name, false))

func _released(name: String) -> bool:
	return not _pressed(name) and bool(_previous_input.get(name, false))

func _real_pressed(name: String) -> bool:
	return InputMap.has_action(name) and Input.is_action_pressed(name)

func _sample_input() -> void:
	_previous_input = _input.duplicate()
	if _test_mode:
		_input = _test_input.duplicate()
		_input["move"] = clampf(float(_input.get("move", 0.0)), -1.0, 1.0)
	else:
		_input = {}
		for key in ["walk","jump","dodge","attack","strong","guard","wire","up","down"]:
			_input[key] = _real_pressed(key)
		_input["move"] = float(_real_pressed("move_right")) - float(_real_pressed("move_left"))
		_input["weapon"] = -1
		for n in range(3):
			if InputMap.has_action("weapon"+str(n+1)) and Input.is_action_just_pressed("weapon"+str(n+1)):
				_input["weapon"] = n
	if ui_pointer_blocked and not _test_mode:
		_input["attack"] = false
		_input["strong"] = false
	for key in _buffer:
		if _edge(key):
			_buffer[key] = BUFFER_TIME
	if _edge("attack") and action == "attack" and attack_phase() != "startup":
		_combo_queued = true
	if _released("strong") and action == "charge":
		_charge_released = true

func _physics_process(delta: float) -> void:
	_sample_input()
	if controls_locked:
		_combo_queued = false
		for key in _buffer:
			_buffer[key] = 0.0
		return
	if hitstop_remaining > 0.0:
		hitstop_remaining = maxf(0.0, hitstop_remaining - delta)
		return
	_tick_timers(delta)
	_just_jumped = false
	_charge_sweep_active = false
	var grounded: bool = _grounded()
	if grounded:
		_coyote = BUFFER_TIME
		_stable_ground += delta
		if _stable_ground >= 2.0/60.0:
			air_dodges_left = 1
	else:
		_stable_ground = 0.0
		_coyote = maxf(0.0, _coyote - delta)
	wall_dir = _wall_direction()
	_handle_weapon_request()
	if action == "dead":
		velocity.y = maxf(velocity.y - GRAVITY*delta, -24.0)
		velocity.x = move_toward(velocity.x, 0.0, 18.0*delta)
		move_and_slide()
		global_position.z = 0.0
		_update_motion_clock(delta)
		return
	if action in ["ledge", "climb"]:
		_process_ledge(delta)
		_update_motion_clock(delta)
		return
	_handle_actions(grounded)
	grounded = _grounded()
	if _released("jump") and velocity.y > 1.0 and action != "hurt":
		velocity.y *= 0.48
	if not grounded:
		velocity.y = maxf(velocity.y - GRAVITY*delta, -24.0)
		_fall_speed = maxf(_fall_speed, -velocity.y)
	elif velocity.y < 0.0:
		velocity.y = -0.10
	if action == "hurt":
		velocity.x = move_toward(velocity.x, 0.0, (10.0 if grounded else 3.0)*delta)
		if action_t >= _hurt_duration:
			_end_action()
	elif action == "dodge":
		_process_dodge(delta)
	elif action == "charge":
		_charge_time += delta
		velocity.x = move_toward(velocity.x, 0.0, 40.0*delta)
		if not grounded:
			_charge_time = 0.0
			_end_action()
		elif _charge_released or not _pressed("strong") or _charge_time+0.000001 >= CombatData.CHARGE_FULL[weapon]/60.0:
			var charge: float = clampf(_charge_time / (CombatData.CHARGE_FULL[weapon]/60.0), 0.0, 1.0)
			if _charge_time < CombatData.CHARGE_FIRST[weapon]/60.0:
				charge = 0.0
			_begin_attack("strong", 0, charge)
	elif action == "attack":
		_process_attack(delta, grounded)
	elif action == "guard":
		_move_horizontal(delta, grounded, 0.35)
		if not _pressed("guard"):
			_end_action()
	else:
		_move_horizontal(delta, grounded, 1.0)
		if absf(float(_input.get("move", 0.0))) > 0.1 and _wall_push <= 0.0:
			facing = signf(float(_input["move"]))
	if not grounded and wall_dir != 0.0 and not rope_connected and action == "free" and _wall_lock <= 0.0:
		if float(_input.get("move", 0.0))*wall_dir > 0.15 and velocity.y < 0.0:
			velocity.y = maxf(velocity.y, -1.55)
	if rope_connected:
		_process_rope_before(delta)
	var falling_speed_before: float = _fall_speed
	var movement_start: Vector3 = global_position
	move_and_slide()
	_fresh_reset = false
	global_position.z = 0.0
	velocity.z = 0.0
	if _charge_sweep_active:
		# The thrust covers the actual collision-limited displacement, not a teleport.
		_hit_targets(false,movement_start)
	if rope_connected:
		_solve_rope_after()
	var now_grounded: bool = _grounded()
	if now_grounded and not _was_grounded and not _just_jumped:
		_on_landed(falling_speed_before)
	if now_grounded:
		_fall_speed = 0.0
	if is_on_ceiling() and velocity.y > 0.0:
		velocity.y = 0.0
	if not now_grounded and action == "free" and not rope_connected:
		_try_ledge()
	_was_grounded = now_grounded
	if global_position.y < -9.0 or absf(global_position.x) > 90.0:
		reset_at(spawn_position)
		_safe_notice("낙하 지점에서 돌아왔습니다.")
	_update_motion_clock(delta)

func _tick_timers(delta: float) -> void:
	action_t += delta
	for key in _buffer:
		if key == "jump" and _land_lock > 0.0:
			continue
		_buffer[key] = maxf(0.0, float(_buffer[key]) - delta)
	_wall_lock = maxf(0.0, _wall_lock - delta)
	_wall_push = maxf(0.0, _wall_push - delta)
	_ledge_lock = maxf(0.0, _ledge_lock - delta)
	_land_lock = maxf(0.0, _land_lock - delta)
	_invulnerable = maxf(0.0, _invulnerable - delta)
	_attack_lock = maxf(0.0, _attack_lock - delta)
	_air_rearm = maxf(0.0, _air_rearm - delta)
	_counter_window = maxf(0.0, _counter_window - delta)
	parry_success_time = maxf(0.0, parry_success_time - delta)
	_notice_cooldown = maxf(0.0, _notice_cooldown - delta)
	land_weight = maxf(0.0, land_weight - delta*6.0)

func _grounded() -> bool:
	return not _fresh_reset and is_on_floor() and velocity.y < 0.2 and not _just_jumped

func _wall_direction() -> float:
	if not is_on_wall() or _grounded() or _wall_lock > 0.0:
		return 0.0
	var normal: Vector3 = get_wall_normal()
	if absf(normal.x) < 0.5:
		return 0.0
	return -signf(normal.x)

func _move_horizontal(delta: float, grounded: bool, factor: float) -> void:
	if _wall_push > 0.0:
		return
	var axis: float = float(_input.get("move", 0.0))
	var speed: float = WALK_SPEED if _pressed("walk") else RUN_SPEED
	var accel: float = 42.0 if grounded else 20.0
	if grounded and (axis == 0.0 or axis * velocity.x < 0.0):
		accel = 55.0
	if rope_connected and not grounded:
		velocity.x = clampf(velocity.x + axis*9.0*delta, -10.5, 10.5)
	else:
		velocity.x = move_toward(velocity.x, axis*speed*factor, accel*delta)

func _can_cancel_motion() -> bool:
	if _land_lock > 0.0 or action in ["hurt", "dead", "climb"]:
		return false
	if action == "attack":
		if attack_kind == "plunge" and not _plunge_landed:
			return attack_elapsed < 2.0/60.0
		if attack_elapsed < 2.0/60.0:
			return true
		return attack_elapsed >= float(attack_spec.get("startup",0.0)) + float(attack_spec.get("active",0.0)) + float(attack_spec.get("cancel_recovery",0.0))
	if action == "dodge":
		return action_t >= (12.0 if _dodge_air else 14.0)/60.0
	return true

func _can_new_attack() -> bool:
	return _can_cancel_motion() and _attack_lock <= 0.0 and _air_rearm <= 0.0 and action != "charge"

func _handle_actions(grounded: bool) -> void:
	var axis: float = float(_input.get("move",0.0))
	if float(_buffer["jump"]) > 0.0 and _can_cancel_motion():
		if rope_connected and not grounded:
			_cancel_for_motion()
			_detach_rope()
			_buffer["jump"] = 0.0
		elif grounded or _coyote > 0.0 or wall_dir != 0.0:
			_cancel_for_motion()
			_do_jump(wall_dir != 0.0 and not grounded)
			grounded = false
	if float(_buffer["dodge"]) > 0.0 and _can_cancel_motion():
		if grounded or air_dodges_left > 0:
			_cancel_for_motion()
			_begin_dodge(grounded,axis)
			_buffer["dodge"] = 0.0
			return
		elif rope_connected:
			_safe_notice("공중 회피를 사용했습니다. 점프로 줄을 놓을 수 있습니다.")
	if float(_buffer["wire"]) > 0.0 and _can_cancel_motion():
		_buffer["wire"] = 0.0
		if rope_connected:
			_detach_rope()
		else:
			_cancel_for_motion()
			_try_attach_rope()
	if action == "attack":
		if _combo_queued and _can_cancel_motion() and attack_phase() == "recovery":
			var count: int = CombatData.chain_count(weapon,attack_kind)
			if attack_index+1 < count:
				var next_kind: String = "ground" if attack_kind == "run" else "air" if attack_kind in ["wall","release"] else attack_kind
				if absf(axis)>0.1:
					facing = signf(axis)
				_begin_attack(next_kind,attack_index+1)
				_buffer["attack"] = 0.0
			return
	if float(_buffer["strong"]) > 0.0 and _can_new_attack():
		_buffer["strong"] = 0.0
		if rope_connected and not grounded:
			_detach_rope()
			_begin_attack("release")
		elif wall_dir != 0.0 and not grounded:
			_do_jump(true)
			_begin_attack("wall")
		elif not grounded:
			var floor_probe: Dictionary = _ray(global_position+Vector3.UP*0.1,global_position-Vector3.UP*1.25)
			_begin_attack("strong" if not floor_probe.is_empty() else "plunge")
		else:
			if rope_connected:
				_detach_rope()
			_set_action("charge")
			_charge_time = 0.0
			_charge_released = false
		return
	if float(_buffer["attack"]) > 0.0 and _can_new_attack():
		_buffer["attack"] = 0.0
		if rope_connected and not grounded:
			if weapon == 1:
				_safe_notice("대검: K 강공격으로 줄을 놓고 공격합니다.")
			else:
				_begin_attack("wire")
		elif wall_dir != 0.0 and not grounded:
			_do_jump(true)
			_begin_attack("wall")
		elif not grounded or _just_jumped:
			_begin_attack("up" if _pressed("up") else "air")
		else:
			if rope_connected:
				_detach_rope()
			if parry_success_time > 0.0 or _counter_window > 0.0:
				_begin_attack("counter")
				parry_success_time = 0.0
				_counter_window = 0.0
			elif absf(velocity.x)>2.5 and not _pressed("walk"):
				_begin_attack("run")
			else:
				_begin_attack("ground")
		return
	if _pressed("guard") and grounded and action == "free" and _land_lock <= 0.0:
		if rope_connected:
			_detach_rope()
		_set_action("guard")

func _do_jump(from_wall: bool = false) -> void:
	_buffer["jump"] = 0.0
	_coyote = 0.0
	_land_lock = 0.0
	if from_wall:
		var away: float = -wall_dir if wall_dir != 0.0 else -facing
		velocity = Vector3(away*6.3,8.8,0.0)
		facing = away
		_wall_push = 6.0/60.0
		_wall_lock = 12.0/60.0
		_ledge_lock = 12.0/60.0
		_detach_rope()
		motion_event.emit("wall_jump",global_position+Vector3.UP*0.6)
	else:
		velocity.y = JUMP_SPEED
		motion_event.emit("jump",global_position)
	_just_jumped = true
	_stable_ground = 0.0
	_set_action("free")

func _begin_dodge(grounded: bool, axis: float) -> void:
	if not grounded:
		air_dodges_left -= 1
	_dodge_air = not grounded
	_dodge_dir = signf(axis) if absf(axis)>0.1 else facing
	_detach_rope()
	_set_action("dodge")
	velocity.x = _dodge_dir*(9.0 if _dodge_air else 10.0)
	if _dodge_air:
		velocity.y = maxf(velocity.y,0.0)*0.35
	_counter_window = 0.0
	motion_event.emit("dodge",global_position+Vector3.UP*0.5)

func _process_dodge(delta: float) -> void:
	var fast_end: float = (8.0 if _dodge_air else 10.0)/60.0
	if action_t < fast_end:
		velocity.x = _dodge_dir*(9.0 if _dodge_air else 10.0)
		if _dodge_air:
			velocity.y = maxf(velocity.y,-1.4)
	else:
		velocity.x = move_toward(velocity.x,0.0,25.0*delta)
	if action_t >= (12.0 if _dodge_air else 14.0)/60.0:
		_counter_window = 0.18
	if action_t >= (18.0 if _dodge_air else 22.0)/60.0:
		_end_action()

func _begin_attack(kind: String, index: int = 0, charge: float = 0.0) -> void:
	_set_action("attack")
	attack_id += 1
	attack_kind = kind
	attack_index = index
	attack_elapsed = 0.0
	attack_spec = CombatData.attack(weapon,kind,index,charge)
	_attack_facing = facing
	_attack_started_air = not _grounded() or _just_jumped or kind in ["air","up","wall","release","wire","plunge"]
	_combo_queued = false
	_hit_ids.clear()
	_previous_blade.clear()
	_plunge_landed = false
	_plunge_recovery_t = 0.0
	_charge_time = 0.0
	if kind == "run":
		velocity.x = facing*maxf(absf(velocity.x),3.0)
	motion_event.emit("swing_"+str(weapon),global_position+Vector3.UP)

func _process_attack(delta: float, grounded: bool) -> void:
	var before: float = attack_elapsed
	attack_elapsed += delta
	var startup: float = float(attack_spec.get("startup",0.1))
	var active: float = float(attack_spec.get("active",0.1))
	var total: float = float(attack_spec.get("total",0.5))
	if attack_elapsed < 2.0/60.0:
		var intent: float = float(_input.get("move",0.0))
		if absf(intent)>0.1:
			_attack_facing = signf(intent)
	facing = _attack_facing
	if attack_kind == "plunge":
		if _plunge_landed:
			_plunge_recovery_t += delta
			velocity.x = move_toward(velocity.x,0.0,30.0*delta)
			if _plunge_recovery_t >= float(attack_spec.get("recovery",0.4)):
				_finish_attack()
			return
		if attack_elapsed >= startup:
			velocity.y = minf(velocity.y,-12.0 if weapon != 1 else -16.0)
			velocity.x = move_toward(velocity.x,0.0,8.0*delta)
			_hit_targets(false)
		return
	var advance_distance: float = float(attack_spec.get("advance_distance",0.0))
	if attack_kind == "strong" and advance_distance > 0.0:
		var advance_start: float = float(attack_spec["advance_start"])
		var advance_end: float = float(attack_spec["advance_end"])
		var a: float = clampf((before-advance_start)/(advance_end-advance_start),0.0,1.0)
		var b: float = clampf((attack_elapsed-advance_start)/(advance_end-advance_start),0.0,1.0)
		# A smooth distance curve provides anticipation, acceleration and a planted finish.
		velocity.x = facing*advance_distance*(smoothstep(0.0,1.0,b)-smoothstep(0.0,1.0,a))/delta
		_charge_sweep_active = weapon == 2 and before < startup+active and attack_elapsed >= startup
	elif grounded:
		if weapon == 1 or attack_kind == "strong" or (weapon == 2 and attack_index == 3):
			var desired: float = 0.0
			if before < startup and attack_elapsed >= startup and weapon == 2:
				velocity.x = facing*5.5
			if attack_kind == "run" and attack_elapsed < startup:
				desired = facing*2.2
			velocity.x = move_toward(velocity.x,desired,(20.0 if attack_elapsed < startup else 36.0)*delta)
		elif attack_kind == "run" and attack_elapsed < startup+active:
			velocity.x = move_toward(velocity.x,facing*2.8,10.0*delta)
		else:
			var speed: float = WALK_SPEED * (0.75 if weapon == 0 else 0.9)
			velocity.x = move_toward(velocity.x,float(_input.get("move",0.0))*speed,28.0*delta)
	else:
		if _wall_push <= 0.0 and not rope_connected:
			var strength: float = 8.0 if weapon == 1 and attack_phase() == "active" else 16.0
			velocity.x = move_toward(velocity.x,float(_input.get("move",0.0))*RUN_SPEED,strength*delta)
	if attack_phase() == "active" and not (weapon == 2 and advance_distance > 0.0):
		_hit_targets(false)
	else:
		_cache_blade()
	if attack_elapsed >= total:
		_finish_attack()

func attack_phase() -> String:
	if action != "attack" or attack_spec.is_empty():
		return "none"
	if attack_kind == "plunge":
		if _plunge_landed:
			return "recovery"
		return "startup" if attack_elapsed < float(attack_spec["startup"]) else "active"
	if attack_elapsed < float(attack_spec["startup"]):
		return "startup"
	if attack_elapsed < float(attack_spec["startup"])+float(attack_spec["active"]):
		return "active"
	return "recovery"

func _finish_attack() -> void:
	if _attack_started_air:
		_air_rearm = 6.0/60.0
	_end_action()

func _cancel_for_motion() -> void:
	if action == "attack":
		_attack_lock = maxf(_attack_lock,float(attack_spec.get("total",0.0))-attack_elapsed)
		if _attack_started_air:
			_air_rearm = maxf(_air_rearm,_attack_lock+6.0/60.0)
	_charge_time = 0.0
	_combo_queued = false
	_end_action()

func _set_action(value: String) -> void:
	action = value
	action_t = 0.0

func _end_action() -> void:
	_set_action("free")
	_combo_queued = false
	_previous_blade.clear()

func _cache_blade() -> Array:
	var visual: Node = get_node_or_null("Visual")
	if visual != null and visual.has_method("get_blade_segment"):
		var segment: Array = visual.call("get_blade_segment")
		if segment.size() >= 2:
			_previous_blade = segment.duplicate()
			return segment
	return []

func _hit_targets(ground_impact: bool, charge_start: Variant = null) -> void:
	var visual: Node = get_node_or_null("Visual")
	var segment: Array = []
	if visual != null and visual.has_method("get_blade_segment"):
		segment = visual.call("get_blade_segment")
	var prior: Array = _previous_blade.duplicate()
	_previous_blade = segment.duplicate()
	for target in get_tree().get_nodes_in_group("dummies"):
		if not is_instance_valid(target) or not target is Node3D or not target.has_method("receive_hit"):
			continue
		var tid: int = target.get_instance_id()
		if _hit_ids.has(tid):
			continue
		var center: Vector3 = target.global_position+Vector3.UP*0.95
		var radius: float = 0.53
		if target.has_method("get_hit_center"):
			center = target.call("get_hit_center")
		if target.has_method("get_hit_radius"):
			radius = float(target.call("get_hit_radius"))
		var hit_pos: Vector3 = center
		var overlap: bool = false
		if ground_impact:
			overlap = absf(center.x-global_position.x)<1.5 and absf(center.y-global_position.y)<1.7
		elif charge_start is Vector3:
			# During the held rapier thrust, sweep from the old hilt to the new tip.
			# Every target has its own attack-ID entry, so the first enemy never consumes the dash.
			var a2 := Vector2(charge_start.x+_attack_facing*0.25,charge_start.y+1.12)
			var b2 := Vector2(global_position.x+_attack_facing*float(attack_spec.get("reach",1.6)),global_position.y+1.12)
			var near: Vector2 = Geometry2D.get_closest_point_to_segment(Vector2(center.x,center.y),a2,b2)
			overlap = near.distance_to(Vector2(center.x,center.y)) < radius+0.04
			hit_pos = Vector3(near.x,near.y,0.0)
		elif segment.size()>=2:
			var c2 := Vector2(center.x,center.y)
			var a2 := Vector2(segment[0].x,segment[0].y)
			var b2 := Vector2(segment[1].x,segment[1].y)
			var near: Vector2 = Geometry2D.get_closest_point_to_segment(c2,a2,b2)
			var distance: float = near.distance_to(c2)
			if prior.size()>=2:
				for pair in [[Vector2(prior[0].x,prior[0].y),a2],[Vector2(prior[1].x,prior[1].y),b2],[Vector2(prior[0].x,prior[0].y),b2]]:
					var p: Vector2 = Geometry2D.get_closest_point_to_segment(c2,pair[0],pair[1])
					if p.distance_to(c2)<distance:
						distance = p.distance_to(c2)
						near = p
				overlap = distance < radius+0.035
				hit_pos = Vector3(near.x,near.y,0.0)
			else:
				overlap = distance < radius+0.035
				hit_pos = Vector3(near.x,near.y,0.0)
		elif visual == null:
			# Deterministic headless controller tests have no rendered weapon.
			var forward: float = (center.x-global_position.x)*_attack_facing
			overlap = forward>-0.1 and forward<float(attack_spec.get("reach",1.3)) and absf(center.y-(global_position.y+1.0))<0.85
		if not overlap:
			continue
		var obstacle: Dictionary = _ray(global_position+Vector3.UP*1.05,hit_pos)
		if not obstacle.is_empty():
			var body: Object = obstacle.get("collider")
			if body != target and not (body is Node and target.is_ancestor_of(body)):
				continue
		var hit: Dictionary = {"attack_id":attack_id,"position":hit_pos,"direction":_attack_facing,"strength":float(attack_spec.get("strength",1.0)),"damage":float(attack_spec.get("damage",15.0)),"weapon":weapon,"kind":attack_kind,"ground_impact":ground_impact,"source":self}
		_hit_ids[tid] = true
		if bool(target.call("receive_hit",hit)):
			total_hits += 1
			total_damage += float(hit["damage"])
			last_hit_position = hit_pos
			hitstop_remaining = maxf(hitstop_remaining,float(attack_spec.get("hitstop",0.05)))
			combat_hit.emit(hit)

func _on_landed(speed: float) -> void:
	land_weight = clampf(speed/14.0,0.25,1.0)
	if rope_connected:
		_detach_rope()
	motion_event.emit("land_hard" if speed>15.0 else "land",global_position)
	if action == "attack" and attack_kind == "plunge":
		_plunge_landed = true
		_plunge_recovery_t = 0.0
		_hit_targets(true)
		motion_event.emit("plunge",global_position)
	elif speed>15.0 and action not in ["hurt","dead"]:
		_land_lock = 8.0/60.0
	if float(_buffer["jump"])>0.0 and _land_lock<=0.0 and _can_cancel_motion():
		air_dodges_left = 1
		_cancel_for_motion()
		_do_jump(false)

func _handle_weapon_request() -> void:
	var request: int = int(_input.get("weapon",-1))
	if request>=0 and request<3 and request!=weapon:
		_pending_weapon = request
	if _pending_weapon<0:
		return
	if rope_connected or action in ["ledge","climb"]:
		_safe_notice("줄이나 벽에서 내려온 뒤 무기를 바꿀 수 있습니다.")
		return
	if action == "free" and _attack_lock<=0.0:
		weapon = _pending_weapon
		_pending_weapon = -1
		motion_event.emit("weapon",global_position+Vector3.UP)

func _try_attach_rope() -> void:
	var hand: Vector3 = global_position+Vector3.UP*1.5
	var best: Node3D = null
	var best_score: float = INF
	for node in get_tree().get_nodes_in_group("wire_anchors"):
		if not node is Node3D:
			continue
		var offset: Vector3 = node.global_position-hand
		var distance: float = offset.length()
		if distance>8.5 or distance<0.6 or offset.y < -0.3:
			continue
		if not _ray(hand,node.global_position).is_empty():
			continue
		var score: float = distance + (2.0 if offset.x*facing < -0.5 else 0.0)
		if score<best_score:
			best_score = score
			best = node
	if best == null:
		_safe_notice("주변의 빛나는 고리가 보이는 곳에서 와이어를 사용하세요.")
		motion_event.emit("wire_fail",hand)
		return
	_rope_node = best
	rope_connected = true
	rope_anchor = best.global_position
	rope_length = clampf(hand.distance_to(rope_anchor),0.8,8.5)
	rope_taut = false
	motion_event.emit("wire_attach",hand)

func _detach_rope() -> void:
	if rope_connected:
		motion_event.emit("wire_release",global_position+Vector3.UP*1.5)
	rope_connected = false
	rope_taut = false
	_rope_node = null

func _process_rope_before(delta: float) -> void:
	if not is_instance_valid(_rope_node):
		_detach_rope()
		return
	rope_anchor = _rope_node.global_position
	var hand: Vector3 = global_position+Vector3.UP*1.5
	var ray: Dictionary = _ray(hand,rope_anchor)
	if not ray.is_empty():
		_detach_rope()
		motion_event.emit("wire_break",hand)
		return
	var radial: Vector3 = hand-rope_anchor
	rope_taut = radial.length()>=rope_length-0.06 and not _grounded()
	if rope_taut and radial.length()>0.001:
		var normal: Vector3 = radial.normalized()
		var outward: float = velocity.dot(normal)
		if outward>0.0:
			velocity -= normal*outward
		# Gravity and input supply the swing; attaching never adds propulsion.
		velocity = velocity.limit_length(10.5)
		velocity.z = 0.0

func _solve_rope_after() -> void:
	var hand: Vector3 = global_position+Vector3.UP*1.5
	var radial: Vector3 = hand-rope_anchor
	if radial.length()>rope_length and radial.length()>0.001:
		var target: Vector3 = rope_anchor+radial.normalized()*rope_length-Vector3.UP*1.5
		move_and_collide(target-global_position)
		var normal: Vector3 = radial.normalized()
		var outward: float = velocity.dot(normal)
		if outward>0.0:
			velocity -= normal*outward
	global_position.z = 0.0

func _ray(start: Vector3, end: Vector3) -> Dictionary:
	if start.distance_squared_to(end)<0.00001 or not is_inside_tree():
		return {}
	var query := PhysicsRayQueryParameters3D.create(start,end,1,[get_rid()])
	query.collide_with_areas = false
	return get_world_3d().direct_space_state.intersect_ray(query)

func _try_ledge() -> void:
	if _ledge_lock>0.0 or _wall_lock>0.0 or velocity.y>2.0:
		return
	var dir: float = signf(float(_input.get("move",0.0)))
	if dir==0.0:
		return
	var chest: Vector3 = global_position+Vector3.UP*1.15
	var low: Dictionary = _ray(chest,chest+Vector3.RIGHT*dir*0.42)
	var high: Dictionary = _ray(global_position+Vector3.UP*1.86,global_position+Vector3.UP*1.86+Vector3.RIGHT*dir*0.48)
	if low.is_empty() or not high.is_empty():
		return
	var over: Vector3 = global_position+Vector3(dir*0.48,2.0,0.0)
	var top: Dictionary = _ray(over,over-Vector3.UP*1.0)
	if top.is_empty() or top["normal"].y<0.7:
		return
	var point: Vector3 = top["position"]
	var target: Vector3 = Vector3(point.x+dir*0.30,point.y+0.04,0.0)
	if not _ray(target+Vector3.UP*0.2,target+Vector3.UP*1.72).is_empty():
		return
	_ledge_grip = Vector3(float(low["position"].x),point.y,0.0)
	_ledge_hang = Vector3(_ledge_grip.x-dir*0.30,point.y-1.88,0.0)
	_ledge_target = target
	facing = dir
	velocity = Vector3.ZERO
	global_position = _ledge_hang
	_buffer["jump"] = 0.0
	_set_action("ledge")

func _process_ledge(delta: float) -> void:
	if action == "climb":
		var t: float = clampf(action_t/CLIMB_DURATION,0.0,1.0)
		var yweight: float = smoothstep(0.0,0.62,t)
		var xweight: float = smoothstep(0.58,1.0,t)
		var desired := Vector3(lerpf(_climb_start.x,_ledge_target.x,xweight),lerpf(_climb_start.y,_ledge_target.y,yweight),0.0)
		move_and_collide(desired-global_position)
		if t>=1.0:
			_end_action()
			_ledge_lock = 0.2
		return
	velocity = Vector3.ZERO
	global_position = _ledge_hang
	if _pressed("down"):
		_ledge_lock = 0.25
		_end_action()
		velocity.y = -1.0
		if float(_buffer["attack"])>0.0 and _attack_lock<=0.0 and _air_rearm<=0.0:
			_buffer["attack"] = 0.0
			_begin_attack("air")
	elif float(_buffer["jump"])>0.0 or _edge("up") or (float(_input.get("move",0.0))*facing > 0.2 and float(_previous_input.get("move",0.0))*facing <= 0.2):
		_buffer["jump"] = 0.0
		var move: float = float(_input.get("move",0.0))
		if move*facing < -0.2:
			_ledge_lock = 0.25
			_end_action()
			velocity = Vector3(move*6.0,7.5,0.0)
			facing = move
		else:
			_climb_start = global_position
			_set_action("climb")
	elif float(_buffer["dodge"])>0.0 and air_dodges_left>0:
		_buffer["dodge"] = 0.0
		_ledge_lock = 0.25
		_end_action()
		_begin_dodge(false,-facing)

func take_hit(damage: float, impulse: Vector3) -> void:
	if action == "dead" or _invulnerable>0.0:
		return
	if action == "dodge":
		var end: float = (8.0 if _dodge_air else 10.0)/60.0
		if action_t>=2.0/60.0 and action_t<end:
			return
	var frontal: bool = impulse.x*facing<0.0 or absf(impulse.x)<0.1
	if action == "guard" and frontal:
		if action_t>=2.0/60.0 and action_t<8.0/60.0:
			parry_success_time = 0.40
			hitstop_remaining = 0.06
			player_hurt.emit({"kind":"parry","position":global_position+Vector3.UP,"damage":0.0,"direction":facing})
			motion_event.emit("parry",global_position+Vector3.UP)
			return
		if damage<28.0:
			velocity.x = impulse.x*0.25
			hitstop_remaining = 0.04
			player_hurt.emit({"kind":"guard","position":global_position+Vector3.UP,"damage":0.0,"direction":facing})
			return
	if not god_mode:
		health = maxf(0.0,health-damage)
	_detach_rope()
	_combo_queued = false
	_previous_blade.clear()
	attack_spec.clear()
	attack_elapsed = 0.0
	_charge_time = 0.0
	_ledge_lock = 0.3
	_wall_lock = 0.3
	_invulnerable = 0.55
	velocity = impulse
	velocity.z = 0.0
	_hurt_duration = 0.5 if damage>=25.0 else 0.3
	_set_action("dead" if health<=0.0 else "hurt")
	hitstop_remaining = 0.06
	player_hurt.emit({"kind":"dead" if health<=0.0 else "hurt","position":global_position+Vector3.UP,"damage":damage,"direction":signf(impulse.x)})

func reset_at(point: Vector3) -> void:
	global_position = point
	global_position.z = 0.0
	spawn_position = point
	velocity = Vector3.ZERO
	health = max_health
	facing = 1.0
	_set_action("free")
	attack_spec.clear()
	attack_elapsed = 0.0
	_hit_ids.clear()
	_previous_blade.clear()
	_combo_queued = false
	rope_connected = false
	rope_taut = false
	_rope_node = null
	air_dodges_left = 1
	hitstop_remaining = 0.0
	_wall_lock = 0.0
	_wall_push = 0.0
	_ledge_lock = 0.0
	_land_lock = 0.0
	_attack_lock = 0.0
	_air_rearm = 0.0
	_invulnerable = 0.0
	_fall_speed = 0.0
	_coyote = 0.0
	_stable_ground = 0.0
	_was_grounded = false
	_fresh_reset = true
	_just_jumped = false
	_charge_time = 0.0
	_charge_released = false
	_charge_sweep_active = false
	_ledge_grip = Vector3.ZERO
	parry_success_time = 0.0
	_counter_window = 0.0
	_pending_weapon = -1
	for key in _buffer:
		_buffer[key] = 0.0

func _safe_notice(message: String) -> void:
	if _notice_cooldown<=0.0:
		notice.emit(message)
		_notice_cooldown = 1.0

func _visible_action() -> String:
	if action != "free":
		return action
	if rope_connected and not _grounded():
		return "rope"
	if not _grounded():
		if wall_dir!=0.0 and not rope_connected and velocity.y<=0.0 and float(_input.get("move",0.0))*wall_dir>0.1:
			return "wall"
		return "jump" if velocity.y>0.1 else "fall"
	return "move" if absf(velocity.x)>0.08 else "idle"

func _update_motion_clock(delta: float) -> void:
	var name_now: String = _visible_action()
	if name_now!=_motion_name:
		_motion_name = name_now
		_motion_time = 0.0
	else:
		_motion_time += delta

func get_visual_state() -> Dictionary:
	var display: String = _visible_action()
	var label: String = {"idle":"준비","move":"걷기" if _pressed("walk") else "달리기","jump":"상승","fall":"낙하","wall":"벽 미끄러짐","ledge":"가장자리 잡기","climb":"올라서기","rope":"와이어 이동","guard":"방어 / 패링","dodge":"공중 회피" if _dodge_air else "지상 회피","charge":"차지","hurt":"피격","dead":"사망","attack":"공격"}.get(display,display)
	if action=="attack":
		label = {"ground":"지상 연격","run":"달리기 공격","air":"공중 연격","up":"상단 공격","plunge":"낙하 공격","wall":"벽차기 공격","wire":"와이어 유지 공격","release":"와이어 이탈 공격","strong":"강공격","counter":"반격"}.get(attack_kind,attack_kind)+" · "+str(attack_index+1)+"타"
		if attack_kind == "strong" and float(attack_spec.get("charge",0.0)) > 0.0:
			label = "관통 돌진" if weapon == 2 else "차지 공격"
	return {
		"action":display,"action_t":attack_elapsed if action=="attack" else action_t if action!="free" else _motion_time,
		"velocity":velocity,"grounded":_grounded(),"facing":facing,"weapon":weapon,
		"attack_id":attack_id,"attack_index":attack_index,"attack_kind":attack_kind,
		"attack_phase":attack_phase(),"attack_progress":clampf(attack_elapsed/maxf(0.001,float(attack_spec.get("total",1.0))),0.0,1.0),
		"attack_startup":float(attack_spec.get("startup",0.1)),"attack_active":float(attack_spec.get("active",0.1)),"attack_total":float(attack_spec.get("total",0.4)),
		"charge_ratio":clampf(_charge_time/(CombatData.CHARGE_FULL[weapon]/60.0),0.0,1.0),
		"attack_charged":action == "attack" and float(attack_spec.get("charge",0.0)) > 0.0,
		"attack_charge":float(attack_spec.get("charge",0.0)) if action == "attack" else 0.0,
		"charge_advancing":action == "attack" and float(attack_spec.get("advance_distance",0.0))>0.0 and attack_elapsed>=float(attack_spec.get("advance_start",0.0)) and attack_elapsed<float(attack_spec.get("advance_end",0.0)),
		"ledge_grip":_ledge_grip,"climb_duration":CLIMB_DURATION,"climb_progress":clampf(action_t/CLIMB_DURATION,0.0,1.0) if action == "climb" else 0.0,
		"wall_dir":wall_dir,"rope_connected":rope_connected,"rope_taut":rope_taut,"rope_anchor":rope_anchor,
		"rope_length":rope_length,"hitstop":hitstop_remaining>0.0,"land_weight":land_weight,"walking":_pressed("walk"),
		"motion_label":label,"health":health,"air_dodges_left":air_dodges_left,"parry_success_time":parry_success_time,
		"plunge_landed":_plunge_landed,"plunge_recovery_t":_plunge_recovery_t,"dodge_air":_dodge_air,"turn_input":float(_input.get("move",0.0))
	}
