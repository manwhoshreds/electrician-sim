extends "res://tests/test_case.gd"
## The supply house: the account rules, the conversation at the counter
## (buying, returns, credit), and the building you walk into.


## Remembers what was said instead of drawing it.
class RecordingDialogue:
	extends DialogueBox
	var said: Array = []

	func _ready() -> void:
		pass

	func say(speaker: String, text: String, options: Array) -> void:
		said.append([speaker, text, options])

	func close() -> void:
		pass

	func line() -> String:
		return said[-1][1]

	func labels() -> Array:
		return (said[-1][2] as Array).map(func(o: Array) -> String: return o[0])

	## Clicks the option starting with these words. False if it isn't there.
	func choose(prefix: String) -> bool:
		for o: Array in said[-1][2]:
			if (o[0] as String).begins_with(prefix):
				(o[1] as Callable).call()
				return true
		return false


var tuning: JobTuning


func before_each() -> void:
	tuning = JobTuning.new()


# --- The account ---------------------------------------------------------------------

func test_account_needs_enough_five_stars() -> void:
	tuning.credit_five_stars_needed = 50
	is_false(CreditAccount.would_open(49, tuning))
	is_true(CreditAccount.would_open(50, tuning))
	tuning.credit_five_stars_needed = 100
	is_false(CreditAccount.would_open(50, tuning), "the knob decides")


func test_account_limit() -> void:
	var a := CreditAccount.new()
	eq(a.room(tuning), 0, "no account, no room")
	is_false(a.can_charge(1, tuning))
	a.open = true
	eq(a.room(tuning), 1500)
	a.charge(1400)
	is_true(a.can_charge(100, tuning))
	is_false(a.can_charge(101, tuning))
	tuning.credit_limit = 1000
	eq(a.room(tuning), 0, "a lower limit leaves nothing, never less than nothing")


func test_paying_down() -> void:
	var a := CreditAccount.new()
	a.open = true
	a.charge(300)
	var w := Wallet.new(100)
	eq(a.pay_down(w), 100, "all you've got")
	eq(a.owed, 200)
	eq(w.money, 0)
	w.earn(500)
	eq(a.pay_down(w), 200)
	eq(a.owed, 0)
	eq(w.money, 300, "only what's owed")


func test_returns_come_off_the_account_first() -> void:
	var a := CreditAccount.new()
	a.open = true
	a.charge(10)
	var w := Wallet.new(0)
	eq(a.refund(16, w), 6, "10 off the account, 6 cash")
	eq(a.owed, 0)
	eq(w.money, 6)


func test_account_saves() -> void:
	var a := CreditAccount.new()
	a.open = true
	a.charge(250)
	var b := CreditAccount.new()
	b.load_save(JSON.parse_string(JSON.stringify(a.to_save())))
	is_true(b.open)
	eq(b.owed, 250)
	eq(typeof(b.owed), TYPE_INT)


# --- At the counter --------------------------------------------------------------------

## A counter with the truck parked out front and a fresh business.
func _counter() -> Array:
	var town := Town.new()             # not built: only supply_door is read
	town.supply_door = Vector3.ZERO
	_nodes.append(town)
	var van := Van.new()
	van.freeze = true                  # parked, and nothing under it to land on
	add_node(van)
	var talk := RecordingDialogue.new()
	_nodes.append(talk)
	var player := Player.new()
	_nodes.append(player)
	var care := Aftercare.new()
	_nodes.append(care)
	var c := SupplyCounter.new()
	_nodes.append(c)
	c.dialogue = talk
	c.player = player
	c.van = van
	c.town = town
	c.inventory = Inventory.new()
	c.inventory.stock = {}
	c.wallet = Wallet.new(100)
	c.credit = CreditAccount.new()
	c.tuning = tuning
	c.aftercare = care
	return [c, talk]


func _five_stars(care: Aftercare, n: int) -> void:
	for i in n:
		care.reviews.append({"address": "%d Elm" % i, "name": "x", "stars": 5, "text": ""})


func test_turned_down_until_youve_earned_it() -> void:
	tuning.credit_five_stars_needed = 3
	var g := _counter()
	var c: SupplyCounter = g[0]
	var talk: RecordingDialogue = g[1]
	_five_stars(c.aftercare, 2)
	c.aftercare.reviews.append({"address": "x", "name": "x", "stars": 4, "text": ""})
	c.open()
	is_true(talk.choose("Could I open a credit account"))
	check(talk.line().begins_with("\"We open accounts for contractors with 3 five-star reviews. You've got 2."), talk.line())
	is_false(c.credit.open)
	_five_stars(c.aftercare, 1)
	talk.choose("Could I open a credit account")
	check(talk.line().begins_with("\"Five-star work"), talk.line())
	is_true(c.credit.open)
	is_false(talk.labels().any(func(l: String) -> bool: return l.begins_with("Could I open")), "no need to ask again")


