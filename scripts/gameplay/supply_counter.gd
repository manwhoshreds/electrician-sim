class_name SupplyCounter
extends Node
## The parts counter at the supply house, and the conversation with the guy
## behind it: buying, returns, and your credit account. Talking to the clerk
## in the SupplyHouse opens it (open()).
##
## Parts are loaded straight into the vehicle, so it has to be parked out
## front. Paying is cash, or once they've opened you an account, on the
## account up to its limit. Returns come off what you owe before any cash
## comes back, so the account can't be turned into cash.

const SPEAKER := "ELECTRIC SUPPLY"

var dialogue: DialogueBox
var player: Player
var van: Van
var town: Town
var inventory: Inventory
var wallet: Wallet
var credit: CreditAccount
var tuning: JobTuning
var aftercare: Aftercare
## Putting purchases on the account rather than paying cash.
var on_account := false
## Extra room on the truck from gear you've bought (TradesmanGear).
var truck_space := 0


func capacity() -> int:
	return van.spec()["capacity"] + truck_space


func _van_out_front() -> bool:
	return van.global_position.distance_to(town.supply_door) <= tuning.supply_reach


func _refund(p: PartSpec) -> int:
	return int(p.price * (tuning.return_percent / 100.0))


# --- The counter ----------------------------------------------------------------------

## What can I get you? `note` is what he just said, if anything.
func open(_p: Node3D = null, note := "") -> void:
	_ui_open()
	var word: String = van.spec()["word"]
	var line := note if note != "" else "\"What can I get you?\""
	line += "\nYour %s: %d of %d loaded.  You have $%d." % [word, inventory.load_used(), capacity(), wallet.money]
	if credit.open:
		line += "  On account: $%d of $%d." % [credit.owed, tuning.credit_limit]
	if not _van_out_front():
		line += "\nYour %s's not out front. Bring it round to load up." % word
	var options: Array = []
	for p in PartSpec.all():
		options.append(["%s  $%d  (takes %d)" % [p.name, p.price, p.size], _buy.bind(p.id)])
	if inventory.load_used() > 0:
		options.append(["Return some parts (%d%% back)" % int(tuning.return_percent), _open_returns])
	if credit.open:
		options.append(["Paying on my account. I'll pay cash instead." if on_account else "Paying cash. Put it on my account instead.",
				_switch_payment])
		if credit.owed > 0:
			options.append(["Pay down my account ($%d owed)" % credit.owed, _pay_down])
	else:
		options.append(["Could I open a credit account with you?", _apply])
	options.append(["That's all", _ui_close])
	dialogue.say(SPEAKER, line, options)


func _buy(part: String) -> void:
	var p := PartSpec.of(part)
	var word: String = van.spec()["word"]
	var note := ""
	if not _van_out_front():
		note = "\"Pull your %s up out front and I'll load it for you.\"" % word
	elif not inventory.fits(part, capacity()):
		note = "\"That won't fit. Your %s's full.\"" % word
	elif on_account:
		if not credit.can_charge(p.price, tuning):
			note = "\"That'd put you over your $%d limit. You've got $%d left on the account.\"" % [tuning.credit_limit, credit.room(tuning)]
		else:
			credit.charge(p.price)
			inventory.add(part)
			note = "\"One %s, on your account. You owe us $%d.\"" % [p.name, credit.owed]
	elif not wallet.can_afford(p.price):
		note = "\"That's $%d. Come back when you've got it.\"" % p.price
	else:
		wallet.pay(p.price)
		inventory.add(part)
		note = "\"One %s, loaded.\"" % p.name
	open(null, note)


# --- Returns ------------------------------------------------------------------------------

func _open_returns(note := "") -> void:
	var options: Array = []
	for p in PartSpec.all():
		if inventory.count(p.id) > 0:
			options.append(["%s (%d on board)  +$%d" % [p.name, inventory.count(p.id), _refund(p)], _return.bind(p.id)])
	options.append(["Done returning", open])
	var line := note if note != "" else "\"What are you bringing back?\""
	dialogue.say(SPEAKER, line + "\nLoaded: %d of %d." % [inventory.load_used(), capacity()], options)


func _return(part: String) -> void:
	if not _van_out_front():
		_open_returns("\"Bring your %s round and I'll unload it.\"" % van.spec()["word"])
		return
	var p := PartSpec.of(part)
	inventory.remove(part)
	var refund := _refund(p)
	var cash := credit.refund(refund, wallet)
	if cash == refund:
		_open_returns("\"One %s back. That frees up %d.\"" % [p.name, p.size])
	else:
		_open_returns("\"One %s back, $%d off your account. That frees up %d.\"" % [p.name, refund - cash, p.size])


# --- Your account ---------------------------------------------------------------------------

func _apply() -> void:
	var have := aftercare.five_star_reviews()
	var need := tuning.credit_five_stars_needed
	if CreditAccount.would_open(have, tuning):
		credit.open = true
		open(null, "\"Five-star work, and plenty of it. You're approved: a $%d limit. Just say when you want it on the account.\"" % tuning.credit_limit)
	else:
		open(null, "\"We open accounts for contractors with %d five-star reviews. You've got %d. Keep at it and come back.\"" % [need, have])


func _switch_payment() -> void:
	on_account = not on_account
	open(null, "\"On the account it is.\"" if on_account else "\"Cash it is.\"")


func _pay_down() -> void:
	if wallet.money <= 0:
		open(null, "\"You owe us $%d. Come back when you've got the cash.\"" % credit.owed)
		return
	var paid := credit.pay_down(wallet)
	open(null, "\"$%d, thanks. %s\"" % [paid, "You're all square." if credit.owed == 0 else "You still owe $%d." % credit.owed])


# --- Screen handling --------------------------------------------------------------------------

func _ui_open() -> void:
	player.target = dialogue
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _ui_close() -> void:
	dialogue.close()
	player.target = null
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
