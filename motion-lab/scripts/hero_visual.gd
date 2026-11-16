extends Node3D
# Runtime poses are sampled from real authored bone tracks in hero.glb.
# The only procedural adjustments are transition blending, grip/rope IK,
# facing, and short contact-aligned weapon trails. No primitive human is used.
const WeaponGeometry = preload("res://scripts/weapon_geometry.gd")
const TOON = preload("res://shaders/hero_toon.gdshader")
var model: Node3D
var skeleton: Skeleton3D
var animation_player: AnimationPlayer
var clips: Dictionary = {}
var clip_tracks: Dictionary = {}
var manifest: Dictionary = {}
var rest_pose: Array = []
var current_pose: Array = []
var blend_from: Array = []
var upper_weights: Array[float] = []
var materials: Array[ShaderMaterial] = []
var bone_ids: Dictionary = {}
var weapons: Array = []
var weapon_node: Node3D
var weapon_base := Vector3.ZERO
var weapon_tip := Vector3.UP
var grip_local := Transform3D(Basis(Vector3.RIGHT,PI/2.0),Vector3(0,0.075,0))
var grip_transform := Transform3D.IDENTITY
var trail_node: MeshInstance3D
var trail_material: StandardMaterial3D
var trail_points: Array[Vector3] = []
var _weapon := -1
var _stride_phase := 0.0
var _idle_time := 0.0
var _air_time := 0.0
var _blend_time := 1.0
var _blend_duration := 0.08
var _last_tag := ""
var _last_state: Dictionary = {}
var _last_facing := 1.0
var _yaw_from := PI/2.0-0.16
var _yaw_target := PI/2.0-0.16
var _yaw_time := 1.0
var _yaw_duration := 0.085
var _trail_attack_id := -1000
var _was_grounded := true
var _land_age := 1.0
var _warned_missing: Dictionary = {}
var _loaded := false
var _ground_bias := 0.0
var _idle_feet_y := 0.02
var _current_clip := ""

func _ready() -> void:
 if FileAccess.file_exists("res://assets/hero_manifest.json"):
  var f := FileAccess.open("res://assets/hero_manifest.json",FileAccess.READ)
  var data = JSON.parse_string(f.get_as_text())
  if data is Dictionary: manifest = data
 var packed = load("res://assets/hero.glb")
 if not packed is PackedScene:
  push_error("Hero visual: authored hero.glb could not be loaded")
  return
 model = packed.instantiate()
 model.name = "AuthoredHero"
 add_child(model)
 skeleton = _find_type(model,"Skeleton3D") as Skeleton3D
 animation_player = _find_type(model,"AnimationPlayer") as AnimationPlayer
 if skeleton == null or animation_player == null:
  push_error("Hero visual requires imported Skeleton3D and AnimationPlayer")
  return
 animation_player.stop()
 animation_player.active = false
 skeleton.reset_bone_poses()
 for i in range(skeleton.get_bone_count()):
  rest_pose.append(skeleton.get_bone_rest(i))
  bone_ids[skeleton.get_bone_name(i)] = i
  var name_lower := String(skeleton.get_bone_name(i)).to_lower()
  var upper := name_lower.begins_with("spine") or name_lower.begins_with("neck") or name_lower == "head" or name_lower.contains("arm") or name_lower.contains("hand") or name_lower.begins_with("clavicle") or name_lower.contains("index") or name_lower.contains("middle") or name_lower.contains("pinky") or name_lower.contains("ring_") or name_lower.contains("thumb")
  upper_weights.append(1.0 if upper else 0.0)
 _bind_clips()
 _apply_materials(model)
 skeleton.force_update_all_bone_transforms()
 var grip_marker = model.find_child("GripR",true,false)
 if grip_marker is Node3D and bone_ids.has("hand_r"):
  # Exported GripR is a child of the hand BoneAttachment; use its local
  # transform so a deferred attachment update cannot corrupt the socket.
  grip_local = grip_marker.transform
 for i in range(3):
  var w := WeaponGeometry.build(i)
  var root: Node3D = w["root"]
  root.top_level = true
  add_child(root)
  root.visible = false
  weapons.append(w)
 _create_trail()
 current_pose = _sample_pose("sword_idle",0.0)
 blend_from = current_pose.duplicate()
 _write_pose(current_pose)
 model.rotation.y = _yaw_target
 _set_weapon(0)
 _loaded = true
 _update_socket()

func _find_type(node: Node, type_name: String) -> Node:
 if node.is_class(type_name): return node
 for c in node.get_children():
  var found := _find_type(c,type_name)
  if found != null: return found
 return null

