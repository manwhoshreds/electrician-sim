extends "res://tests/test_case.gd"
## What you get to use is what you're looking at: standing in the real house,
## the crosshair picks the thing, not whatever's nearest your feet, and never
## something through a wall.

var main: Node
var inside: HouseInterior
var player: Player


func before_each() -> void:
	SaveGame.enabled = false
	Engine.time_scale = 0.0              # nobody moves while we look round
	seed(21)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_node(main)
	var service: ServiceCall = main.service
	service.start_job()
	inside = service._inside
	player = main.player


func after_each() -> void:
	super()
	Engine.time_scale = 1.0
	SaveGame.enabled = true


## Stand at a spot in the house (local x, z, on the floor) and look at a point (local).
func _stand_and_look(at: Vector2, look_at: Vector3) -> Interactable:
	player.global_position = inside.to_global(Vector3(at.x, HouseInterior.FLOOR, at.y))
	var eye := player.global_position + Vector3(0, player.head.position.y, 0)
	var to := inside.to_global(look_at) - eye
	player.rotation.y = atan2(-to.x, -to.z)
	player.head.rotation.x = atan2(to.y, Vector2(to.x, to.z).length())
	return player._looked_at()


## Checks you're offered `want`, saying what you were offered if not.
func _offered(seen: Interactable, want: Interactable, what: String) -> void:
	check(seen == want, "%s: offered %s" % [what, ("\"%s\"" % seen.prompt) if seen != null else "nothing"])


func _box(room: String, kind: String) -> BoxView:
	for b: BoxView in inside.boxes:
		if b.room == room and b.device.kind == kind:
			return b
	return null


func _appliance(name: String) -> Appliance:
	return inside.appliances.filter(func(a: Appliance) -> bool: return a.appliance == name)[0]


func test_looking_at_the_water_heater_isnt_the_light_switch() -> void:
	await tree.physics_frame
	var heater := inside.get_node("WaterHeater") as Node3D
	var spot := Vector2(-0.2, -3.4)                     # in the laundry, the switch just behind you
	_offered(_stand_and_look(spot, heater.position + Vector3(0, 1.0, 0)), inside.heater_view, "looking at the heater is the heater")
	var sw := _box("laundry", "Switch")
	_offered(_stand_and_look(spot, sw.position), sw, "turn round to the switch and it's the switch")


func test_the_crosshair_picks_between_things_side_by_side() -> void:
	await tree.physics_frame
	var spot := Vector2(-4.8, -3.3)                      # at the kitchen counter
	var mw := _appliance("microwave")
	_offered(_stand_and_look(spot, inside.to_local(mw.aim_point())), mw, "the microwave")
	var toaster := _appliance("toaster")
	_offered(_stand_and_look(spot, inside.to_local(toaster.aim_point())), toaster, "the toaster beside it")
	var stove := _appliance("range")
	_offered(_stand_and_look(Vector2(-4.6, -3.0), inside.to_local(stove.aim_point())), stove, "the stove on the other wall")


func test_nothing_through_a_wall() -> void:
	await tree.physics_frame
	# In the kitchen, looking at where the laundry switch is on the other side of the wall.
	var sw := _box("laundry", "Switch")
	var seen := _stand_and_look(Vector2(-1.4, -3.0), sw.position)
	check(seen != sw, "the laundry switch isn't usable through the kitchen wall")


func test_looking_away_offers_nothing() -> void:
	await tree.physics_frame
	var seen := _stand_and_look(Vector2(-2.0, 1.0), Vector3(-2.0, HouseInterior.CEILING - 0.5, -1.0))
	check(seen == null, "staring at the empty family room ceiling: %s" % (seen.prompt if seen else ""))


func test_the_customer_by_their_middle() -> void:
	await tree.physics_frame
	var c: Customer = (main.service as ServiceCall)._customer
	player.global_position = c.global_position + Vector3(0, 0, 2.0)
	var eye := player.global_position + Vector3(0, player.head.position.y, 0)
	var to := c.aim_point() - eye
	player.rotation.y = atan2(-to.x, -to.z)
	player.head.rotation.x = atan2(to.y, Vector2(to.x, to.z).length())
	_offered(player._looked_at(), c, "looking them in the chest is talking to them")
