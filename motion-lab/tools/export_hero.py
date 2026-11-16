"""Export the accepted v04 skinned hero and authored CC0 motions for Godot.
Run: blender -b --python tools/export_hero.py (from any directory).
No generated raster imagery is used. Authored source animations are sampled at60fps.
"""
import bpy,sys,math,json
from pathlib import Path
from mathutils import Vector,Quaternion,Matrix
ROOT=Path(__file__).resolve().parents[1]
SRC=ROOT.parent/'motion_review_v04'
sys.path.insert(0,str(SRC))
from hero_asset import build_hero
from motion_pipeline import import_reference,cache_action,pose_at,apply_pose,blend_pose
from retarget_dual import retarget_sample,SOURCE as KAYKIT
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
hero=build_hero();rig=hero['armature'];rig.rotation_mode='QUATERNION';rig.rotation_quaternion=Quaternion();rig.location=(0,0,0)
refs=[];clips={};provenance={};FPS=60
specs=[('universal-animation-library','UAL1_Standard.glb',{'Idle_Loop':'idle','Sword_Idle':'sword_idle','Walk_Loop':'walk','Jog_Fwd_Loop':'run','Sprint_Loop':'sprint','Jump_Start':'jump_start','Jump_Loop':'jump_loop','Jump_Land':'jump_land','Roll':'roll','Hit_Chest':'hit','Hit_Head':'hit_head','Death01':'death','Interact':'interact','Crouch_Idle_Loop':'crouch'}),('universal-animation-library-2','UAL2_Standard.glb',{'Sword_Regular_Combo':'sword_combo','Sword_Heavy_Combo':'great_combo','Sword_Regular_A':'sword_a','Sword_Regular_A_Rec':'sword_a_recover','Sword_Regular_B':'sword_b','Sword_Regular_B_Rec':'sword_b_recover','Sword_Regular_C':'sword_c','Sword_Block':'guard','ClimbUp_1m':'climb','Hit_Knockback':'hit_heavy','Sword_Dash':'sword_dash','Slide_Loop':'slide','Consume':'consume'})]
for folder,filename,mapping in specs:
 path=next((SRC/'external'/folder).rglob(filename));source,actions,objects=import_reference(path);refs+=objects
 for wanted,name in mapping.items():
  action=next(a for a in actions if a.name.startswith(wanted+'_'))
  clips[name]=cache_action(source,action,FPS);provenance[name]={'author':'Quaternius','pack':folder,'source_clip':wanted,'license':'CC0'}
  print('CACHE',name,clips[name]['duration'],flush=True)
 source.animation_data_clear()
# Restore scene frame rate before constructing target actions.
bpy.context.scene.render.fps=FPS
# Split actual source combo segments using contact times audited in v04.
segments={'sword':[(0,.82,.249166667),(.82,1.43,1.245833333),(1.43,2.24,1.571666667)],'great':[(0,.82,.5075),(.82,1.46,1.1375),(1.46,2.13,1.785),(2.13,3.65,2.625)]}
hits={}
for prefix,parts in segments.items():
 source=clips[prefix+'_combo']
 for index,(start,end,hit) in enumerate(parts,1):
  end=min(end,source['duration']);duration=end-start
  poses=[pose_at(source,start+min(i/FPS,duration)) for i in range(round(duration*FPS)+1)]
  name=f'{prefix}_{index}';clips[name]={'duration':duration,'fps':FPS,'poses':poses};hits[name]=hit-start
  provenance[name]={**provenance[prefix+'_combo'],'source_start':start,'source_end':end,'source_contact':hit}
# Dedicated one-handed rapier thrusts: authored stab retarget, not dual wield reuse.
source,actions,objects=import_reference(KAYKIT);refs+=objects
act=next(a for a in actions if a.name.startswith('1H_Melee_Attack_Stab'))
kay=cache_action(source,act,FPS);source.animation_data_clear()
grip=pose_at(clips['sword_idle'],0)
baseposes=[retarget_sample(rig,kay['rest'],g,l,grip) for g,l in zip(kay['matrices'],kay['poses'])]
# Fix ground penetration without changing limb lengths. All rapier variations
# retain the authored leg/arm sequence; only intent height/stance is adjusted.
def copied(p):return {n:tuple(v.copy() for v in vals) for n,vals in p.items()}
def capture():return {b.name:(b.location.copy(),b.rotation_quaternion.copy(),b.scale.copy()) for b in rig.pose.bones}
for index in range(1,5):
 poses=[]
 for i,base in enumerate(baseposes):
  p=copied(base);u=i/max(1,len(baseposes)-1);weight=math.sin(math.pi*u)**2
  apply_pose(rig,p);bpy.context.view_layer.update()
  # Change thrust line by rotating upper arm in character/world pitch plane.
  angle={1:0,2:-.12,3:.12,4:.035}[index]*weight
  bone=rig.pose.bones['upperarm_r'];pivot=bone.head.copy()
  bone.matrix=Matrix.Translation(pivot)@Quaternion((1,0,0),angle).to_matrix().to_4x4()@Matrix.Translation(-pivot)@bone.matrix
  bpy.context.view_layer.update()
  # Fourth thrust has a deeper, still anatomically authored crouch/lunge stance.
  if index==4:
   pelvis=rig.pose.bones['pelvis'];mat=pelvis.matrix.copy();mat.translation.z-=.045*weight;pelvis.matrix=mat
   bpy.context.view_layer.update()
  p=capture()
  bias=min((rig.pose.bones[n].head.z-rig.data.bones[n].head_local.z) for n in ['ball_l','ball_r','foot_l','foot_r'])
  loc,q,sc=p['root'];p['root']=(loc+rig.data.bones['root'].matrix_local.to_quaternion().inverted()@Vector((0,0,-bias)),q,sc)
  poses.append(p)
 name=f'rapier_{index}';clips[name]={'duration':kay['duration'],'fps':FPS,'poses':poses};provenance[name]={'author':'Kay Lousberg / KayKit','pack':'Character Pack Adventures1.0','source_clip':'1H_Melee_Attack_Stab','license':'CC0','retarget':'global rest-space orientation; fixed human bone lengths','variant':index}