func _bind_clips() -> void:
 for full_name in animation_player.get_animation_list():
  var anim := animation_player.get_animation(full_name)
  var key := String(full_name).get_file().to_lower()
  if key == "reset": continue
  clips[key] = anim
  var tracks: Array = []
  for t in range(anim.get_track_count()):
   var path := anim.track_get_path(t)
   if path.get_subname_count() == 0: continue
   var bone := skeleton.find_bone(String(path.get_subname(0)))
   if bone < 0: continue
   var type := anim.track_get_type(t)
   if type in [Animation.TYPE_POSITION_3D,Animation.TYPE_ROTATION_3D,Animation.TYPE_SCALE_3D]:
    tracks.append([t,bone,type])
  clip_tracks[key] = tracks
 if clips.has("jump") and not clips.has("jump_loop"):
  clips["jump_loop"] = clips["jump"]
  clip_tracks["jump_loop"] = clip_tracks["jump"]
 if not clips.has("walk") or not clips.has("sword_1"):
  push_warning("Hero clip names: " + str(clips.keys()))

func _apply_materials(node: Node) -> void:
 if node is MeshInstance3D:
  var mesh_node := node as MeshInstance3D
  if mesh_node.mesh != null:
   for i in range(mesh_node.mesh.get_surface_count()):
    var original := mesh_node.get_active_material(i)
    var color := Color(0.6,0.65,0.68)
    if original is BaseMaterial3D: color = original.albedo_color
    var mat := ShaderMaterial.new()
    mat.shader = TOON
    mat.set_shader_parameter("base_color",color)
    mesh_node.set_surface_override_material(i,mat)
    materials.append(mat)
 for c in node.get_children(): _apply_materials(c)

func _clip_length(key: String) -> float:
 if clips.has(key): return (clips[key] as Animation).length
 return 1.0

func _sample_pose(request: String, time: float, loop := false) -> Array:
 var name := request
 if not clips.has(name):
  if not _warned_missing.has(name):
   push_warning("Missing authored clip: " + name + "; using explicit sword_idle fallback")
   _warned_missing[name] = true
  name = "sword_idle" if clips.has("sword_idle") else "idle"
 var pose := rest_pose.duplicate()
 if not clips.has(name): return pose
 var animation: Animation = clips[name]
 var t := fposmod(time,maxf(animation.length,0.0001)) if loop else clampf(time,0.0,animation.length)
 for binding in clip_tracks[name]:
  var track: int = binding[0]
  var bone: int = binding[1]
  var transform: Transform3D = pose[bone]
  match binding[2]:
   Animation.TYPE_POSITION_3D:
    transform.origin = animation.position_track_interpolate(track,t)
   Animation.TYPE_ROTATION_3D:
    var scale := transform.basis.get_scale()
    var rotation := animation.rotation_track_interpolate(track,t)
    transform.basis = Basis(rotation).scaled(scale)
   Animation.TYPE_SCALE_3D:
    var q := transform.basis.get_rotation_quaternion()
    transform.basis = Basis(q).scaled(animation.scale_track_interpolate(track,t))
  pose[bone] = transform
 # Motion extraction is owned by CharacterBody3D, never by the animation root.
 if bone_ids.has("root"):
  var root_id: int = bone_ids["root"]
  var root_t: Transform3D = pose[root_id]
  root_t.origin = (rest_pose[root_id] as Transform3D).origin
  pose[root_id] = root_t
 return pose

func _mix(a: Array,b: Array,weight: float) -> Array:
 var result: Array = []
 var w := clampf(weight,0.0,1.0)
 for i in range(a.size()): result.append((a[i] as Transform3D).interpolate_with(b[i],w))
 return result

func _mix_upper(base: Array, attack: Array, legs_weight := 0.0, upper_weight := 1.0) -> Array:
 var result: Array = []
 for i in range(base.size()):
  var weight := lerpf(legs_weight,upper_weight,upper_weights[i])
  if skeleton.get_bone_name(i) == "pelvis": weight = minf(0.35,upper_weight)
  result.append((base[i] as Transform3D).interpolate_with(attack[i],weight))
 return result

func _idle_pose(weapon: int) -> Array:
 var key := "rapier_idle" if weapon == 2 else "sword_idle"
 return _sample_pose(key,_idle_time,true)

func _ledge_hold_pose() -> Array:
 var pose := _sample_pose("jump_loop",0.15)
 # Bring the torso close enough to the lip for both authored arms to reach.
 # The collision body remains outside the wall; only the hanging pose leans in.
 var pelvis := int(bone_ids.get("pelvis",-1))
 if pelvis>=0:
  var tr: Transform3D = pose[pelvis]
  # Imported root coordinates use -Y forward and +Z up.
  tr.origin += Vector3(0,-0.20,0.10)
  pose[pelvis] = tr
 return pose

