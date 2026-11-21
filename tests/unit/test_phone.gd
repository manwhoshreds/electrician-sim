extends "res://tests/test_case.gd"
## Your phone: Tab gets it out, texts come in unread, Messages reads them, and
## every app draws from the business as it stands.

var main: Node
var service: ServiceCall
var phone: PhoneScreen


func before_each() -> void:
	SaveGame.enabled = false
	Engine.time_scale = 0.0
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_node(main)
	service = main.service
	phone = main.phone


func after_each() -> void:
	super()
	Engine.time_scale = 1.0
	SaveGame.enabled = true


func test_tab_gets_it_out_and_puts_it_away() -> void:
	main._get_phone_out()
	is_true(phone.is_open, "it's out")
	eq(main.player.target, phone, "you're looking at it, not walking")
	phone.close()
	is_false(phone.is_open)
	eq(main.player.target, null, "back to walking")


func test_texts_wait_unread_till_you_open_messages() -> void:
	var before := service.unread_texts()
	service.send_text("Dispatch", "New call at 12 Elm St.")
	service.send_text("Mrs. Okafor", "Thanks again!")
	eq(service.unread_texts(), before + 2)
	eq(service.phone_texts()[0][0], "Mrs. Okafor", "newest first")
	main._get_phone_out()
	phone.show_app("messages")
	eq(service.unread_texts(), 0, "read once you've looked")


func test_every_app_draws() -> void:
	main._get_phone_out()
	for app in ["home", "messages", "jobs", "mail", "wallet"]:
		phone.show_app(app)
		await tree.process_frame
		eq(phone.app, app)
	eq(service.phone_wallet()["money"], service.wallet.money)


func test_texts_are_saved() -> void:
	service.send_text("City Inspector", "Fined $50.")
	var saved := service.to_save()
	service.texts.clear()
	service.load_save(saved)
	eq(service.texts[-1]["from"], "City Inspector")
	is_false(service.texts[-1]["read"], "still unread after loading")
