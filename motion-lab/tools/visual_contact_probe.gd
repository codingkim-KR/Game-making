extends SceneTree
func _initialize(): call_deferred("go")
func go():
 var v = load("res://scripts/hero_visual.gd").new()
 root.add_child(v)
 await process_frame
 var results = []
 for w in range(3):
  for idx in range(4 if w>0 else 3):
   var s = {"weapon":w,"action":"attack","facing":1.0,"grounded":true,"velocity":Vector3.ZERO,"action_t":0.13,"attack_startup":0.1,"attack_active":0.066,"attack_total":0.5,"attack_kind":"ground","attack_index":idx,"attack_id":w*10+idx,"attack_phase":"active"}
   for f in range(10):v.update_state(s,1.0/60)
   var seg=v.get_blade_segment()
   results.append({"w":w,"idx":idx,"base":str(seg[0]),"tip":str(seg[1]),"grip":str(v.grip_local)})
 print(JSON.stringify(results,"  "))
 quit()