func _locomotion_pose(state: Dictionary,delta: float) -> Array:
 var velocity: Vector3 = state.get("velocity",Vector3.ZERO)
 var speed := absf(velocity.x)
 var weapon: int = int(state.get("weapon",0))
 var grounded: bool = state.get("grounded",false)
 var action: String = state.get("action","idle")
 var idle := _idle_pose(weapon)
 if grounded:
  _air_time = 0.0
  if speed < 0.08: return idle
  var run_weight := smoothstep(1.45,2.45,speed)
  var natural_speed := lerpf(0.979,5.899,run_weight)
  var duration := lerpf(_clip_length("walk"),_clip_length("run"),run_weight)
  _stride_phase = fposmod(_stride_phase + delta/maxf(duration,0.01)*clampf(speed/natural_speed,0.35,1.7),1.0)
  var walk := _sample_pose("walk",_stride_phase*_clip_length("walk"))
  var run := _sample_pose("run",_stride_phase*_clip_length("run"))
  var locomotion := _mix(walk,run,run_weight)
  # Fingers stay closed on the grip while the authored arms retain gait motion.
  for i in range(locomotion.size()):
   var bone: String = skeleton.get_bone_name(i)
   if bone.ends_with("_r") and (bone.begins_with("index") or bone.begins_with("middle") or bone.begins_with("pinky") or bone.begins_with("ring") or bone.begins_with("thumb")):
    locomotion[i] = idle[i]
  if weapon == 1:
   locomotion = _mix_upper(locomotion,idle,0.0,0.74)
  return _mix(idle,locomotion,clampf(speed/0.65,0.0,1.0))
 _air_time += delta
 var jump: Array
 if velocity.y > 0.3:
  var start_len := _clip_length("jump_start")
  var start := _sample_pose("jump_start",minf(start_len,start_len*0.58 + _air_time))
  jump = _mix(start,_sample_pose("jump_loop",0.08),clampf(_air_time/0.16,0.0,1.0))
 else:
  jump = _sample_pose("jump_loop",minf(_clip_length("jump_loop"),0.25+clampf(-velocity.y/16.0,0.0,0.4)))
 # Ready arms retain readable sword grip while legs are genuinely aerial.
 jump = _mix_upper(jump,idle,0.0,0.60 if weapon != 1 else 0.78)
 return jump

func _contact_time(clip: String) -> float:
 var all_clips: Dictionary = manifest.get("clips",{})
 if all_clips.has(clip):
  var c: Dictionary = all_clips[clip]
  if c.get("contact_time") != null: return float(c["contact_time"])
 return _clip_length(clip)*0.42

func _attack_clip(state: Dictionary) -> String:
 var weapon: int = int(state.get("weapon",0))
 var index := int(state.get("attack_index",0))
 var kind: String = state.get("attack_kind","ground")
 if weapon == 2:
  return "rapier_" + str(4 if kind in ["run","strong","release","counter"] else posmod(index,4)+1)
 if weapon == 1:
  return "great_" + str(4 if kind in ["plunge","strong","release"] else posmod(index,4)+1)
 return "sword_" + str(3 if kind in ["plunge","strong"] else posmod(index,3)+1)

func _attack_pose(state: Dictionary) -> Array:
 var clip := _attack_clip(state)
 _current_clip = clip
 var elapsed: float = float(state.get("action_t",0.0))
 var startup: float = maxf(0.016,float(state.get("attack_startup",0.12)))
 var active: float = maxf(0.016,float(state.get("attack_active",0.05)))
 var total: float = maxf(startup+active+0.016,float(state.get("attack_total",0.5)))
 var contact := _contact_time(clip)
 var length := _clip_length(clip)
 var source_before := maxf(0.0,contact-0.035)
 var source_after := minf(length,contact+0.035)
 var clip_info: Dictionary = manifest.get("clips",{}).get(clip,{})
 if clip_info.get("active_window") is Array:
  source_before = float(clip_info["active_window"][0])
  source_after = float(clip_info["active_window"][1])
 var t: float
 var charged := bool(state.get("attack_charged",false))
 if String(state.get("attack_kind","")) == "plunge" and elapsed >= startup:
  # A plunge remains dangerous until actual ground contact, so its animation
  # holds a cutting pose too. The recovery clock begins at the collision.
  if bool(state.get("plunge_landed",false)):
   var recovery := float(state.get("plunge_recovery_t",0.0))
   t = lerpf(contact,length,clampf(recovery/(total-startup-active),0.0,1.0))
  else:
   t = contact
 elif elapsed < startup:
  # A held charge already has its weapon drawn back. Resume that actual pose
  # instead of returning to the beginning of the attack's ordinary windup.
  var windup := lerpf(maxf(0.0,contact-0.30),maxf(0.0,contact-0.08),clampf(float(state.get("attack_charge",0.0)),0.0,1.0)) if charged else 0.0
  t = lerpf(windup,source_before,clampf(elapsed/startup,0.0,1.0))
 elif elapsed < startup+active:
  if charged and int(state.get("weapon",0)) == 2:
   # Keep the thrust extended for the complete physical piercing dash.
   t = lerpf(contact,source_after,clampf((elapsed-startup)/active,0.0,1.0))
  else:
   t = lerpf(source_before,source_after,clampf((elapsed-startup)/active,0.0,1.0))
 else:
  t = lerpf(source_after,length,clampf((elapsed-startup-active)/(total-startup-active),0.0,1.0))
 return _sample_pose(clip,t)

