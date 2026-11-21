extends "res://tests/test_case.gd"
## The testing cheats behind the ` key.

var main: Node
var service: ServiceCall
var cheats: CheatConsole


func before_each() -> void:
	SaveGame.enabled = false
	Engine.time_scale = 0.0
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_node(main)
	service = main.service
	cheats = main.cheats


func after_each() -> void:
	super()
	Engine.time_scale = 1.0
	SaveGame.enabled = true


func test_job_cheat_sends_that_call_next() -> void:
	is_true(cheats.run("job recessed").contains("only sending recessed"))
	service.start_job()
	eq(service.job.kind, "recessed")
	is_true(cheats.run("job nope").contains("No such job"))
	is_true(cheats.run("job any").contains("any kind"))
	is_true(service.call_generator.catalog.size() > 1)


func test_money_and_parts() -> void:
	cheats.run("money 2000")
	eq(service.wallet.money, 2000)
	cheats.run("give Romex 2")
	eq(service.inventory.count("Romex"), 2)
	cheats.run("kit recessed")
	eq(service.inventory.in_bag("GuardStrip"), 2, "in the bag, where the attic work takes them from")
	eq(service.inventory.in_bag("Blank"), 1)
	eq(service.inventory.in_bag("Romex"), 1)
	is_true(cheats.run("give Bananas").contains("No part"))


func test_the_console_stops_you_walking_while_you_type() -> void:
	cheats.open()
	is_true(cheats.is_open())
	eq(main.player.target, cheats)
	cheats.close()
	eq(main.player.target, null)
