class_name Interactable
extends Node3D
## Something in the world you can walk up to and press E on. You get it by
## looking at it (see Player): `aim` is where on it the crosshair goes, and
## `aim_radius` roughly how big it is, so anywhere on it counts.

var prompt := ""
var reach := 2.5                 # metres, measured along the ground
var active := true
var on_use: Callable             # called with the player
var alt_prompt := ""             # a second thing you can do with it, on F
var on_alt: Callable
var facing := Vector3.ZERO       # if set, only usable from this side of it (local direction), not through a wall
var height_range := Vector2(-INF, INF)   # how far above (+) or below (-) it your feet can be: keeps the attic and the rooms apart
var aim := Vector3.ZERO          # the middle of the thing you look at, from aim_target's origin (in its own space)
var aim_target: Node3D = null    # what you look at, if it isn't this node (a model that slides out, say)
var aim_radius := 0.2            # roughly how big it is, in metres


func _ready() -> void:
	add_to_group("interactables")


func can_use(p: Node3D) -> bool:
	if not active:
		return false
	var d := p.global_position - global_position
	if d.y < height_range.x or d.y > height_range.y:
		return false
	d.y = 0.0
	if facing != Vector3.ZERO and d.dot(global_basis * facing) < 0.0:
		return false
	return d.length() < reach


## Where the crosshair goes on it, in the world.
func aim_point() -> Vector3:
	var base: Node3D = aim_target if aim_target != null else self
	return base.global_transform * aim


func use(p: Node3D) -> void:
	on_use.call(p)
