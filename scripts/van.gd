class_name Van
extends VehicleBody3D
## Your work vehicle. You start with a rusty old pickup (art/truck.py) that
## holds next to nothing; buy the van (art/van.py) and it holds a lot more.
##   E (near it)  get in / out      W / S  gas / brake + reverse
##   A / D        steer             Space  handbrake
##   R            flip it back over      Mouse  look around
##   C            inside view / chase view

const ENGINE_FORCE := 3600.0        # per driven wheel, newtons
const REVERSE_FORCE := 1400.0
const BRAKE := 65.0
const HANDBRAKE := 80.0
const MAX_STEER := 0.55             # radians at walking speed...
const HIGH_SPEED_STEER := 0.16      # ...and at top speed
const TOP_SPEED := 30.0             # m/s (~110 km/h)
const ENTER_RANGE := 4.5             # from the middle of the van

var prompt := "[E] Get in the truck"
var model_name := "truck"           # "truck" or "van", see MODELS

var player: Node                    # the player (set by main)
var hud: Node
var driver: Node = null             # the player while driving

var _cam: Camera3D
var _cam_yaw := 0.0                 # mouse orbit around the van
var _cam_pitch := -0.25
var _idle_look := 0.0
var _engine: AudioStreamPlayer3D
var _headlights: Array[SpotLight3D] = []
var _lamp_mat: StandardMaterial3D
var _brake_mat: StandardMaterial3D
var _flip_timer := 0.0
var _inside := false                # looking out from the driver's seat
var _steering_wheel: Node3D
var _steering_rest := Basis()
var _parts: Array[Node] = []        # everything the current model added, so it can be swapped


func _ready() -> void:
	add_to_group("vehicles")
	mass = 2200.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, -0.15, 0)   # very low, so it doesn't roll over in turns
	_build_body()
	_build_wheels()
	_build_lights()
	_build_sound()
	_cam = Camera3D.new()
	_cam.top_level = true
	_cam.fov = 75.0
	_cam.far = 8000.0
	add_child(_cam)


func _unhandled_input(event: InputEvent) -> void:
	if driver:
		if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_cam_yaw -= event.relative.x * 0.004
			_cam_pitch = clampf(_cam_pitch - event.relative.y * 0.003, -1.2, 0.3)
			if _inside:
				_cam_yaw = clampf(_cam_yaw, -INSIDE_YAW, INSIDE_YAW)
			_idle_look = 0.0
		elif event.is_action_pressed("interact"):
			get_out()
			get_viewport().set_input_as_handled()
		elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
			_flip()
		elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_C:
			_set_inside(not _inside)
	elif event.is_action_pressed("interact") and can_enter(player):
		get_in(player)
		get_viewport().set_input_as_handled()


## Close enough, and not busy chopping a tree or building.
func can_enter(p: Node) -> bool:
	if p == null or p.dead or p.target != null or p.driving != null or p.focus != null:
		return false
	return p.global_position.distance_to(global_position) < ENTER_RANGE


func get_in(p: Node) -> void:
	driver = p
	p.driving = self
	p.visible = false
	p.get_node("CollisionShape3D").disabled = true
	_set_inside(_inside)
	_cam.global_position = global_position + global_basis.z * 8.0 + Vector3.UP * 3.0
	_cam.make_current()
	for l in _headlights:
		l.visible = true
	if _bar_light != null:
		_bar_light.visible = light_bar
	_lamp_mat.emission_energy_multiplier = 4.0
	_engine.play()
	p._last_prompt = ""
	if hud:
		hud.show_toast("W/S gas & brake   A/D steer   Space handbrake   E get out   R flip over   C inside view", 4.0)


## The LED light bar on the roof (TradesmanGear): lights the road ahead while you drive.
var light_bar := false:
	set(v):
		light_bar = v
		_fit_light_bar()
var _bar: Node3D
var _bar_light: SpotLight3D


func _fit_light_bar() -> void:
	if _bar == null and light_bar:
		_bar = Node3D.new()
		var roof := 1.9 if model_name == "truck" else 2.55
		var z := -0.55 if model_name == "truck" else -1.9
		_bar.position = Vector3(0, roof, z)
		add_child(_bar)
		var body := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(1.0, 0.09, 0.09)
		body.mesh = b
		body.material_override = _mat(Color(0.05, 0.05, 0.06), 0.6, 0.3)
		_bar.add_child(body)
		var lens := MeshInstance3D.new()
		var lb := BoxMesh.new()
		lb.size = Vector3(0.92, 0.05, 0.01)
		lens.mesh = lb
		lens.material_override = _lamp_mat
		lens.position = Vector3(0, 0, -0.05)
		_bar.add_child(lens)
		_bar_light = SpotLight3D.new()
		_bar_light.light_energy = 9.0
		_bar_light.spot_range = 70.0
		_bar_light.spot_angle = 40.0
		_bar_light.rotation.x = -0.12
		_bar_light.visible = false
		_bar.add_child(_bar_light)
	if _bar != null:
		_bar.visible = light_bar