func test_buying_on_the_account() -> void:
	var g := _counter()
	var c: SupplyCounter = g[0]
	var talk: RecordingDialogue = g[1]
	c.credit.open = true
	c.wallet.money = 0
	c.open()
	is_true(talk.choose("Paying cash. Put it on my account"))
	is_true(c.on_account)
	c._buy("GFCI")
	check(talk.line().begins_with("\"One GFCI receptacle, on your account. You owe us $18.\""), talk.line())
	eq(c.inventory.count("GFCI"), 1)
	eq(c.wallet.money, 0, "no cash changed hands")
	check(talk.line().contains("On account: $18 of $1500."), talk.line())


func test_the_limit_holds() -> void:
	tuning.credit_limit = 30
	var g := _counter()
	var c: SupplyCounter = g[0]
	var talk: RecordingDialogue = g[1]
	c.credit.open = true
	c.on_account = true
	c._buy("GFCI")
	c._buy("GFCI")
	check(talk.line().begins_with("\"That'd put you over your $30 limit. You've got $12 left"), talk.line())
	eq(c.inventory.count("GFCI"), 1)


func test_paying_it_down_at_the_counter() -> void:
	var g := _counter()
	var c: SupplyCounter = g[0]
	var talk: RecordingDialogue = g[1]
	c.credit.open = true
	c.credit.charge(150)
	c.open()
	is_true(talk.choose("Pay down my account ($150 owed)"))
	check(talk.line().begins_with("\"$100, thanks. You still owe $50.\""), talk.line())
	eq(c.wallet.money, 0)
	talk.choose("Pay down my account")
	check(talk.line().begins_with("\"You owe us $50. Come back when you've got the cash.\""), talk.line())


func test_cash_still_works_the_same() -> void:
	var g := _counter()
	var c: SupplyCounter = g[0]
	var talk: RecordingDialogue = g[1]
	c._buy("Fan")
	check(talk.line().begins_with("\"That's $120. Come back when you've got it.\""), "a fan's more than you've got: " + talk.line())
	c._buy("GFCI")
	check(talk.line().begins_with("\"One GFCI receptacle, loaded.\""), talk.line())
	eq(c.wallet.money, 82)


func test_returning_on_an_account_pays_it_back_first() -> void:
	var g := _counter()
	var c: SupplyCounter = g[0]
	var talk: RecordingDialogue = g[1]
	c.credit.open = true
	c.on_account = true
	c._buy("GFCI")
	c._return("GFCI")
	check(talk.line().begins_with("\"One GFCI receptacle back, $16 off your account."), talk.line())
	eq(c.credit.owed, 2)
	eq(c.wallet.money, 100, "no cash from a part bought on credit")


func test_the_clerk_needs_the_truck_out_front() -> void:
	var g := _counter()
	var c: SupplyCounter = g[0]
	var talk: RecordingDialogue = g[1]
	c.van.global_position = Vector3(100, 0, 0)
	c._buy("GFCI")
	check(talk.line().begins_with("\"Pull your truck up out front"), talk.line())


# --- The building ----------------------------------------------------------------------

## Is anything solid between these two points (in the store's own space)?
func _blocked(store: SupplyHouse, a: Vector3, b: Vector3) -> bool:
	var space := store.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(store.to_global(a), store.to_global(b))
	return not space.intersect_ray(q).is_empty()


func test_you_can_walk_in_the_door_but_not_through_the_walls() -> void:
	var store := SupplyHouse.new()
	add_node(store)
	await tree.physics_frame
	await tree.physics_frame
	var outside := store.size.z / 2 + 1.0
	var inside := 1.0
	var y := 1.0
	is_false(_blocked(store, Vector3(SupplyHouse.DOOR_X, y, outside), Vector3(SupplyHouse.DOOR_X, y, inside)), "in through the doorway")
	is_true(_blocked(store, Vector3(-2.0, y + 0.5, outside), Vector3(-2.0, y + 0.5, inside)), "not through the window")
	is_true(_blocked(store, Vector3(0, y, -store.size.z / 2 - 1.0), Vector3(0, y, 0)), "not through the back wall")
	is_true(_blocked(store, Vector3(store.size.x / 2 + 1.0, y, 0), Vector3(0, y, 0)), "not through the side")
	is_true(_blocked(store, Vector3(-1.0, 0.5, 0.5), Vector3(-1.0, 0.5, SupplyHouse.COUNTER_Z - 1.0)), "not over the counter")


func test_the_parts_guy_is_behind_the_counter() -> void:
	var store := SupplyHouse.new()
	add_node(store)
	var clerk := store.clerk
	check(clerk != null, "there's someone there")
	eq(clerk.person_name, SupplyHouse.CLERK_NAME)
	is_true(clerk.position.z < SupplyHouse.COUNTER_Z, "on the far side of it")
	is_false(clerk.waving)
	var you := Node3D.new()
	add_node(you)
	you.global_position = store.to_global(Vector3(clerk.position.x, 0.09, SupplyHouse.COUNTER_Z + 0.9))
	is_true(clerk.can_use(you), "you can talk to him across the counter")


func test_the_parts_guy_always_looks_the_same_and_leaves_the_dice_alone() -> void:
	seed(42)
	var before := randi()
	seed(42)
	var store := SupplyHouse.new()
	add_node(store)
	eq(randi(), before, "building him didn't roll the game's dice")
