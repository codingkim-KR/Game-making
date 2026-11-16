extends SceneTree
func _initialize() -> void:
 call_deferred("go")
func go() -> void:
 var world := Node3D.new()
 root.add_child(world)
 var visual = load("res://scripts/hero_visual.gd").new()
 world.add_child(visual)
 await process_frame
 print("VISUAL DEBUG ",visual.get_visual_debug())
 var results: Array = []
 for w in range(3):
  for action in ["idle","move","jump","fall","attack","charge","wall","rope","dodge","guard","hurt","dead"]:
   var s := {"weapon":w,"action":action,"facing":1.0,"grounded":action in ["idle","move","attack","charge","guard","hurt","dead"],"velocity":Vector3(1.1,3,0) if action=="move" else Vector3.ZERO,"action_t":0.1,"attack_startup":0.1,"attack_active":0.066,"attack_total":0.5,"attack_kind":"ground","attack_index":0,"attack_id":w*10,"attack_phase":"active","charge_ratio":0.7,"rope_connected":action=="rope","rope_taut":action=="rope","rope_anchor":Vector3(2,4,0),"wall_dir":1.0}
   for i in range(12): visual.update_state(s,1.0/60.0)
   var seg: Array = visual.get_blade_segment()
   results.append({"weapon":w,"action":action,"base":str(seg[0]),"tip":str(seg[1])})
 print(JSON.stringify(results))
 print("VISUAL FINAL ",visual.get_visual_debug())
 quit()
