import bpy,json
from pathlib import Path
from mathutils import Matrix
root=Path(__file__).resolve().parents[1]
bpy.ops.wm.open_mainfile(filepath=str(root.parent/'motion_review_v04/hero_asset.blend'))
rig=bpy.data.objects.get('HeroB_AuthoredRig')
C=Matrix(((1,0,0,0),(0,0,1,0),(0,-1,0,0),(0,0,0,1)))
result={}
for side in ['r','l']:
 mat=C@rig.matrix_world@rig.data.bones['hand_'+side].matrix_local@Matrix.Translation((0,.075,0))@C.inverted()
 result[side]=[list(row) for row in mat]
(root/'assets/socket_world_rest.json').write_text(json.dumps(result,indent=2))
print(result)
