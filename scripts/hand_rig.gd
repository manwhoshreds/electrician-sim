class_name HandRig
extends Node3D
## A real rigged human hand with a work glove on it. The origin is the wrist,
## fingers point along -Z and the back of the hand faces +Y. Poses are finger
## curl angles, and it eases between them.

const FINGERS := ["index-finger", "middle-finger", "ring-finger", "pinky-finger"]
const POSES := {
	"relaxed": {"fingers": [[0.25, 0.3, 0.2], [0.3, 0.35, 0.2], [0.35, 0.35, 0.25], [0.4, 0.4, 0.25]], "thumb": [0.1, 0.15, 0.1]},
	"point": {"fingers": [[0.08, 0.1, 0.05], [1.25, 1.45, 0.9], [1.3, 1.5, 0.9], [1.35, 1.5, 0.9]], "thumb": [0.35, 0.5, 0.4]},
	"pinch": {"fingers": [[0.72, 0.72, 0.4], [0.9, 0.95, 0.5], [1.15, 1.2, 0.7], [1.25, 1.3, 0.8]], "thumb": [0.55, 0.35, 0.3]},
	"fist": {"fingers": [[1.0, 1.15, 0.7], [1.05, 1.2, 0.75], [1.1, 1.25, 0.75], [1.15, 1.25, 0.75]], "thumb": [0.5, 0.6, 0.45]},
	"wrap": {"fingers": [[0.5, 1.0, 0.65], [0.55, 1.05, 0.65], [0.6, 1.05, 0.65], [0.7, 1.05, 0.6]], "thumb": [0.2, 0.3, 0.25]},
}

var is_right := true
var material: Material

static var _skin: StandardMaterial3D


## Your hands: light skin, a little soft light through it like real skin.
static func skin_material() -> StandardMaterial3D:
	if _skin == null:
		_skin = StandardMaterial3D.new()
		_skin.albedo_color = Color(0.93, 0.76, 0.65)
		_skin.roughness = 0.55
		_skin.subsurf_scatter_enabled = true
		_skin.subsurf_scatter_strength = 0.35
		_skin.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _skin

var _skeleton: Skeleton3D
var _model: Node3D
var _hinge := {}                 # bone index -> the axis it curls round
var _chains: Array = []          # each digit's bones, knuckle to tip, as bone indexes
var _current := {}               # bone index -> angle now
var _target := {}                # bone index -> angle wanted


func _ready() -> void:
	_model = (load("res://assets/hands/%s.glb" % ("right" if is_right else "left")) as PackedScene).instantiate()
	add_child(_model)
	_skeleton = _model.find_children("*", "Skeleton3D", true, false)[0]
	for mi: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		mi.material_override = material
	# Sit the model so its wrist bone is exactly at this node's origin.
	var wrist := _model.global_transform.affine_inverse() * _skeleton.global_transform * _skeleton.get_bone_global_rest(_skeleton.find_bone("wrist"))
	_model.transform = wrist.affine_inverse()
	_find_hinges()
	set_pose("relaxed", true)


## Work out from the shape of the hand which way "curl" is: fingers bend toward
## the palm, the thumb toward the base of the middle finger.
func _find_hinges() -> void:
	var palm_side := -_skeleton.get_bone_global_rest(_skeleton.find_bone("wrist")).basis.y
	for f: String in FINGERS:
		_add_chain([f + "-phalanx-proximal", f + "-phalanx-intermediate", f + "-phalanx-distal", f + "-tip"], palm_side, false)
	var toward := _rest_origin("middle-finger-phalanx-proximal") - _rest_origin("thumb-metacarpal") + palm_side * 0.06
	_add_chain(["thumb-metacarpal", "thumb-phalanx-proximal", "thumb-phalanx-distal", "thumb-tip"], toward, true)


func _add_chain(names: Array, toward: Vector3, _thumb: bool) -> void:
	var chain: Array[int] = []
	for j in names.size():
		var i := _skeleton.find_bone(names[j])
		chain.append(i)
		if j < names.size() - 1:
			_hinge[i] = (_rest_origin(names[j + 1]) - _rest_origin(names[j])).cross(toward).normalized()
	_chains.append(chain)


func _rest_origin(bone: String) -> Vector3:
	return _skeleton.get_bone_global_rest(_skeleton.find_bone(bone)).origin


func set_pose(pose_name: String, instantly := false) -> void:
	var p: Dictionary = POSES[pose_name]
	for f in FINGERS.size():
		var names := ["%s-phalanx-proximal", "%s-phalanx-intermediate", "%s-phalanx-distal"]
		for j in 3:
			_aim(names[j] % FINGERS[f], p["fingers"][f][j])
	_aim("thumb-metacarpal", p["thumb"][0])
	_aim("thumb-phalanx-proximal", p["thumb"][1])
	_aim("thumb-phalanx-distal", p["thumb"][2])
	if instantly:
		_current = _target.duplicate()
		_apply()


func _aim(bone: String, angle: float) -> void:
	var i := _skeleton.find_bone(bone)
	_target[i] = angle
	if not _current.has(i):
		_current[i] = angle


func _process(delta: float) -> void:
	for i: int in _target:
		_current[i] = lerpf(_current[i], _target[i], minf(1.0, delta * 14.0))
	_apply()


## This rig's finger bones aren't parented to each other, so each digit is
## walked from knuckle to tip here: every segment inherits the bend before it.
func _apply() -> void:
	var posed := {}
	for chain: Array in _chains:
		var bend := Quaternion.IDENTITY
		var at := _skeleton.get_bone_global_rest(chain[0]).origin
		for j in chain.size():
			var i: int = chain[j]
			var rest := _skeleton.get_bone_global_rest(i)
			if j > 0:
				at += bend * (rest.origin - _skeleton.get_bone_global_rest(chain[j - 1]).origin)
			if _hinge.has(i) and _current.has(i):
				bend = Quaternion(bend * (_hinge[i] as Vector3), _current[i]) * bend
			var world := Transform3D(Basis(bend) * rest.basis, at)
			posed[i] = world
			var parent := _skeleton.get_bone_parent(i)
			var parent_world := Transform3D.IDENTITY     # most of this rig's bones have no parent
			if posed.has(parent):
				parent_world = posed[parent]
			elif parent >= 0:
				parent_world = _skeleton.get_bone_global_rest(parent)
			var local := parent_world.affine_inverse() * world
			_skeleton.set_bone_pose_position(i, local.origin)
			_skeleton.set_bone_pose_rotation(i, local.basis.get_rotation_quaternion())


## Where a joint is right now, in this node's space.
func joint(bone: String) -> Vector3:
	_skeleton.force_update_all_bone_transforms()
	var world := _skeleton.global_transform * _skeleton.get_bone_global_pose(_skeleton.find_bone(bone)).origin
	return global_transform.affine_inverse() * world