# Determine maximal extension along original forward -Y for clip timewarp.
for index in range(1,5):
 name=f'rapier_{index}';forward=[]
 for p in clips[name]['poses']:
  apply_pose(rig,p);bpy.context.view_layer.update()
  hand=rig.pose.bones['hand_r'].matrix;tip=hand@Vector((0,.075,.90));forward.append(-tip.y)
 peak=max(range(len(forward)),key=lambda i:forward[i]);hits[name]=peak/FPS
 print('RAPIER EXTENSION PEAK',name,hits[name],max(forward),flush=True)
 hits[name]=26/FPS # Actual forward extension onset/contact, not later extension peak
# Idle at start of stab uses target gripping fingers, fixed both feet ground.
idleposes=[copied(clips['rapier_1']['poses'][0]) for _ in range(61)]
clips['rapier_idle']={'duration':1.,'fps':FPS,'poses':idleposes};provenance['rapier_idle']={**provenance['rapier_1'],'variant':'ready pose'}
# Remove imported reference objects and all nonhero actions. Target actions are
# baked separately so glTF contains no hidden mannequins or reference skeletons.
for ob in refs:
 if ob.name in bpy.data.objects:bpy.data.objects.remove(ob,do_unlink=True)
for action in list(bpy.data.actions):bpy.data.actions.remove(action)
rig.animation_data_clear();rig.animation_data_create()
scene=bpy.context.scene;scene.render.fps=FPS
for name,clip in clips.items():
 action=bpy.data.actions.new(name);action.use_fake_user=True;rig.animation_data.action=action
 for i,p in enumerate(clip['poses']):
  apply_pose(rig,p)
  for b in rig.pose.bones:
   b.keyframe_insert('rotation_quaternion',frame=i)
   # Source local translations include pelvis/leg squash. Preserve them exactly.
   b.keyframe_insert('location',frame=i)
 for fc in action.fcurves:
  for kp in fc.keyframe_points:kp.interpolation='LINEAR'
 print('BAKE',name,len(clip['poses']),flush=True)
rig.animation_data.action=None
apply_pose(rig,pose_at(clips['idle'],0));bpy.context.view_layer.update()
# Select only real hero mesh and its skin; glTF coordinate transform is standard.
bpy.ops.object.select_all(action='DESELECT')
for o in hero['objects']:o.select_set(True)
bpy.context.view_layer.objects.active=rig
scene.frame_start=0;scene.frame_end=60
out=ROOT/'assets/hero.glb'
bpy.ops.export_scene.gltf(filepath=str(out),export_format='GLB',use_selection=True,export_animations=True,export_animation_mode='ACTIONS',export_frame_range=False,export_force_sampling=True,export_optimize_animation_size=True,export_anim_single_armature=True,export_skins=True,export_morph=False,export_materials='EXPORT',export_cameras=False,export_lights=False,export_yup=True)
manifest={'height':1.84,'native_forward_godot':'+Z','native_forward_blender':'-Y','mesh_count':len(hero['meshes']),'bones':[b.name for b in rig.data.bones],'clips':{},'socket':{'bone':'hand_r','blender_hand_local_grip':[0,.075,0],'blender_blade_axis':[0,0,1],'note':'Godot imported local bone axes require verification; see GodotProbe output'},'source':'Quaternius CC0 model/UAL, KayKit CC0 rapier authored stab','fps':60,'gltf_bytes':out.stat().st_size}
for name,clip in clips.items():manifest['clips'][name]={'duration':(len(clip['poses'])-1)/FPS,'contact_time':hits.get(name),'loop':name in ['idle','sword_idle','walk','run','sprint','jump_loop','crouch','slide','rapier_idle'],'provenance':provenance.get(name)}
for i in range(1,5):
 manifest['clips'][f'rapier_{i}']['active_window']=[21/FPS,31/FPS]
 manifest['clips'][f'rapier_{i}']['ready_time']=0
manifest['godot_animation_aliases']={'jump_loop':'jump'}
(ROOT/'assets/hero_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2))
print('EXPORTED',out,out.stat().st_size,flush=True)