func get_out() -> void:
	var p := driver
	driver = null
	engine_force = 0.0
	brake = HANDBRAKE
	# Step out on the driver's side, on the ground.
	var spot := global_position - global_basis.x * 2.4 + Vector3.UP * 0.3
	p.global_position = spot
	p.velocity = Vector3.ZERO
	p.rotation.y = rotation.y
	p.head.rotation.x = 0.0
	p.visible = true
	p.get_node("CollisionShape3D").disabled = false
	p.driving = null
	p.camera.make_current()
	for l in _headlights:
		l.visible = false
	if _bar_light != null:
		_bar_light.visible = false
	_lamp_mat.emission_energy_multiplier = 0.3
	_brake_mat.emission_energy_multiplier = 0.3
	_engine.stop()
	if hud:
		hud.set_speed("")


## Where the driver "sits" (the player is moved here while driving).
func seat() -> Vector3:
	return global_transform * Vector3(-0.45, 0.8, -1.8)


func _physics_process(delta: float) -> void:
	var fwd_speed := -global_basis.z.dot(linear_velocity)   # + forward, - backward
	var speed := linear_velocity.length()
	if driver == null:
		engine_force = 0.0
		brake = HANDBRAKE * 0.5
		return

	var throttle := Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
	var steer_in := Input.get_action_strength("move_left") - Input.get_action_strength("move_right")
	var braking := false
	if throttle > 0.0:
		engine_force = ENGINE_FORCE * throttle if fwd_speed < TOP_SPEED else 0.0
		brake = 0.0
		if fwd_speed < -1.0:            # rolling backwards: brake first
			engine_force = 0.0
			brake = BRAKE
			braking = true
	elif throttle < 0.0:
		if fwd_speed > 1.0:             # moving forward: S brakes...
			engine_force = 0.0
			brake = BRAKE
			braking = true
		else:                           # ...then reverses
			engine_force = -REVERSE_FORCE
			brake = 0.0
	else:
		engine_force = 0.0
		brake = 2.0                     # engine braking / rolling resistance
	if Input.is_action_pressed("jump"):
		brake = HANDBRAKE
		engine_force = 0.0
		braking = true

	# Less steering the faster you go, and it eases in.
	var max_steer := lerpf(MAX_STEER, HIGH_SPEED_STEER, clampf(absf(fwd_speed) / TOP_SPEED, 0.0, 1.0))
	steering = move_toward(steering, steer_in * max_steer, delta * 2.5)
	# Godot's vehicle drives toward +Z; this van's front is -Z.
	engine_force = -engine_force

	_brake_mat.emission_energy_multiplier = 5.0 if braking else 0.6
	_engine.pitch_scale = 0.55 + absf(fwd_speed) / TOP_SPEED * 1.6 + absf(throttle) * 0.1
	_engine.volume_db = -10.0 + absf(throttle) * 4.0
	if hud:
		hud.set_speed("%d km/h" % int(absf(fwd_speed) * 3.6))

	# Stuck on its side or roof for a while: offer to flip.
	if global_basis.y.y < 0.3 and speed < 2.0:
		_flip_timer += delta
		if _flip_timer > 1.5 and hud:
			hud.show_toast("Press R to flip the truck")
			_flip_timer = 0.0
	else:
		_flip_timer = 0.0


func _process(delta: float) -> void:
	if driver == null:
		return
	# The steering wheel turns a good bit more than the road wheels do.
	_steering_wheel.basis = _steering_rest * Basis(Vector3.BACK, steering * STEERING_TURNS)
	if _inside:
		_update_inside_camera(delta)
		return
	# Chase camera: behind the van, swings round with the mouse, and drifts
	# back behind once you've stopped looking around and you're moving.
	_idle_look += delta
	if _idle_look > 1.5 and linear_velocity.length() > 4.0:
		_cam_yaw = lerp_angle(_cam_yaw, 0.0, minf(1.0, delta * 2.0))
		_cam_pitch = lerpf(_cam_pitch, CHASE_PITCH, minf(1.0, delta * 2.0))
	var heading := atan2(global_basis.z.x, global_basis.z.z)
	var orbit := Basis(Vector3.UP, heading + _cam_yaw) * Basis(Vector3.RIGHT, _cam_pitch)
	var focus := global_position + Vector3.UP * 2.0
	var want := focus + orbit * Vector3(0, 0, 8.5)
	want.y = maxf(want.y, 0.6)
	_cam.global_position = _cam.global_position.lerp(want, minf(1.0, delta * 10.0))
	_cam.look_at(focus, Vector3.UP)
	_cam.fov = lerpf(_cam.fov, 72.0 + linear_velocity.length() * 0.4, minf(1.0, delta * 3.0))