func _state_pose(state: Dictionary,delta: float) -> Array:
 var action: String = state.get("action","idle")
 var weapon: int = int(state.get("weapon",0))
 var elapsed: float = float(state.get("action_t",0.0))
 var grounded: bool = state.get("grounded",false)
 var velocity: Vector3 = state.get("velocity",Vector3.ZERO)
 var base := _locomotion_pose(state,delta)
 _current_clip = "walk/run" if grounded and absf(velocity.x)>0.1 else "sword_idle" if grounded else "jump_loop"
 if action == "attack":
  var attack := _attack_pose(state)
  var kind: String = state.get("attack_kind","ground")
  if weapon == 2 and bool(state.get("attack_charged",false)) and grounded and bool(state.get("charge_advancing",false)):
   # Authored running legs carry the extended fencing thrust forward; the
   # upper body remains the dedicated rapier motion rather than a sword slash.
   return _mix_upper(base,attack,0.42,1.0)
  if kind == "plunge":
   if not grounded:
    # Follow the authored finishing cut; legs remain tucked above the floor.
    return _mix_upper(base,attack,0.50,1.0)
   return attack
  if not grounded:
   return _mix_upper(base,attack,0.36 if weapon == 1 else 0.18,1.0)
  if weapon != 1 and kind in ["ground","wire"] and absf(velocity.x)>0.2:
   return _mix_upper(base,attack,0.10,1.0)
  return attack
 if action == "charge":
  var ratio := clampf(float(state.get("charge_ratio",0.0)),0.0,1.0)
  var clip := "great_4" if weapon == 1 else "rapier_4" if weapon == 2 else "sword_3"
  _current_clip = clip+"/charge"
  var contact := _contact_time(clip)
  var target := _sample_pose(clip,lerpf(maxf(0.0,contact-0.30),maxf(0.0,contact-0.08),ratio))
  # Small breathing/tension remains after reaching full charge, not a frozen still.
  var spine := int(bone_ids.get("spine_02",-1))
  if spine>=0:
   var tr: Transform3D = target[spine]
   tr.basis = tr.basis * Basis(Vector3.RIGHT,sin(_idle_time*7.0)*0.013*(0.3+ratio))
   target[spine] = tr
  return target
 if action in ["guard","parry"]:
  _current_clip = "guard"
  return _mix_upper(base,_sample_pose("guard",minf(elapsed,_clip_length("guard")*0.4)),0.1,1.0)
 if action == "dodge":
  _current_clip = "roll"
  var roll := _sample_pose("roll",clampf(elapsed/(0.37 if grounded else 0.30),0.0,1.0)*_clip_length("roll"))
  return roll
 if action in ["hurt","hit"]:
  _current_clip = "hit"
  return _sample_pose("hit",minf(elapsed*1.3,_clip_length("hit")))
 if action == "dead":
  _current_clip = "death"
  return _sample_pose("death",elapsed)
 if action == "ledge":
  _current_clip = "jump_loop/ledge_hold"
  # A ledge hold is a fixed pose. It must never cycle the climbing animation.
  return _ledge_hold_pose()
 if action == "climb":
  _current_clip = "climb/pull_up"
  var progress := clampf(float(state.get("climb_progress",elapsed/maxf(0.1,float(state.get("climb_duration",0.6))))),0.0,1.0)
  var hang := _ledge_hold_pose()
  var knees := _sample_pose("climb",lerpf(0.15,0.30,smoothstep(0.28,0.72,progress)))
  # The ladder source supplies a knee lift, not another root rise or an arm
  # swing. Arms stay on the lip until the hips start crossing it.
  var pose := _mix_upper(knees,hang,0.0,1.0)
  var pelvis := int(bone_ids.get("pelvis",-1))
  if pelvis>=0: pose[pelvis] = hang[pelvis]
  pose = _mix(hang,pose,smoothstep(0.22,0.65,progress))
  return _mix(pose,_idle_pose(weapon),smoothstep(0.70,1.0,progress))
 if action == "wall":
  _current_clip = "climb"
  return _mix(base,_sample_pose("climb",0.15),0.74)
 if action == "rope" or bool(state.get("rope_taut",false)):
  _current_clip = "jump_loop/rope"
  return base
 return base

