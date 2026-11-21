extends "res://tests/test_case.gd"
## The computer at home: TradesmanGear.com (buying truck gear and tools,
## delivered next morning) and your email.

var main: Node
var service: ServiceCall
var screen: ComputerScreen


func before_each() -> void:
	SaveGame.enabled = false
	Engine.time_scale = 0.0
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_node(main)
	service = main.service
	screen = service.computer_screen


func after_each() -> void:
	super()
	Engine.time_scale = 1.0
	SaveGame.enabled = true


func _sit_down() -> void:
	main.town.home_house.computer.on_use.call(main.player)


## The clock moved on to just after tomorrow's delivery time.
func _next_morning() -> void:
	service._minutes = Fatigue.next_time(service._minutes, Upgrades.DELIVERY_HOUR) + 1.0
	service._take_deliveries()


func test_the_computer_opens_the_website() -> void:
	_sit_down()
	is_true(screen.visible, "the desktop's up")
	is_true(main.player.target != null, "you're sitting, not walking")
	screen.close()
	is_false(screen.visible)
	eq(main.player.target, null, "back on your feet")


func test_every_page_draws() -> void:
	_sit_down()
	for cat in ShopItem.CATEGORIES + ["Deals"]:
		screen.go(cat)
		is_false(screen.items_shown().is_empty(), "something on the %s page" % cat)
	for item in ShopItem.all():
		screen.go("item:" + item.id)
	screen.add_to_cart("tool_bag")
	screen.go("cart")
	screen._search = "drill"
	screen.go("search")
	eq(screen.items_shown().map(func(i: ShopItem) -> String: return i.id), ["drill_kit"])
	screen.open_email()
	await tree.process_frame


func test_every_item_has_its_own_picture() -> void:
	for item in ShopItem.all():
		var m := ShopModels.model(item.id)
		check(m.get_child_count() > 1 or item.id == "work_van", "%s isn't the plain grey box" % item.id)
		m.free()


func test_buying_pays_and_it_comes_next_morning() -> void:
	service.wallet.money = 1000
	_sit_down()
	screen.add_to_cart("tool_bag")
	screen.add_to_cart("truck_toolbox")
	screen.place_order()
	eq(service.wallet.money, 1000 - 89 - 349, "paid for both")
	eq(screen.cart().size(), 0, "cart emptied")
	is_true(service.upgrades.ordered("tool_bag"))
	is_false(service.upgrades.can_buy(ShopItem.of("tool_bag")), "one's on its way")
	eq(service.inbox()[0][1], "Order confirmed: $438")
	var room := service.capacity()
	eq(service.inventory.bag_slots, Inventory.BAG_SLOTS, "not here yet")
	_next_morning()
	is_true(service.upgrades.owns("tool_bag"))
	eq(service.inventory.bag_slots, Inventory.BAG_SLOTS + 4, "a bigger bag")
	eq(service.capacity(), room + 4, "room for more on the truck")
	eq(service.supply.capacity(), room + 4, "and the supply house knows it")
	eq(service.inbox()[0][1], "Delivered: your order is here")


func test_not_enough_money() -> void:
	service.wallet.money = 50
	_sit_down()
	screen.add_to_cart("ladder_rack")
	screen.place_order()
	eq(service.wallet.money, 50, "nothing taken")
	eq(screen.cart(), ["ladder_rack"] as Array[String], "still in the cart")
	is_true(screen._note.contains("$499"), screen._note)
	is_false(service.upgrades.ordered("ladder_rack"))


func test_gear_does_its_job() -> void:
	service.wallet.money = 5000
	eq(service.buy_online(["headlamp", "gloves", "light_bar", "work_van"] as Array[String]), "")
	eq(service.wallet.money, 5000 - 39 - 119 - 129 - service.tuning.van_price)
	_next_morning()
	is_true(main.player.has_headlamp, "headlamp")
	is_true(service.inventory.insulated_gloves, "gloves")
	is_true(main.van.light_bar, "light bar")
	eq(main.van.model_name, "van", "the van's in the driveway")


func test_no_delivery_while_youre_driving() -> void:
	service.wallet.money = 5000
	service.buy_online(["work_van"] as Array[String])
	service._minutes = Fatigue.next_time(service._minutes, Upgrades.DELIVERY_HOUR) + 1.0
	main.player.driving = main.van
	service._process(0.0)
	eq(main.van.model_name, "truck", "not swapped under you")
	main.player.driving = null
	service._process(0.0)
	eq(main.van.model_name, "van", "there once you're out")


func test_saved_and_loaded() -> void:
	service.wallet.money = 1000
	service.buy_online(["rolling_toolbox"] as Array[String])
	_next_morning()
	service.buy_online(["headlamp"] as Array[String])
	var saved: Dictionary = JSON.parse_string(JSON.stringify(service.to_save()))
	service.upgrades = Upgrades.new()
	service.mail.clear()
	service._apply_upgrades()
	eq(service.inventory.bag_slots, Inventory.BAG_SLOTS)
	service.load_save(saved)
	is_true(service.upgrades.owns("rolling_toolbox"))
	is_true(service.upgrades.ordered("headlamp"), "still on its way")
	eq(service.inventory.bag_slots, Inventory.BAG_SLOTS + 6, "the bigger bag's back")
	eq(service.mail.size(), 3, "order, delivery, order")
