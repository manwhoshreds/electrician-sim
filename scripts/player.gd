class_name Player
extends CharacterBody3D
## First-person electrician on foot. WASD, Shift sprint, Space jump, mouse look.

const WALK := 4.5
const SPRINT := 7.5
const JUMP := 4.5
const MOUSE := 0.0022

var head: Node3D
var camera: Camera3D
var hud: Node
var driving: Node = null          # the van, while you're in it
## How fast you go of your usual pace: slower when you're exhausted (Fatigue).
var pace := 1.0
## A headlamp you've bought (TradesmanGear), and whether you've switched it on.
var has_headlamp := false
var headlamp_on := false
var dead := false
var target: Node = null           # what's got your attention: a conversation or a panel
var focus: Interactable = null    # the thing E would use right now
var _last_prompt := ""
var crouched := false             # in an attic: low, slow, with a headlamp on
var _headlamp: SpotLight3D
var _shape: CapsuleShape3D
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	add_to_group("player")
	var col := CollisionShape3D.new()
	col.name = "CollisionShape3D"
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.8
	col.shape = cap
	_shape = cap
	col.position.y = 0.9
	add_child(col)
	head = Node3D.new()
	head.position.y = 1.65
	add_child(head)
	camera = Camera3D.new()
	camera.fov = 75.0
	camera.far = 3000.0
	head.add_child(camera)
	camera.make_current()
	_headlamp = SpotLight3D.new()
	_headlamp.light_color = Color(1.0, 0.95, 0.85)
	_headlamp.light_energy = 2.5
	_headlamp.spot_range = 9.0
	_headlamp.spot_angle = 32.0
	_headlamp.shadow_enabled = true
	_headlamp.visible = false
	camera.add_child(_headlamp)


## Hunched over in the attic, headlamp on. Back to normal when you climb down.
func set_crouched(on: bool) -> void:
	crouched = on
	_shape.height = 1.05 if on else 1.8
	(get_node("CollisionShape3D") as CollisionShape3D).position.y = _shape.height / 2
	head.position.y = 0.95 if on else 1.65
	_light_headlamp()


## The headlamp's on in the attic, and anywhere you've switched on one you bought (L).
func _light_headlamp() -> void:
	_headlamp.visible = crouched or (has_headlamp and headlamp_on)


func toggle_headlamp() -> void:
	if has_headlamp:
		headlamp_on = not headlamp_on
		_light_headlamp()


func _unhandled_input(event: InputEvent) -> void:
	if target != null or driving != null:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotation.y -= event.relative.x * MOUSE
		head.rotation.x = clampf(head.rotation.x - event.relative.y * MOUSE, -1.45, 1.45)
	elif event.is_action_pressed("headlamp"):
		toggle_headlamp()
	elif event.is_action_pressed("interact") and focus != null:
		focus.use(self)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("work") and focus != null and focus.on_alt.is_valid():
		focus.on_alt.call(self)
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if driving:
		global_position = driving.seat()
		return
	if target != null:
		velocity = Vector3.ZERO
		focus = null
		_show_prompt()
		return
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = JUMP
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := (global_basis * Vector3(input.x, 0, input.y)).normalized()
	var speed := (SPRINT if Input.is_action_pressed("sprint") else WALK) * pace
	if crouched:
		speed = 1.6                   # stepping joist to joist
	velocity.x = move_toward(velocity.x, dir.x * speed, delta * 40.0)
	velocity.z = move_toward(velocity.z, dir.z * speed, delta * 40.0)
	move_and_slide()
	# What can I do here? Whatever's under the crosshair, in reach, and not
	# behind a wall; anything up close beats getting in the truck.
	focus = _looked_at()
	var lines: Array[String] = []
	var at := Vector3.INF
	if focus:
		lines.append(focus.prompt)
		if focus.alt_prompt != "":
			lines.append(focus.alt_prompt)
		at = focus.aim_point()
	else:
		for v: Node3D in get_tree().get_nodes_in_group("vehicles"):
			if v.can_enter(self):
				lines = [v.prompt]
				at = v.global_position + Vector3.UP * 1.3
	_show_prompt(lines, at)


## How far off the crosshair (in radians, past its edge) something can be and still count.
const LOOK_SLACK := 0.09


## The thing you're looking at: in reach, the crosshair on it (or nearest to
## being on it), nothing solid in between. Null if there isn't one.
func _looked_at() -> Interactable:
	var eye := camera.global_position
	var look := -camera.global_basis.z
	var best: Interactable = null
	var best_score := INF
	for it: Interactable in get_tree().get_nodes_in_group("interactables"):
		if not it.can_use(self):
			continue
		var to := it.aim_point() - eye
		var dist := to.length()
		var off := look.angle_to(to) if dist > 0.01 else 0.0
		var miss := maxf(off - atan2(it.aim_radius, dist), 0.0)
		if miss > LOOK_SLACK:
			continue
		var score := miss * 4.0 + off      # on it beats near it; then the one nearest the crosshair
		if score < best_score and _in_sight(eye, it.aim_point(), dist - it.aim_radius - 0.05):
			best = it
			best_score = score
	return best


## Nothing solid between your eyes and a point, short of `clear_to` metres.
func _in_sight(eye: Vector3, point: Vector3, clear_to: float) -> bool:
	if clear_to <= 0.0:
		return true
	var q := PhysicsRayQueryParameters3D.create(eye, point)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or eye.distance_to(hit["position"]) >= clear_to


## The tag(s) beside what you're looking at. The HUD follows `at` every frame.
func _show_prompt(lines: Array[String] = [], at := Vector3.INF) -> void:
	if hud:
		hud.set_prompt(lines, at)
	_last_prompt = "\n".join(lines)
