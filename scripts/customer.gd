class_name Customer
extends Interactable
## The person who called. Waits by the front door, waves until you've talked,
## and turns to face you when you're close. The model faces +Z.

const SKIN := [Color(0.93, 0.76, 0.62), Color(0.7, 0.5, 0.36), Color(0.42, 0.28, 0.2), Color(0.85, 0.65, 0.5)]
const SHIRT := [Color(0.65, 0.2, 0.2), Color(0.2, 0.4, 0.6), Color(0.35, 0.55, 0.35), Color(0.75, 0.6, 0.25), Color(0.5, 0.35, 0.6)]
const PANTS := [Color(0.2, 0.22, 0.3), Color(0.35, 0.3, 0.25), Color(0.28, 0.28, 0.28)]
const HAIR := [Color(0.1, 0.08, 0.07), Color(0.35, 0.22, 0.12), Color(0.7, 0.7, 0.72), Color(0.6, 0.45, 0.2)]

signal arrived(hangout: int)     # got to a place in the house: 0 the couch, 1 the kitchen

var person_name := "Customer"
## Non-zero: always the same look, from this seed, and the game's shared dice
## aren't touched (someone who's always there, like the parts guy).
var look_seed := 0
var player: Node3D
var waving := true
## Once you've talked: places to go and spend some time in the house, each
## [position, the way to face, sit down there]. They wander between them.
var hangouts: Array = []

var _route: Array[Vector3] = []
var _sitting := false
var _settle_t := 0.0             # how long before they get up and go somewhere else
var _face := Vector3.ZERO        # the way to face once they get there
var _at := -1

const WALK_SPEED := 1.1
const SIT_DROP := 0.42           # sunk into the cushions: the legs go down out of sight

## Their body: one of the City Folks, posed and moving (CharacterModel).
var body: CharacterModel


func _ready() -> void:
	super()
	reach = 3.0
	aim = Vector3(0, 1.1, 0)         # their middle, not their feet
	aim_radius = 0.4
	prompt = "[E] Talk to %s" % person_name
	# The same four rolls the old look took, so the game's dice fall the same;
	# together they pick which of the City Folks this is.
	var rng := RandomNumberGenerator.new()
	rng.seed = look_seed
	var pick := func(from: Array) -> int: return (rng.randi() % from.size()) if look_seed != 0 else from.find(from.pick_random())
	var look: int = pick.call(SKIN) + pick.call(SHIRT) * 3 + pick.call(PANTS) * 7 + pick.call(HAIR) * 11
	body = CharacterModel.new()
	add_child(body)
	body.setup(look)
	body.speed = WALK_SPEED


## Walk through the points in order, then settle at the first hangout.
func go_inside(points: Array[Vector3]) -> void:
	_route = points.duplicate()
	_at = -1
	_head_to_next_hangout()


func _head_to_next_hangout() -> void:
	if hangouts.is_empty():
		return
	_at = (_at + 1) % hangouts.size()
	var spot: Array = hangouts[_at]
	_route.append(spot[0])
	_face = spot[1]
	_stand()


func _stand() -> void:
	if _sitting:
		_sitting = false
		position.y += SIT_DROP


func _walk(delta: float) -> void:
	var goal := _route[0]
	var d := goal - global_position
	var flat := Vector3(d.x, 0, d.z)
	if flat.length() < 0.05:
		global_position = goal
		_route.pop_front()
		if _route.is_empty():
			_arrive()
		return
	var step := minf(WALK_SPEED * delta, flat.length())
	global_position += flat.normalized() * step + Vector3(0, d.y * step / maxf(flat.length(), 0.01), 0)
	rotation.y = lerp_angle(rotation.y, atan2(flat.x, flat.z), minf(1.0, delta * 8.0))


func _arrive() -> void:
	rotation.y = atan2(_face.x, _face.z)
	var spot: Array = hangouts[_at]
	if spot[2]:
		_sitting = true
		position.y -= SIT_DROP
	_settle_t = randf_range(25.0, 50.0)
	arrived.emit(_at)


func _process(delta: float) -> void:
	body.walking = move_toward(body.walking, 1.0 if not _route.is_empty() else 0.0, delta * 4.0)
	body.sitting = _sitting
	body.waving = waving and _route.is_empty()
	if not _route.is_empty():
		_walk(delta)
		return
	if _at >= 0:
		_settle_t -= delta
		if _settle_t <= 0.0:
			_head_to_next_hangout()
		if _sitting:
			return
	if player == null:
		return
	var d := player.global_position - global_position
	d.y = 0.0
	if d.length() < 9.0:
		rotation.y = lerp_angle(rotation.y, atan2(d.x, d.z), minf(1.0, delta * 5.0))
