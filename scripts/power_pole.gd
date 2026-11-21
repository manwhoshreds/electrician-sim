class_name PowerPole
extends RigidBody3D
## A wooden utility pole. Solid as a rock until the van hits it or you sprint
## into it, then it comes loose and goes over in the direction you were moving.
## Its origin is the middle of the pole.

signal knocked_down

const HEIGHT := 9.0
const RADIUS := 0.17
const VAN_MIN_SPEED := 2.5          # m/s, about 9 km/h
const RUN_MIN_SPEED := 6.0          # faster than walking, so only a sprint does it
const HIT_REACH := 0.55             # noticed a little before contact, so nothing stops dead on it
const VAN_SPEED_KEPT := 0.85

var fallen := false

var _hit_zone: Area3D


func _ready() -> void:
	mass = 300.0
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	freeze = true
	var col := CollisionShape3D.new()
	col.shape = _capsule(RADIUS)   # a cylinder's flat foot balances on the ground and won't go over
	add_child(col)
	_hit_zone = Area3D.new()
	var zone := CollisionShape3D.new()
	zone.shape = _capsule(HIT_REACH)
	_hit_zone.add_child(zone)
	add_child(_hit_zone)


func _physics_process(_delta: float) -> void:
	for body in _hit_zone.get_overlapping_bodies():
		var hit := _impact_velocity(body)
		if hit != Vector3.ZERO:
			_topple(hit, body)
			return


## How the body is moving if it's hitting hard enough to count, otherwise zero.
func _impact_velocity(body: Node3D) -> Vector3:
	if body is Van:
		var v: Vector3 = body.linear_velocity
		return v if v.length() >= VAN_MIN_SPEED else Vector3.ZERO
	if body is Player:
		var v: Vector3 = body.velocity
		v.y = 0.0
		var toward_pole := (global_position - body.global_position).dot(v) > 0.0
		return v if toward_pole and v.length() >= RUN_MIN_SPEED else Vector3.ZERO
	return Vector3.ZERO


func _topple(hit: Vector3, body: Node3D) -> void:
	fallen = true
	set_physics_process(false)
	_hit_zone.monitoring = false
	# Once it's down it only lands on the town. It never gets under the van's
	# wheels or trips you up.
	collision_layer = 0
	for other in get_tree().get_nodes_in_group("vehicles") + get_tree().get_nodes_in_group("player"):
		add_collision_exception_with(other)
	freeze = false
	sleeping = false
	var push := Vector3(hit.x, 0.0, hit.z).normalized() * mass * clampf(hit.length() * 0.3, 2.5, 6.0)
	# Pushed two-thirds of the way up, the foot stays put and the pole tips over.
	apply_impulse(push, Vector3.UP * HEIGHT / 6.0)
	if body is Van:
		body.linear_velocity *= VAN_SPEED_KEPT
	knocked_down.emit()


func _capsule(radius: float) -> CapsuleShape3D:
	var c := CapsuleShape3D.new()
	c.radius = radius
	c.height = HEIGHT
	return c
