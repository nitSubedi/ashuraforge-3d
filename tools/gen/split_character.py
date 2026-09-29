"""Headless Blender: split a skinned Mixamo character into body-region meshes
(head/torso/hips/arms/legs) by dominant bone weight, drop the armature, and
export a GLB of static limb meshes in bind pose. Used to build a dismemberable
enemy from the same Mixamo mesh as the hero.

Usage: blender --background --python split_character.py -- in.fbx out.glb
"""
import bpy
import sys

argv = sys.argv[sys.argv.index("--") + 1:]
inp, outp = argv[0], argv[1]

REGIONS = ["head", "torso", "hips", "arm_l", "arm_r", "leg_l", "leg_r"]


def region_of(bone: str) -> str:
	if any(k in bone for k in ["Head", "Neck", "Eye"]):
		return "head"
	if "Hips" in bone:
		return "hips"
	if "Spine" in bone or "Shoulder" in bone or "Chest" in bone:
		return "torso"
	if "LeftHand" in bone or "LeftForeArm" in bone or "LeftArm" in bone:
		return "arm_l"
	if "RightHand" in bone or "RightForeArm" in bone or "RightArm" in bone:
		return "arm_r"
	if any(k in bone for k in ["LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToe"]):
		return "leg_l"
	if any(k in bone for k in ["RightUpLeg", "RightLeg", "RightFoot", "RightToe"]):
		return "leg_r"
	return "torso"


bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=inp, global_scale=0.01)  # Mixamo cm -> m

meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
# Join all skinned meshes into one so each region becomes a single part.
if len(meshes) > 1:
	bpy.ops.object.select_all(action="DESELECT")
	for o in meshes:
		o.select_set(True)
	bpy.context.view_layer.objects.active = meshes[0]
	bpy.ops.object.join()
	meshes = [bpy.context.view_layer.objects.active]

for obj in meshes:
	me = obj.data
	me.materials.clear()
	idx = {}
	for i, r in enumerate(REGIONS):
		me.materials.append(bpy.data.materials.new(r))
		idx[r] = i
	grp_region = {vg.index: region_of(vg.name) for vg in obj.vertex_groups}
	vert_region = []
	for v in me.vertices:
		bw, br = -1.0, "torso"
		for g in v.groups:
			if g.group in grp_region and g.weight > bw:
				bw, br = g.weight, grp_region[g.group]
		vert_region.append(br)
	for poly in me.polygons:
		counts = {}
		for vi in poly.vertices:
			r = vert_region[vi]
			counts[r] = counts.get(r, 0) + 1
		poly.material_index = idx[max(counts, key=counts.get)]

# Separate each mesh by material -> one object per region.
bpy.ops.object.select_all(action="DESELECT")
for obj in meshes:
	bpy.context.view_layer.objects.active = obj
	obj.select_set(True)
	bpy.ops.object.mode_set(mode="EDIT")
	bpy.ops.mesh.select_all(action="SELECT")
	bpy.ops.mesh.separate(type="MATERIAL")
	bpy.ops.object.mode_set(mode="OBJECT")
	obj.select_set(False)

# KEEP the armature + skin weights so each region is a skinned limb sharing one
# skeleton (animates together; we hide a limb to dismember). Just rename by region.
for o in list(bpy.context.scene.objects):
	if o.type == "MESH" and o.data.materials and o.data.materials[0]:
		o.name = o.data.materials[0].name

bpy.ops.export_scene.gltf(filepath=outp, export_format="GLB")
print("WROTE", outp, "meshes:", [o.name for o in bpy.context.scene.objects if o.type == "MESH"])
