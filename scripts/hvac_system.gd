class_name HvacSystem
extends Node3D
## One central cooling system: a thermostat runs the indoor air handler and
## outdoor condenser, while the service disconnect can isolate the condenser.

var sim: ElectricalPanel
var interior: Node
var thermostat_position := Vector3.ZERO
var disconnect_position := Vector3.ZERO
var cooling_on := true
var disconnect_on := true

var thermostat: Interactable
var disconnect: Interactable


func _ready() -> void:
	thermostat = Interactable.new()
	thermostat.position = thermostat_position
	thermostat.on_use = _toggle_cooling
	thermostat.aim_radius = 0.08
	add_child(thermostat)
	disconnect = Interactable.new()
	disconnect.position = disconnect_position
	disconnect.on_use = _toggle_disconnect
	disconnect.reach = 1.5
	disconnect.aim_radius = 0.2
	add_child(disconnect)
	_update_prompts()


func _process(_delta: float) -> void:
	_set_load(15, "air handler", cooling_on and sim.circuit_volts(15) > 100.0)
	var ac := sim.circuit_at(6)
	var condenser_powered := ac != null and sim.voltage("term_%d" % ac.poles[0], "term_%d" % ac.poles[1]) > 200.0
	_set_load(6, "condenser", cooling_on and disconnect_on and condenser_powered)


func _set_load(slot: int, equipment: String, running: bool) -> void:
	var key := "%d:%s" % [slot, equipment]
	if running:
		sim.demo[key] = 1.0
	else:
		sim.demo.erase(key)


func _toggle_cooling(_player: Node3D) -> void:
	cooling_on = not cooling_on
	interior.hud_say("The central air is %s." % ("running" if cooling_on else "off"))
	_update_prompts()


func _toggle_disconnect(_player: Node3D) -> void:
	disconnect_on = not disconnect_on
	interior.hud_say("A/C disconnect %s." % ("installed" if disconnect_on else "pulled"))
	_update_prompts()


func _update_prompts() -> void:
	thermostat.prompt = "[E] Turn central air %s" % ("off" if cooling_on else "on")
	disconnect.prompt = "[E] %s A/C disconnect" % ("Pull" if disconnect_on else "Install")
