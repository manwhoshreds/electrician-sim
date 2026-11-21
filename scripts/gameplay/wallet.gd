class_name Wallet
extends RefCounted
## The business's money. Fines and liability can take it below zero.

var money := 0


func _init(money_ := 0) -> void:
	money = money_


func to_save() -> Dictionary:
	return {"money": money}


func load_save(d: Dictionary) -> void:
	money = int(d.get("money", money))


func can_afford(amount: int) -> bool:
	return money >= amount


func earn(amount: int) -> void:
	money += amount


## Spend or be charged. No check: a fine is a fine.
func pay(amount: int) -> void:
	money -= amount