func update_state(state: Dictionary,delta: float) -> void:
 if not _loaded: return
 _last_state = state
 var weapon: int = clampi(int(state.get("weapon",0)),0,2)
 _set_weapon(weapon)
 if bool(state.get("hitstop",false)):
  _update_socket()
  return
 var dt := clampf(delta,0.0,0.05)
 _idle_time += dt
 var action: String = state.get("action","idle")
 var grounded: bool = state.get("grounded",false)
 # The physics capsule clears the vertical face before crossing the ledge.
 # Keep the visible body crouched below it while the hands pull, then stand
 # up during the horizontal crossing instead of levitating outside the lip.
 var model_y := 0.0
 if action == "climb":
  var progress := clampf(float(state.get("climb_progress",0.0)),0.0,1.0)
  var grip: Vector3 = state.get("ledge_grip",global_position+Vector3.UP)
  var physical_rise := global_position.y-(grip.y-1.88)
  var visible_rise := lerpf(0.0,0.82,smoothstep(0.0,0.60,progress)) if progress<=0.60 else lerpf(0.82,1.92,smoothstep(0.60,1.0,progress))
  model_y = visible_rise-physical_rise
 model.position.y = model_y if action == "climb" else move_toward(model.position.y,0.0,dt*18.0)
 var face := signf(float(state.get("facing",1.0)))
 if is_zero_approx(face): face = _last_facing
 if face != _last_facing:
  _yaw_from = model.rotation.y
  _yaw_target = face*(PI/2.0-0.16)
  _yaw_time = 0.0
  _yaw_duration = 0.085
  if action == "attack":
   _yaw_duration = clampf(float(state.get("attack_startup",0.08))-float(state.get("action_t",0.0)),0.025,0.085)
  _last_facing = face
  trail_points.clear()
 _yaw_time += dt
 var yaw_u := clampf(_yaw_time/_yaw_duration,0.0,1.0)
 model.rotation.y = lerp_angle(_yaw_from,_yaw_target,smoothstep(0.0,1.0,yaw_u))
 if grounded and not _was_grounded: _land_age = 0.0
 else: _land_age += dt
 _was_grounded = grounded
 var tag := action+"/"+str(weapon)+"/"+str(grounded)
 if action == "attack": tag += "/"+str(state.get("attack_id",state.get("attack_index",0)))
 if tag != _last_tag:
  blend_from = current_pose.duplicate()
  _blend_time = 0.0
  _blend_duration = 0.08
  if action == "attack": _blend_duration = 0.035 if weapon==2 else 0.045
  elif action in ["hurt","hit"]: _blend_duration = 0.025
  elif action == "dodge": _blend_duration = 0.045
  elif action in ["jump","fall"]: _blend_duration = 0.055
  _last_tag = tag
 var target := _state_pose(state,dt)
 # Natural landing is a lower-body compression over the still-running upper pose.
 if grounded and _land_age < 0.15 and action not in ["dead","hurt","dodge"]:
  var landing := _sample_pose("jump_land",_land_age*1.5)
  var amount := (1.0-_land_age/0.15)*0.35
  for i in range(target.size()):
   if upper_weights[i]<0.5:
    target[i] = (target[i] as Transform3D).interpolate_with(landing[i],amount)
 _blend_time += dt
 var blend_u := smoothstep(0.0,1.0,clampf(_blend_time/_blend_duration,0.0,1.0))
 current_pose = _mix(blend_from,target,blend_u) if blend_u<1.0 else target
 _write_pose(current_pose)
 _aim_directional_attack(state)
 _aim_charged_thrust(state)
 # The left hand follows a real support target. It never also holds a sword.
 var rope := bool(state.get("rope_connected",false))
 if rope and not grounded:
  _reach_support(state.get("rope_anchor",global_position+Vector3(0,3,0)))
 elif action == "wall":
  var wall_dir := float(state.get("wall_dir",face))
  _reach_support(global_position+Vector3(wall_dir*0.38,1.55,0.0))
 elif action in ["ledge","climb"]:
  var grip: Vector3 = state.get("ledge_grip",global_position+Vector3(face*0.30,1.88,0.0))
  var hold := 1.0
  if action == "climb":
   hold = 1.0-smoothstep(0.60,0.78,float(state.get("climb_progress",0.0)))
  _hold_ledge(grip,face,hold)
 _update_socket()
 if weapon == 1 and not rope and action not in ["wall","ledge","climb","dead"]:
  _two_bone_ik("upperarm_l","lowerarm_l","hand_l",grip_transform*Vector3(0,-0.15,0),Vector3.LEFT)
  _update_socket()
 # A new action blends from the pose actually shown, including support IK.
 # This matters when releasing a wire or leaving a wall into an attack.
 for i in range(current_pose.size()):
  current_pose[i] = Transform3D(Basis(skeleton.get_bone_pose_rotation(i)).scaled(skeleton.get_bone_pose_scale(i)),skeleton.get_bone_pose_position(i))
 weapon_node.visible = action not in ["ledge","climb"]
 var flash := 0.62 if action in ["hurt","hit"] and fmod(elapsed_safe(state),0.12)<0.045 else 0.0
 for mat in materials:
  mat.set_shader_parameter("hit_flash",flash)
  mat.set_shader_parameter("charge_glow",float(state.get("charge_ratio",0.0))*0.5 if action=="charge" else 0.0)
 _update_trail(state)

