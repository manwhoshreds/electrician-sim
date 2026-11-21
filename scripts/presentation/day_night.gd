class_name DayNight
extends Node
## Keeps the sky (Sky3D, addons/sky_3d) at the game clock's time of day, and
## turns the street lamps up and the lights on at home after dark.

var sky: Sky3D
var clock: Callable              # -> game minutes
var street_lamps: StandardMaterial3D


func _process(_delta: float) -> void:
	sky.current_time = fmod(float(clock.call()), 1440.0) / 60.0
	var dark := is_dark()
	if street_lamps != null:
		street_lamps.emission_energy_multiplier = 4.0 if dark else 0.4
	for bulb: Node in get_tree().get_nodes_in_group("home_light"):
		(bulb as Light3D).visible = dark


func is_dark() -> bool:
	return sky.is_night()
