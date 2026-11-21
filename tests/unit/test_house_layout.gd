extends "res://tests/test_case.gd"
## The house as built against the owner's floor plan: everything where the
## plan says, in the room it's named for, on a wall face (not buried in one),
## and a person can walk through every doorway into every room.

const H := 1.36                  # waist height above the floor, for walk-through rays

var inside: HouseInterior


func before_each() -> void:
	SaveGame.enabled = false
	Engine.time_scale = 0.0
	seed(21)
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_node(main)
	var service: ServiceCall = main.service
	service.start_job()
	inside = service._inside


func after_each() -> void:
	super()
	Engine.time_scale = 1.0
	SaveGame.enabled = true


func test_the_house_is_the_plans_size() -> void:
	near(inside._w, 12.192, "40 ft wide")
	near(inside._d, 9.144, "30 ft deep")
	is_false(inside.house["two_story"])


func test_nothing_buried_floating_in_a_doorway_or_outside() -> void:
	eq(inside.layout_violations(), [] as Array[String])


## Where each room is on the plan (local metres), generously at the walls.
static func _in_room(room: String, p: Vector3) -> bool:
	var m := 0.07
	match room:
		"kitchen":
			return p.x < -0.98 + m and p.z < -0.3
		"living room":
			return p.x < 0.83 + m and p.z > -1.0
		"bathroom":
			return p.x > -0.98 - m and p.x < 1.96 + m and p.z > -2.62 - m and p.z < -0.04 + m
		"master bedroom":
			return p.x > 1.96 - m and p.z < -0.04 + m
		"front bedroom":
			return p.x > 2.38 - m and p.z > 1.14 - m
		"hall bathroom":
			return p.x > 0.83 - m and p.x < 2.38 + m and p.z > 1.14 - m and p.z < 2.99 + m
		"laundry":
			return p.x > -0.98 - m and p.x < 1.96 + m and p.z < -2.62 + m
	return false


func test_every_box_is_in_the_room_its_named_for() -> void:
	for b: BoxView in inside.boxes + inside.detectors:
		check(_in_room(b.room, b.position), "%s (%s) is at %s" % [inside.electrical.id_of(b.device), b.room, b.position])


func test_the_customer_makes_toast_in_the_kitchen() -> void:
	eq(inside.hangouts.size(), 2)
	var couch := inside.to_local(inside.hangouts[0][0])
	var toast := inside.to_local(inside.hangouts[1][0])
	check(_in_room("living room", couch), "the couch spot's in the family room: %s" % couch)
	check(_in_room("kitchen", toast), "the toast spot's in the kitchen: %s" % toast)
	var toaster := inside.appliances.filter(func(a: Appliance) -> bool: return a.appliance == "toaster")[0] as Appliance
	var at := inside.to_local(toaster.node.global_position)
	is_true(Vector2(at.x, at.z).distance_to(Vector2(toast.x, toast.z)) < 1.0, "standing at the toaster")


func test_appliances_are_in_their_rooms() -> void:
	var where := {"range": "kitchen", "fridge": "kitchen", "microwave": "kitchen", "toaster": "kitchen", "TV": "living room",
			"washer": "laundry", "dryer": "laundry"}
	for a: Appliance in inside.appliances:
		var p := inside.to_local(a.node.global_position)
		check(_in_room(where[a.appliance], p), "%s at %s" % [a.appliance, p])


# --- Walking through it --------------------------------------------------------------------

func _clear(a: Vector2, b: Vector2) -> bool:
	var space := inside.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(inside.to_global(Vector3(a.x, H, a.y)), inside.to_global(Vector3(b.x, H, b.y)))
	return space.intersect_ray(q).is_empty()


## A walk along these points (local x, z), every leg unobstructed.
func _walk(name: String, points: Array) -> void:
	for i in points.size() - 1:
		check(_clear(points[i], points[i + 1]), "%s: blocked between %s and %s" % [name, points[i], points[i + 1]])


