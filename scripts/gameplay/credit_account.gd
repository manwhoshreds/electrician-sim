class_name CreditAccount
extends RefCounted
## Your account at the supply house: parts now, pay later. They only open one
## for a contractor with enough five-star reviews (JobTuning). The limit is
## the tuning's too, so changing it changes every account.

var open := false
## What you owe them.
var owed := 0


## Would they open an account for you, with this many five-star reviews?
static func would_open(five_stars: int, tuning: JobTuning) -> bool:
	return five_stars >= tuning.credit_five_stars_needed


## How much more you can put on it.
func room(tuning: JobTuning) -> int:
	return maxi(tuning.credit_limit - owed, 0) if open else 0


func can_charge(amount: int, tuning: JobTuning) -> bool:
	return open and amount <= room(tuning)


func charge(amount: int) -> void:
	owed += amount


## Pays down what you can from the wallet. Returns how much went on it.
func pay_down(wallet: Wallet) -> int:
	var paid := mini(owed, maxi(wallet.money, 0))
	wallet.pay(paid)
	owed -= paid
	return paid


## Money back on a return: it comes off what you owe first, then cash.
## Returns the cash part.
func refund(amount: int, wallet: Wallet) -> int:
	var off_account := mini(owed, amount)
	owed -= off_account
	wallet.earn(amount - off_account)
	return amount - off_account


func to_save() -> Dictionary:
	return {"open": open, "owed": owed}


func load_save(d: Dictionary) -> void:
	open = bool(d.get("open", false))
	owed = int(d.get("owed", 0))
