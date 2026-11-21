extends "res://tests/test_case.gd"
## Finishing a job while you're still inside the house: the house stays open
## round you until you walk out, then goes back to how the street sees it.

var main: Node
var service: ServiceCall


func after_each() -> void:
	super()
	Engine.time_scale = 1.0
	SaveGame.enabled = true


func _job() -> void:
	SaveGame.enabled = false
	Engine.time_scale = 0.0
	seed(9)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_node(main)
	service = main.service
	service.call_generator.catalog.assign([JobType.of("smoke_battery")])
	service.start_job()


func _solid(house: Dictionary) -> bool:
	return (house["body"] as Node).get_children().any(func(c: Node) -> bool: return c is CollisionShape3D and not c.disabled)


func test_finishing_inside_leaves_you_free_to_walk_out() -> void:
	_job()
	var inside := service._inside
	var house := service._house
	main.player.global_position = inside.to_global(Vector3(-2.0, HouseInterior.FLOOR, 1.0))   # the family room
	service._finish()
	is_true(is_instance_valid(inside) and not inside.is_queued_for_deletion(), "the house stays open while you're in it")
	is_false(_solid(house), "and the street's solid stand-in isn't round you")
	is_false((house["shell"] as Node3D).visible, "you still see the real walls, not the outside of the box")
	main.player.global_position = inside.to_global(Vector3(0, 0, inside._d / 2.0 + 3.0))      # out the front, on the lawn
	service._process(0.016)
	is_true(inside.is_queued_for_deletion(), "out the door: now it closes up")
	is_true(_solid(house))
	is_true((house["shell"] as Node3D).visible)


func test_finishing_outside_closes_straight_away() -> void:
	_job()
	var inside := service._inside
	main.player.global_position = inside.to_global(Vector3(0, 0, inside._d / 2.0 + 5.0))
	service._finish()
	is_true(inside.is_queued_for_deletion())
