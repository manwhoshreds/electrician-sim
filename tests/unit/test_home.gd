extends "res://tests/test_case.gd"
## Starting out: a run-down house of your own, the truck in its driveway, the
## office at the kitchen table. The shop downtown is up for sale.

var main: Node


func before_each() -> void:
	SaveGame.enabled = false
	Engine.time_scale = 0.0
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_node(main)


func after_each() -> void:
	super()
	Engine.time_scale = 1.0
	SaveGame.enabled = true


func test_you_start_at_home_by_your_truck() -> void:
	var town: Town = main.town
	is_true(town.home.get("home", false), "one house is yours")
	is_false(town.home.get("business", false), "a house, not a business")
	var home: Node3D = town.home["root"]
	is_true(main.player.global_position.distance_to(town.home["door"]) < 10.0, "you're at your house")
	is_true(main.van.global_position.distance_to(town.home_start) < 4.0, "the truck's right there")
	is_true(main.van.global_position.distance_to(town.shop_spot.origin) > 20.0, "not at the shop")
	var van_local := home.to_local(main.van.global_position)
	is_true(absf(van_local.x) > (town.home["size"] as Vector3).x / 2 + 0.9, "in the driveway, clear of the house")


func test_nobody_calls_you_out_to_your_own_house() -> void:
	var service: ServiceCall = main.service
	var homes := service.properties.residential().map(func(p: Dictionary) -> String: return p["address"])
	is_false(main.town.home["address"] in homes)
	for i in 30:
		var job := service.call_generator.generate()
		check(job == null or job.address != main.town.home["address"], "call %d" % i)


func test_the_office_is_the_computer_at_home() -> void:
	var house: HomeHouse = main.town.home_house
	is_true(house.computer.on_use.is_valid(), "the computer opens the office")
	is_true(house.bed.on_use.is_valid(), "the bed's for sleeping")
	is_true(house.is_ancestor_of(house.computer) and house.is_ancestor_of(house.bed), "both inside your house")


func test_you_can_walk_in() -> void:
	var house: HomeHouse = main.town.home_house
	is_false(house.is_door_open())
	house.toggle_door()
	is_true(house.is_door_open(), "the front door opens")
	await tree.physics_frame
	# Nothing solid between the porch and the computer once the door's open.
	var space: PhysicsDirectSpaceState3D = main.get_viewport().world_3d.direct_space_state
	var from := house.to_global(Vector3(HomeHouse.DOOR_X, 1.0, HomeHouse.D / 2.0 + 1.0))
	var to := house.to_global(Vector3(HomeHouse.DOOR_X, 1.0, 0.0))
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))
	is_true(hit.is_empty(), "in through the front door: hit %s" % (hit.get("collider") if not hit.is_empty() else ""))


func test_the_shop_is_for_sale() -> void:
	var labels: Array = main.town.find_children("*", "Label3D", true, false).map(func(l: Label3D) -> String: return l.text)
	is_false(labels.has("SPARKS & SONS ELECTRIC"), "it isn't yours yet")
	is_true(labels.any(func(t: String) -> bool: return t.begins_with("FOR SALE")), "there's a sign")