func _set_inside(on: bool) -> void:
	_inside = on
	_cam_yaw = 0.0
	_cam_pitch = INSIDE_PITCH if on else CHASE_PITCH
	_idle_look = 0.0
	_cam.fov = INSIDE_FOV if on else 75.0


## Sitting in the driver's seat. Your eyes drift back to the road once you stop
## looking around and you're moving.
func _update_inside_camera(delta: float) -> void:
	_idle_look += delta
	if _idle_look > 1.5 and linear_velocity.length() > 4.0:
		_cam_yaw = lerp_angle(_cam_yaw, 0.0, minf(1.0, delta * 2.0))
		_cam_pitch = lerpf(_cam_pitch, INSIDE_PITCH, minf(1.0, delta * 2.0))
	_cam.global_transform = Transform3D(global_basis * Basis(Vector3.UP, _cam_yaw) * Basis(Vector3.RIGHT, _cam_pitch), to_global(spec()["eye"]))


func _flip() -> void:
	if global_basis.y.y > 0.7:
		return
	var yaw := atan2(-global_basis.z.x, -global_basis.z.z)
	global_transform = Transform3D(Basis(Vector3.UP, yaw), global_position + Vector3.UP * 1.5)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


# --- Model ----------------------------------------------------------------
## Front is -Z. The origin is on the ground. Positions match art/truck.py.

## Everything that changes between the two vehicles. Positions match their art scripts.
const MODELS := {
	"truck": {"glb": "res://assets/truck/truck.glb", "front": -1.75, "rear": 1.45, "track": 0.8,
		"headlight": Vector3(0.8, 0.9, -2.5), "tail": Vector3(0.905, 1.02, 2.455), "eye": Vector3(-0.42, 1.62, 0.2),
		"boxes": [[Vector3(1.9, 1.4, 1.5), Vector3(0, 1.16, 0.03)], [Vector3(1.9, 0.8, 1.75), Vector3(0, 0.86, -1.6)],
			[Vector3(1.9, 0.75, 1.62), Vector3(0, 0.87, 1.62)]],
		"name_at": Vector3(0.98, 0.88, -0.05), "name_colour": Color(0.86, 0.82, 0.68, 0.9), "name_size": 0.0028,
		"rear_door": 2.95, "capacity": 8, "word": "truck"},
	"van": {"glb": "res://assets/van/van.glb", "front": -1.75, "rear": 1.55, "track": 0.86,
		"headlight": Vector3(0.78, 1.1, -2.66), "tail": Vector3(0.93, 1.35, 2.715), "eye": Vector3(-0.5, 1.82, -1.0),
		"boxes": [[Vector3(2.0, 1.7, 3.5), Vector3(0, 1.6, 0.95)], [Vector3(2.0, 1.2, 1.9), Vector3(0, 1.1, -1.7)]],
		"name_at": Vector3(1.012, 1.75, 1.0), "name_colour": Color(0.12, 0.12, 0.14), "name_size": 0.0045,
		"rear_door": 3.05, "capacity": 30, "word": "van"},
}

const INSIDE_PITCH := -0.1
const CHASE_PITCH := -0.25
const INSIDE_YAW := 2.2             # how far you can turn your head
const INSIDE_FOV := 75.0
const STEERING_TURNS := 4.0


func spec() -> Dictionary:
	return MODELS[model_name]


## Swap to the other vehicle, keeping where it's parked.
func become(new_model: String) -> void:
	model_name = new_model
	for n in _parts:
		n.queue_free()
	_parts.clear()
	_headlights.clear()
	_build_body()
	_build_wheels()
	_build_lights()
	if _bar != null:                 # the light bar goes on the new roof
		_bar.queue_free()
		_bar = null
		_bar_light = null
	_fit_light_bar()
	prompt = "[E] Get in the %s" % spec()["word"]


func _keep(n: Node) -> Node:
	add_child(n)
	_parts.append(n)
	return n