func test_you_can_walk_into_every_room() -> void:
	await tree.physics_frame
	await tree.physics_frame
	var hall := [Vector2(-0.05, 3.7), Vector2(-1.5, 0.6), Vector2(0.0, 0.55)]
	_walk("front door to the kitchen", [Vector2(-0.05, 3.7), Vector2(-1.5, 0.6), Vector2(-2.0, -2.6)])
	_walk("into the master", hall + [Vector2(2.6, 0.55), Vector2(2.6, -1.5)])
	_walk("into bedroom 2", hall + [Vector2(3.0, 0.55), Vector2(3.0, 2.5)])
	_walk("into the hall bath", hall + [Vector2(1.35, 0.55), Vector2(1.35, 1.8)])
	_walk("master into its bath", [Vector2(2.6, -1.5), Vector2(1.3, -1.35)])
	_walk("master into its closet", [Vector2(2.6, -1.5), Vector2(5.1, -1.2), Vector2(5.1, 0.3)])
	_walk("bedroom 2 into its closet", [Vector2(3.0, 2.5), Vector2(3.2, 3.75), Vector2(1.6, 3.75)])
	_walk("kitchen into the laundry", [Vector2(-2.0, -3.3), Vector2(0.0, -3.3)])


func test_walls_are_where_the_plan_has_them() -> void:
	await tree.physics_frame
	await tree.physics_frame
	is_false(_clear(Vector2(-1.5, 0.6), Vector2(0.4, -3.3)), "family room straight into the laundry")
	is_false(_clear(Vector2(4.5, -1.5), Vector2(4.5, 2.5)), "master through the closet into bedroom 2")
	is_false(_clear(Vector2(0.0, 0.55), Vector2(0.4, -1.3)), "hall straight into the master bath")
	is_false(_clear(Vector2(-1.5, 2.0), Vector2(1.6, 2.0)), "family room straight into the hall bath")


func test_the_back_door_opens_out_of_the_kitchen() -> void:
	await tree.physics_frame
	await tree.physics_frame
	var out := [Vector2(-1.7, -3.3), Vector2(-1.7, -6.0)]
	is_false(_clear(out[0], out[1]), "shut, it's solid")
	inside._toggle_back_door()
	await tree.physics_frame
	await tree.physics_frame
	_walk("out the back door", out)


func test_the_water_heater_stands_in_the_laundry() -> void:
	var heater := inside.get_node_or_null("WaterHeater") as Node3D
	check(heater != null, "the owner's water heater model is in the house")
	if heater == null:
		return
	check(_in_room("laundry", heater.position), "in the laundry: %s" % heater.position)
	near(heater.position.y, HouseInterior.FLOOR, "standing on the floor")
	for part in ["WaterHeaterTank", "UpperThermostatCover", "LowerThermostatCover", "ElectricalJunctionPlate"]:
		check(heater.get_node_or_null(part) != null, "has its " + part)
	# Clear of the walls: the tank, and the relief pipe down its back.
	var tank_back := heater.position.z - 0.28
	is_true(tank_back > HouseInterior.ZB, "tank clear of the back wall")
	is_true(heater.position.x - 0.28 > -0.98 + 0.05, "tank clear of the kitchen wall")
	var top := heater.position.y + 2.55 + 0.01
	is_true(top < HouseInterior.CEILING, "the pipes and conduit fit under the ceiling")
	var label := heater.find_children("*WarningLabel*", "GeometryInstance3D", true, false)
	eq(label.size(), 1)
	if label.size() == 1:
		eq((label[0] as GeometryInstance3D).cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)


func test_the_roof_stays_on_during_a_job() -> void:
	var roof: Node3D = inside.house["roof"]
	var gable: Node3D = inside.house["gable"]
	check(roof.is_visible_in_tree(), "the roof is still there while you work")
	check(gable.is_visible_in_tree(), "and the gable ends")


## Every rafter sits above the ceiling (never shows in a room) and under the
## roof's underside (never pokes out through the shingles).
func test_rafters_fit_between_the_ceiling_and_the_roof() -> void:
	var top := HouseInterior.CEILING + 0.05          # the ceiling's top face
	var eave_z := inside._d / 2 + Town.ROOF_OVERHANG
	var eave_y := 3.0 - Town.ROOF_EAVE_DROP
	var ridge_y := 3.0 + Town.ROOF_RISE
	var rafters := tree.get_nodes_in_group("rafter").filter(func(n: Node) -> bool: return inside.is_ancestor_of(n))
	check(rafters.size() > 20, "the attic is framed (%d rafters)" % rafters.size())
	for r: MeshInstance3D in rafters:
		var box := r.get_aabb()
		for i in 8:
			var p := inside.to_local(r.global_transform * box.get_endpoint(i))
			var under := ridge_y - (ridge_y - eave_y) * absf(p.z) / eave_z
			check(p.y >= top - 0.001, "rafter corner %.2f above the ceiling top %.2f" % [p.y, top])
			check(p.y <= under + 0.001, "rafter corner %.2f under the roof %.2f at z %.2f" % [p.y, under, p.z])
