"""Preserve v04 weapon socket through Blender->glTF coordinate conversion.
Patch named child markers into a GLB using exported rest-space matrices.
Run after export_hero.py and export_socket_math.py.
"""
from pathlib import Path
import json,struct,numpy as np
B=Path(__file__).resolve().parents[1];p=B/'assets/hero.glb';raw=p.read_bytes();n,typ=struct.unpack_from('<II',raw,12);doc=json.loads(raw[20:20+n]);binary=raw[20+n:]
parents={ch:i for i,node in enumerate(doc['nodes']) for ch in node.get('children',[])}
def local(n):
 if 'matrix' in n:return np.array(n['matrix']).reshape(4,4).T
 x,y,z,w=n.get('rotation',[0,0,0,1]);m=np.eye(4)
 m[:3,:3]=np.array([[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)],[2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)],[2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)]])@np.diag(n.get('scale',[1,1,1]));m[:3,3]=n.get('translation',[0,0,0]);return m
def world(i):return (world(parents[i]) if i in parents else np.eye(4))@local(doc['nodes'][i])
rest=json.loads((B/'assets/socket_world_rest.json').read_text());sockets={}
for side in ['r','l']:
 name='Grip'+side.upper();idx=next(i for i,x in enumerate(doc['nodes']) if x.get('name')=='hand_'+side)
 matrix=np.linalg.inv(world(idx))@np.array(rest[side]);new=len(doc['nodes'])
 doc['nodes'].append({'name':name,'matrix':matrix.T.flatten().tolist(),'children':[new+1]});doc['nodes'].append({'name':'GripTip'+side.upper(),'translation':[0,1,0]});doc['nodes'][idx].setdefault('children',[]).append(new);sockets[side]={'matrix':matrix.tolist(),'marker':name,'tip_marker':'GripTip'+side.upper(),'blade_axis_local':[0,1,0],'hand_bone':'hand_'+side}
text=json.dumps(doc,separators=(',',':')).encode();text+=b' '*((-len(text))%4);out=struct.pack('<III',0x46546c67,2,12+8+len(text)+len(binary))+struct.pack('<II',len(text),0x4e4f534a)+text+binary;p.write_bytes(out)
mp=B/'assets/hero_manifest.json';m=json.loads(mp.read_text());m['socket_markers']=sockets;m['gltf_bytes']=len(out);mp.write_text(json.dumps(m,ensure_ascii=False,indent=2));print(json.dumps(sockets,indent=2))
