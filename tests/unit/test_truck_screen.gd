extends "res://tests/test_case.gd"
## The truck screen at the tailgate: shelves of what's on board, a picture of
## each part, the job bag along the bottom.

var screen: TruckScreen
var inv: Inventory


func before_each() -> void:
	inv = Inventory.new()
	for i in 10:
		inv.add("Receptacle")
	inv.add("Element")
	inv.add("Battery9V")
	inv.add("Smoke")
	screen = TruckScreen.new()
	add_node(screen)
	screen.open(inv, null, 30)


func test_shows_whats_on_board_by_shelf() -> void:
	var ids := screen.shown().map(func(p: PartSpec) -> String: return p.id)
	is_true("Receptacle" in ids and "breaker20" in ids and "Element" in ids)
	screen._category = "Breakers"
	eq(screen.shown().map(func(p: PartSpec) -> String: return p.id), ["breaker15", "breaker20"])
	eq(screen._load_text.text, "Load:  %d / 30 spaces" % inv.load_used())


func test_click_one_right_click_all_click_slot_back() -> void:
	screen.take("GFCI")
	eq(inv.bag, ["GFCI"] as Array[String])
	screen.take_all("Receptacle")
	eq(inv.bag.size(), Inventory.BAG_SLOTS, "as many as the bag holds")
	eq(screen._bag_title.text, "Job Bag (8 / 8)")
	screen.take("Switch")
	eq(screen._bag_title.text, "Your bag's full.")
	screen.put_back("Receptacle")
	eq(inv.bag.size(), Inventory.BAG_SLOTS - 1)
	screen.clear_bag()
	is_true(inv.hands_empty())
	eq(inv.count("Receptacle"), 11)


func test_every_part_has_a_picture() -> void:
	for p in PartSpec.all():
		var m := screen.part_model(p.id)
		check(not m.find_children("*", "MeshInstance3D", true, false).is_empty(), "%s has a model" % p.id)
		m.free()


func test_done_closes_the_doors() -> void:
	var told := [false]
	screen.closed.connect(func() -> void: told[0] = true)
	screen.close()
	is_false(screen.visible)
	is_true(told[0])