func elapsed_safe(state: Dictionary) -> float:
 return float(state.get("action_t",0.0))

func _write_pose(pose: Array) -> void:
 for i in range(pose.size()):
  var t: Transform3D = pose[i]
  skeleton.set_bone_pose_position(i,t.origin)
  skeleton.set_bone_pose_rotation(i,t.basis.orthonormalized().get_rotation_quaternion())
  skeleton.set_bone_pose_scale(i,t.basis.get_scale())
 skeleton.force_update_all_bone_transforms()

func _set_weapon(index: int) -> void:
 if index == _weapon: return
 _weapon = index
 for i in range(weapons.size()): (weapons[i]["root"] as Node3D).visible = i==index
 weapon_node = weapons[index]["root"]
 weapon_base = weapons[index]["base"]
 weapon_tip = weapons[index]["tip"]
 trail_points.clear()

func _update_socket() -> void:
 if skeleton == null or weapon_node == null: return
 var hand := int(bone_ids.get("hand_r",-1))
 if hand<0: return
 skeleton.force_update_all_bone_transforms()
 grip_transform = skeleton.global_transform*skeleton.get_bone_global_pose(hand)*grip_local
 weapon_node.global_transform = grip_transform

func get_blade_segment() -> Array[Vector3]:
 if not _loaded: return []
 _update_socket()
 return [grip_transform*weapon_base,grip_transform*weapon_tip]

func get_wire_hand() -> Vector3:
 if not _loaded or not bone_ids.has("hand_l"): return global_position+Vector3(0,1.5,0)
 return skeleton.global_transform*skeleton.get_bone_global_pose(bone_ids["hand_l"]).origin

func get_ledge_hands() -> Array[Vector3]:
 var result: Array[Vector3] = []
 if not _loaded: return result
 for name in ["hand_l","hand_r"]:
  result.append(skeleton.global_transform*skeleton.get_bone_global_pose(bone_ids[name]).origin)
 return result

func _hold_ledge(anchor_world: Vector3,face: float,weight: float) -> void:
 if weight <= 0.0: return
 for side in ["l","r"]:
  var saved: Dictionary = {}
  for prefix in ["upperarm_","lowerarm_","hand_"]:
   var id := int(bone_ids.get(prefix+side,-1))
   if id>=0: saved[id] = skeleton.get_bone_pose_rotation(id)
  var depth := -face*0.14 if side == "l" else face*0.14
  var target := anchor_world+Vector3(-face*0.025,0.015,depth)
  _two_bone_ik("upperarm_"+side,"lowerarm_"+side,"hand_"+side,target,Vector3(0,-0.5,-1))
  for id in saved:
   skeleton.set_bone_pose_rotation(id,(saved[id] as Quaternion).slerp(skeleton.get_bone_pose_rotation(id),weight))
  skeleton.force_update_all_bone_transforms()

