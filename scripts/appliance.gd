class_name Appliance
extends Interactable
## A piece of furniture or an appliance in the house you can do things with.
## E slides it out from the wall (and back), so you can get at what's behind
## it. F turns it on, if it's something that runs: it only works if the outlet
## it's plugged into has power, and it pulls real current on that circuit.

var node: Node3D                 # the placed model, which slides
var title := ""                  # "stove", "fridge", "couch"...
var slide := 0.7                 # how far it comes out from the wall
var sim: ElectricalPanel
var outlet: BoxView              # what it's plugged into, if it runs
var appliance := ""              # the name the electrics know it by: "range", "microwave"...
var slot := 0
var voltage := 120                # direct-connected equipment can require both 240 V legs
var interior: Node
var on := false
var pulled := false

var _home := Vector3.ZERO
var _glows: Array[StandardMaterial3D] = []


func _ready() -> void:
	super()
	reach = 1.3
	height_range = Vector2(-1.5, 0.6)   # on the floor or up on the counter, never from the attic
	_home = node.position
	position = _home + node.basis.z * 0.9
	_aim_at_model()
	on_use = _toggle_slide
	if appliance != "":
		on_alt = _toggle_on
	_update_prompt()


## You look at the appliance itself (it slides, so follow the model), not at
## the spot in front of it you stand on.
func _aim_at_model() -> void:
	var box := AABB()
	var first := true
	var to_node := node.global_transform.affine_inverse()
	for m: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (to_node * m.global_transform) * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	aim_target = node
	if not first:
		aim = box.get_center()
		aim_radius = box.size.length() / 2.0 * 0.8


## Something that glows while it's running: burners, a screen.
func add_glow(mat: StandardMaterial3D) -> void:
	_glows.append(mat)


func powered() -> bool:
	if outlet == null:
		if sim == null:
			return false
		if voltage == 240:
			var circuit := sim.circuit_at(slot)
			return circuit != null and circuit.poles.size() == 2 \
					and sim.voltage("term_%d" % circuit.poles[0], "term_%d" % circuit.poles[1]) > 200.0
		return sim.circuit_volts(slot) > 100.0
	if outlet.device.family == "240":
		return outlet.device.range_good()    # a stove needs both legs
	return outlet.device.face_volts() > 100.0


func _process(_delta: float) -> void:
	var running := on and powered()
	for m in _glows:
		m.emission_energy_multiplier = (3.0 if running else 0.0)
	# Continuous appliances report their actual running load to the panel.
	if appliance in ["range", "TV", "fridge"]:
		var key := "%d:%s" % [slot, appliance]
		if running:
			sim.demo[key] = 1.0
		else:
			sim.demo.erase(key)


func _toggle_slide(_p: Node3D) -> void:
	pulled = not pulled
	var out := node.basis.z * slide
	var t := create_tween()
	t.tween_property(node, "position", _home + (out if pulled else Vector3.ZERO), 0.6).set_trans(Tween.TRANS_SINE)
	position = _home + out * (1.0 if pulled else 0.0) + node.basis.z * 0.9
	_update_prompt()


func _toggle_on(_p: Node3D) -> void:
	if appliance in ["microwave", "toaster", "washer", "dryer"]:
		# These run for a while and switch themselves off.
		if powered():
			sim.run_appliance(slot, 30.0, appliance)
			_say("The %s is running." % title)
		else:
			_say("Nothing. The %s's dead." % title)
		return
	on = not on
	if on and not powered():
		_say("You turn the %s on. Nothing happens." % title)
	else:
		_say("You turn the %s %s." % [title, "on" if on else "off"])
	_update_prompt()


func _say(line: String) -> void:
	if interior != null and interior.has_method("hud_say"):
		interior.hud_say(line)


func _update_prompt() -> void:
	prompt = "[E] %s the %s" % ["Push back" if pulled else "Slide out", title]
	if appliance in ["range", "TV", "fridge"]:
		alt_prompt = "[F] Turn it %s" % ("off" if on else "on")
	elif appliance != "":
		alt_prompt = "[F] Run it"
