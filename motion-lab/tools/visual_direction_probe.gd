extends SceneTree
func _initialize() -> void:
 call_deferred("go")
func go() -> void:
 var visual = load("res://scripts/hero_visual.gd").new()
 root.add_child(visual)
 await process_frame
 var started := Time.get_ticks_usec()
 for w in range(3):
  for face in [-1.0,1.0]:
   for kind in ["up","plunge"]:
    var s := {"weapon":w,"action":"attack","facing":face,"grounded":false,"velocity":Vector3.ZERO,"action_t":1.5,"attack_startup":0.1,"attack_active":0.066,"attack_total":0.5,"attack_kind":kind,"attack_index":0,"attack_id":w*100+int(face)*10+int(kind=="up"),"attack_phase":"active"}
    for i in range(24): visual.update_state(s,1.0/60.0)
    var seg: Array = visual.get_blade_segment()
    var dir: Vector3 = (seg[1]-seg[0]).normalized()
    assert(dir.y > 0.94 if kind=="up" else dir.y < -0.95)
    print("DIRECTION ",w," ",face," ",kind," ",dir)
 for w in range(3):
  var benchmark_start := Time.get_ticks_usec()
  var s := {"weapon":w,"action":"move","facing":1.0,"grounded":true,"velocity":Vector3(5.8,0,0)}
  for i in range(600): visual.update_state(s,1.0/60.0)
  print("UPDATE_MICROSECONDS weapon ",w,": ",(Time.get_ticks_usec()-benchmark_start)/600.0)
 print("PASS directional blade poses; total ms ",(Time.get_ticks_usec()-started)/1000.0)
 quit()