func _aim_charged_thrust(state: Dictionary) -> void:
 if String(state.get("action","")) != "attack" or int(state.get("weapon",0)) != 2 or not bool(state.get("attack_charged",false)): return
 var elapsed := float(state.get("action_t",0.0))
 var startup := maxf(0.016,float(state.get("attack_startup",0.1)))
 var active := maxf(0.016,float(state.get("attack_active",0.2)))
 var amount := smoothstep(0.0,1.0,elapsed/startup)
 if elapsed > startup+active:
  amount *= 1.0-smoothstep(0.0,0.17,elapsed-startup-active)
 if amount <= 0.0: return
 var face := float(state.get("facing",1.0))
 _aim_right_blade(global_position+Vector3(face*0.57,1.20,0.08),Vector3(face,0.025,0.015).normalized(),amount)

func get_visual_debug() -> Dictionary:
 return {"loaded":_loaded,"clip":_current_clip,"bones":skeleton.get_bone_count() if skeleton else 0,"clips":clips.size(),"weapon":_weapon,"missing":_warned_missing.keys()}

func _reach_support(anchor_world: Vector3) -> void:
 var upper := int(bone_ids.get("upperarm_l",-1))
 if upper<0: return
 var shoulder_world := skeleton.global_transform*skeleton.get_bone_global_pose(upper).origin
 var dir := (anchor_world-shoulder_world).normalized()
 _two_bone_ik("upperarm_l","lowerarm_l","hand_l",shoulder_world+dir*0.53,Vector3(0.0,0.0,1.0))

func _aim_directional_attack(state: Dictionary) -> void:
 if String(state.get("action","")) != "attack": return
 var kind: String = state.get("attack_kind","")
 if kind not in ["up","plunge"]: return
 var elapsed := float(state.get("action_t",0.0))
 var startup := maxf(0.016,float(state.get("attack_startup",0.1)))
 var amount := smoothstep(0.15,0.95,elapsed/startup)
 if kind == "plunge" and bool(state.get("plunge_landed",false)):
  amount *= 1.0-smoothstep(0.06,0.30,float(state.get("plunge_recovery_t",0.0)))
 elif kind == "up" and String(state.get("attack_phase","")) == "recovery":
  var recovery := elapsed-startup-float(state.get("attack_active",0.06))
  amount *= 1.0-smoothstep(0.03,0.20,recovery)
 if amount <= 0.0: return
 var face := float(state.get("facing",1.0))
 var hand_target := global_position+Vector3(face*0.26,1.66,0.02) if kind == "up" else global_position+Vector3(face*0.32,0.91,0.02)
 var blade_direction := Vector3(face*0.25,0.97,0.03).normalized() if kind == "up" else Vector3(face*0.12,-0.99,0.02).normalized()
 _aim_right_blade(hand_target,blade_direction,amount)

func _aim_right_blade(hand_target: Vector3,blade_direction: Vector3,amount: float) -> void:
 var before: Dictionary = {}
 for name in ["upperarm_r","lowerarm_r","hand_r"]:
  var id: int = int(bone_ids.get(name,-1))
  if id>=0: before[id] = skeleton.get_bone_pose_rotation(id)
 _two_bone_ik("upperarm_r","lowerarm_r","hand_r",hand_target,Vector3(0,0,1))
 var hand := int(bone_ids.get("hand_r",-1))
 if hand>=0:
  var hand_global := skeleton.get_bone_global_pose(hand)
  var blade_global := skeleton.global_transform*hand_global*grip_local
  var world_delta := Quaternion((blade_global.basis*Vector3.UP).normalized(),blade_direction)
  var desired_world_basis := Basis(world_delta)*skeleton.global_transform.basis*hand_global.basis
  var parent := skeleton.get_bone_parent(hand)
  var parent_world_basis := skeleton.global_transform.basis*skeleton.get_bone_global_pose(parent).basis
  skeleton.set_bone_pose_rotation(hand,(parent_world_basis.inverse()*desired_world_basis).orthonormalized().get_rotation_quaternion())
 for id in before:
  skeleton.set_bone_pose_rotation(id,(before[id] as Quaternion).slerp(skeleton.get_bone_pose_rotation(id),amount))
 skeleton.force_update_all_bone_transforms()

func _two_bone_ik(upper_name: String,lower_name: String,end_name: String,target_world: Vector3,bend_hint: Vector3) -> void:
 var upper := int(bone_ids.get(upper_name,-1))
 var lower := int(bone_ids.get(lower_name,-1))
 var end := int(bone_ids.get(end_name,-1))
 if upper<0 or lower<0 or end<0: return
 var target := skeleton.global_transform.affine_inverse()*target_world
 var shoulder := skeleton.get_bone_global_pose(upper).origin
 var elbow := skeleton.get_bone_global_pose(lower).origin
 var hand := skeleton.get_bone_global_pose(end).origin
 var l1 := shoulder.distance_to(elbow)
 var l2 := elbow.distance_to(hand)
 if l1<0.01 or l2<0.01: return
 var direction := target-shoulder
 var distance := clampf(direction.length(),absf(l1-l2)+0.005,l1+l2-0.005)
 direction = direction.normalized()
 var bend := bend_hint-direction*direction.dot(bend_hint)
 if bend.length_squared()<0.001: bend = Vector3.RIGHT-direction*direction.dot(Vector3.RIGHT)
 bend = bend.normalized()
 var along := (distance*distance+l1*l1-l2*l2)/(2.0*distance)
 var height := sqrt(maxf(0.0,l1*l1-along*along))
 var desired_elbow := shoulder+direction*along+bend*height
 _aim_bone_at(upper,lower,desired_elbow)
 skeleton.force_update_all_bone_transforms()
 _aim_bone_at(lower,end,shoulder+direction*distance)
 skeleton.force_update_all_bone_transforms()

func _aim_bone_at(bone: int,child: int,target: Vector3) -> void:
 var global_pose := skeleton.get_bone_global_pose(bone)
 var from := skeleton.get_bone_global_pose(child).origin-global_pose.origin
 var to := target-global_pose.origin
 if from.length_squared()<0.000001 or to.length_squared()<0.000001: return
 var delta := Quaternion(from.normalized(),to.normalized())
 var desired_basis := Basis(delta)*global_pose.basis
 var parent := skeleton.get_bone_parent(bone)
 var parent_basis := skeleton.get_bone_global_pose(parent).basis if parent>=0 else Basis.IDENTITY
 var local_basis := parent_basis.inverse()*desired_basis
 skeleton.set_bone_pose_rotation(bone,local_basis.orthonormalized().get_rotation_quaternion())

func _create_trail() -> void:
 trail_node = MeshInstance3D.new()
 trail_node.name = "ActualTipTrail"
 trail_node.top_level = true
 add_child(trail_node)
 trail_node.global_transform = Transform3D.IDENTITY
 trail_material = StandardMaterial3D.new()
 trail_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
 trail_material.vertex_color_use_as_albedo = true
 trail_material.cull_mode = BaseMaterial3D.CULL_DISABLED
 trail_node.material_override = trail_material
 trail_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _update_trail(state: Dictionary) -> void:
 var active := String(state.get("action",""))=="attack" and String(state.get("attack_phase",""))=="active"
 var attack_id := int(state.get("attack_id",0))
 if not active:
  trail_points.clear()
  trail_node.visible = false
  return
 if attack_id!=_trail_attack_id:
  _trail_attack_id = attack_id
  trail_points.clear()
 var tip := grip_transform*weapon_tip
 tip.z = maxf(tip.z,0.26)
 if not trail_points.is_empty() and tip.distance_to(trail_points.back())>1.8: trail_points.clear()
 if trail_points.is_empty() or tip.distance_to(trail_points.back())>0.004: trail_points.append(tip)
 var piercing := _weapon==2 and bool(state.get("attack_charged",false))
 while trail_points.size()>(7 if piercing else 4): trail_points.pop_front()
 if trail_points.size()<2: return
 var st := SurfaceTool.new()
 st.begin(Mesh.PRIMITIVE_TRIANGLES)
 var width := 0.035 if _weapon==1 else 0.020 if _weapon==0 else 0.021 if piercing else 0.012
 var body := Color("e5a950") if _weapon==1 else Color("b0f3ed") if piercing else Color("78d3dc")
 for i in range(trail_points.size()-1):
  var a := trail_points[i]
  var b := trail_points[i+1]
  var direction := Vector2(b.x-a.x,b.y-a.y)
  if direction.length()<0.002: continue
  var n := Vector3(-direction.y,direction.x,0).normalized()
  var w0 := width*pow(float(i)/float(trail_points.size()-1),0.7)
  var w1 := width*pow(float(i+1)/float(trail_points.size()-1),0.7)
  _trail_quad(st,a+n*w0,b+n*w1,b-n*w1,a-n*w0,body)
  var shift := Vector3(0,0,0.002)
  _trail_quad(st,a+n*w0*.28+shift,b+n*w1*.28+shift,b-n*w1*.28+shift,a-n*w0*.28+shift,Color("fff3cb"))
 trail_node.mesh = st.commit()
 trail_node.visible = true

func _trail_quad(st: SurfaceTool,a: Vector3,b: Vector3,c: Vector3,d: Vector3,color: Color) -> void:
 st.set_color(color)
 for v in [a,b,c,a,c,d]: st.add_vertex(v)