func _build_body() -> void:
	var model: Node3D = _keep((load(spec()["glb"]) as PackedScene).instantiate())
	_steering_wheel = model.find_child("SteeringWheel", true, false)
	_steering_rest = _steering_wheel.basis
	var inside: Node = model.find_child("Inside", true, false)
	if inside != null:
		_backlight_gauges(inside)
	# The company name on both sides.
	for s in [-1.0, 1.0]:
		var name_l := Label3D.new()
		name_l.text = "SPARKS & SONS\nELECTRIC"
		name_l.font_size = 72
		name_l.pixel_size = spec()["name_size"]
		name_l.modulate = spec()["name_colour"]
		name_l.outline_size = 0
		name_l.position = spec()["name_at"] * Vector3(s, 1, 1)
		name_l.rotation.y = s * PI / 2
		_keep(name_l)
	for b: Array in spec()["boxes"]:
		_add_collision_box(b[0], b[1])


## The dash is in shadow, so the dials glow a little to stay readable.
func _backlight_gauges(inside: MeshInstance3D) -> void:
	for i in inside.mesh.get_surface_count():
		var mat := inside.mesh.surface_get_material(i) as StandardMaterial3D
		if mat != null and mat.resource_name == "Gauges":
			mat.emission_enabled = true
			mat.emission_texture = mat.albedo_texture
			mat.emission_energy_multiplier = 0.6


func _add_collision_box(size: Vector3, pos: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = pos
	_keep(col)


func _build_wheels() -> void:
	var model: PackedScene = load("res://assets/truck/truck_wheel.glb")
	var track: float = spec()["track"]
	for z in [spec()["front"], spec()["rear"]]:
		for x in [-track, track]:
			var w := VehicleWheel3D.new()
			w.position = Vector3(x, 0.6, z)
			w.use_as_steering = z < 0.0
			w.use_as_traction = z > 0.0       # rear-wheel drive
			w.wheel_radius = 0.39
			w.wheel_rest_length = 0.22
			w.suspension_travel = 0.25
			w.suspension_stiffness = 50.0
			w.suspension_max_force = 60000.0
			w.damping_compression = 2.5
			w.damping_relaxation = 3.5
			w.wheel_friction_slip = 2.2
			w.wheel_roll_influence = 0.04
			_keep(w)
			var tyre: Node3D = model.instantiate()
			if x < 0.0:                       # so the rim faces out on both sides
				tyre.rotation.y = PI
			w.add_child(tyre)


func _build_lights() -> void:
	_lamp_mat = _mat(Color(1, 0.95, 0.8), 0.0, 0.2)
	_lamp_mat.emission_enabled = true
	_lamp_mat.emission = Color(1, 0.92, 0.75)
	_lamp_mat.emission_energy_multiplier = 0.3
	_brake_mat = _mat(Color(0.6, 0.02, 0.02), 0.0, 0.3)
	_brake_mat.emission_enabled = true
	_brake_mat.emission = Color(1, 0.05, 0.02)
	_brake_mat.emission_energy_multiplier = 0.3
	var lens_mesh := CylinderMesh.new()
	lens_mesh.top_radius = 0.1
	lens_mesh.bottom_radius = 0.1
	lens_mesh.height = 0.03
	lens_mesh.radial_segments = 24
	for s in [-1.0, 1.0]:
		var lens := MeshInstance3D.new()
		lens.mesh = lens_mesh
		lens.material_override = _lamp_mat
		lens.position = spec()["headlight"] * Vector3(s, 1, 1)
		lens.rotation.x = PI / 2
		_keep(lens)
		_parts.append(_box(Vector3(0.11, 0.21, 0.012), spec()["tail"] * Vector3(s, 1, 1), _brake_mat))
		var spot := SpotLight3D.new()
		spot.position = spec()["headlight"] * Vector3(s, 1, 1) + Vector3(0, 0, -0.1)
		spot.rotation.x = -0.08
		spot.light_color = Color(1, 0.93, 0.8)
		spot.light_energy = 6.0
		spot.spot_range = 45.0
		spot.spot_angle = 32.0
		spot.shadow_enabled = false
		spot.visible = driver != null
		_keep(spot)
		_headlights.append(spot)


## A looping engine drone: low buzz plus a bit of rumble.
func _build_sound() -> void:
	var rate := 22050
	var n := rate                       # 1 s loop; 55 Hz fits it exactly
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in n:
		var t := float(i) / rate
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.08
		var s := sin(TAU * 55.0 * t) * 0.5 + sin(TAU * 110.0 * t) * 0.25 \
				+ signf(sin(TAU * 27.5 * t * 2.0)) * 0.12 + lp * 0.6
		data.encode_s16(i * 2, int(clampf(s * 0.7, -1.0, 1.0) * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_end = n
	_engine = AudioStreamPlayer3D.new()
	_engine.stream = w
	_engine.unit_size = 8.0
	_engine.position = Vector3(0, 0.9, -2.6)
	add_child(_engine)


func _mat(c: Color, metal: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	return m


func _box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi
