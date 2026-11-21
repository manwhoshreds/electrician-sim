class_name CharacterModel
extends Node3D
## A person from the City Folks pack (Alstra Infinite, in res://GLB/), posed
## and moved by hand: the models come rigged but with no animations. Arms
## down at the sides, breathing, walking (legs and arms swinging), waving,
## and sitting. Faces +Z, feet on the origin, like the rest of the game.
##
## How it moves: each frame every controlled bone gets a turn in the model's
## own space (around its joint), on top of its rest pose; a child carries its
## parent's turn. That keeps the numbers readable ("swing the thigh forward
## 25 degrees") whatever way the rig's bones happen to point.

const MODELS: Array[String] = [
	"res://GLB/Deportista/Deportista_CityFolks_PolyMate.glb",
	"res://GLB/Dough Sensei/DoughSensei_CityFolks_PolyMate.glb",
	"res://GLB/Muscle Man/MuscleMan_CityFolks_PolyMate.glb",
	"res://GLB/Padel Player/PadelPlayer_CityFolks_PolyMate.glb",
]
## Which way each arm hangs, at rest by their side: down, a little out, a touch forward.
const ARM_DOWN := {"l": Vector3(0.14, -1.0, 0.04), "r": Vector3(-0.14, -1.0, 0.04)}
const WAVE_UP := Vector3(-0.55, 0.82, 0.18)    # the right arm, up and out
## The bones it moves, by what they are, and their names in the rig.
const BONES := {"spine": "spine_02.x", "head": "head.x", "arm.l": "arm_stretch.l", "arm.r": "arm_stretch.r",
	"forearm.l": "forearm_stretch.l", "forearm.r": "forearm_stretch.r", "hand.l": "hand.l", "hand.r": "hand.r",
	"thigh.l": "thigh_stretch.l", "thigh.r": "thigh_stretch.r", "shin.l": "leg_stretch.l", "shin.r": "leg_stretch.r"}

## 0 standing, 1 walking at full stride.
var walking := 0.0
## How fast they're walking, metres a second, for the length of stride.
var speed := 1.1
var waving := false
var sitting := false

var skeleton: Skeleton3D
var _bones := {}                 # "arm.l" -> bone index
var _rest := {}                  # bone index -> its rest basis in the model
var _arm_down := {}              # "l"/"r" -> the turn that drops that arm to their side
var _arm_up: Quaternion          # the turn that raises the right arm to wave
var _phase := 0.0
var _t := 0.0


## Builds model number `which` (0 to 3) from MODELS.
func setup(which: int) -> void:
	var model := (load(MODELS[posmod(which, MODELS.size())]) as PackedScene).instantiate() as Node3D
	add_child(model)
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	for key: String in BONES:
		_bones[key] = skeleton.find_bone(BONES[key])
	for i in skeleton.get_bone_count():
		_rest[i] = skeleton.get_bone_global_rest(i).basis.orthonormalized()
	for side in ["l", "r"]:
		_arm_down[side] = Quaternion(_dir("arm." + side, "forearm." + side), ARM_DOWN[side].normalized())
	_arm_up = Quaternion(_dir("arm.r", "forearm.r"), WAVE_UP.normalized())
	_apply()


## Which way a bone points at rest (from its joint to the next one), in the model.
func _dir(from: String, to: String) -> Vector3:
	return (skeleton.get_bone_global_rest(_bones[to]).origin - skeleton.get_bone_global_rest(_bones[from]).origin).normalized()


func _process(delta: float) -> void:
	if skeleton == null:
		return
	_t += delta
	_phase += delta * TAU * speed / 1.25 * walking   # one full stride (two steps) every 1.25 m
	_apply()


## A turn about the model's sideways axis: positive swings a hanging limb backward.
static func _swing(angle: float) -> Quaternion:
	return Quaternion(Vector3.RIGHT, angle)


func _apply() -> void:
	var turn := {}               # bone index -> its own turn, in the model's space
	var stride := sin(_phase) * walking
	var breathe := sin(_t * 1.6) * 0.012
	turn[_bones["spine"]] = _swing(-breathe)
	for side in ["l", "r"]:
		var s := 1.0 if side == "l" else -1.0
		# Legs: swing from the hip, the knee bending as the leg comes through.
		var hip := -0.42 * stride * s
		var knee := maxf(0.0, cos(_phase) * s) * 0.6 * walking   # bent while it swings forward under them
		if sitting:
			hip = -1.45
			knee = 1.45
		turn[_bones["thigh." + side]] = _swing(hip)
		turn[_bones["shin." + side]] = _swing(knee)
		# Arms: down by their sides, swinging against the legs, elbows soft.
		var arm: Quaternion = _swing(0.32 * stride * s) * _arm_down[side]
		var elbow := _swing(-0.2 - 0.15 * walking)
		if side == "r" and waving and not sitting:
			arm = Quaternion(Vector3.BACK, sin(_t * 7.0) * 0.32) * _arm_up
			elbow = Quaternion(Vector3.BACK, -0.5)
		if sitting:
			arm = _swing(-0.25) * _arm_down[side]       # hands resting on their knees
			elbow = _swing(-0.6)
		turn[_bones["arm." + side]] = arm
		turn[_bones["forearm." + side]] = elbow
	var whole := {}              # bone index -> its turn with all its parents' turns
	for i: int in turn:
		var q: Quaternion = turn[i]
		var p := skeleton.get_bone_parent(i)
		while p >= 0:
			if turn.has(p):
				q = q * turn[p]
			p = skeleton.get_bone_parent(p)
		whole[i] = q
	for i: int in turn:
		var p := skeleton.get_bone_parent(i)
		var parent_turn := Quaternion.IDENTITY
		var a := p
		while a >= 0:            # the nearest turned ancestor carries every turn above it
			if whole.has(a):
				parent_turn = whole[a]
				break
			a = skeleton.get_bone_parent(a)
		var parent_basis: Basis = Basis(parent_turn) * (_rest[p] as Basis) if p >= 0 else Basis.IDENTITY
		var mine: Basis = Basis(whole[i] as Quaternion) * (_rest[i] as Basis)
		skeleton.set_bone_pose_rotation(i, (parent_basis.inverse() * mine).get_rotation_quaternion())
