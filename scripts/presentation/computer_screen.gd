class_name ComputerScreen
extends CanvasLayer
## The computer on your desk at home. You sit down, the view comes in to the
## monitor, and it's a desktop: a browser on TradesmanGear.com (truck gear,
## tools, safety gear and workwear, delivered next morning) and your email
## (orders, deliveries and what customers are saying about you).
##
## The desktop is drawn into its own SubViewport and shown on the monitor's glass
## in the world, so you see the monitor on the desk. Mouse clicks are traced from
## the camera onto the glass and passed in.
##
## The shop itself (prices, paying, what each thing does) is ServiceCall's and
## Upgrades'; this only shows it and says what was clicked.

signal closed

const ORANGE := Color(0.98, 0.58, 0.1)
const GOLD := Color(0.98, 0.73, 0.16)
const TEXT := Color(0.93, 0.94, 0.95)
const DIM := Color(0.62, 0.65, 0.7)
const PAGE := Color(0.09, 0.1, 0.11)
const CARD := Color(0.14, 0.15, 0.17)
const LINE := Color(0.27, 0.29, 0.32)
const BEZEL := Color(0.03, 0.03, 0.035)
const GREEN := Color(0.42, 0.85, 0.42)
## The desktop's resolution, roughly the shape of the monitor's glass.
const SCREEN_PX := Vector2i(1600, 930)

var service: ServiceCall
## The view moving in to the monitor and back, in the world.
var seat_view := Transform3D()
var _cam: Camera3D
var _player_cam: Camera3D
var _app := "browser"            # "browser" or "email"
var _page := "home"              # "home", a category, "item:<id>", "cart", "search"
var _cart: Array[String] = []
var _search := ""
var _note := ""                  # a line at the top of the page: "Order placed..."
var _checked_email := false
var _ordered := false
var _spinners: Array[Node3D] = []

var _root: Control               # beside the monitor: tasks, money, rating
var _vp: SubViewport             # the desktop itself
var _glass: MeshInstance3D       # the monitor's glass, showing _vp
var _glass_size := Vector2.ZERO
var _money: Label
var _rep: Label
var _tasks: VBoxContainer
var _window: VBoxContainer
var _clock: Label
var _tab_title: Label
var _address: Label
var _content: VBoxContainer
var _cart_button: Button


func _ready() -> void:
	layer = 6
	visible = false
	_build()


func _process(delta: float) -> void:
	for s in _spinners:
		if is_instance_valid(s):
			s.rotation.y += delta * 0.5
	if visible and service != null:
		_clock.text = service.date_and_time()


## Sit down: the view moves in to the monitor from wherever you're standing.
## glass: the middle of the monitor's glass (+Z facing you); glass_size: its width and height.
func open(service_: ServiceCall, from: Camera3D, seat: Transform3D, world: Node3D, glass: Transform3D, glass_size: Vector2) -> void:
	service = service_
	_player_cam = from
	seat_view = seat
	if _cam == null:
		_cam = Camera3D.new()
		_cam.fov = 50.0
		world.add_child(_cam)
	if _glass == null:
		_glass = MeshInstance3D.new()
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_texture = _vp.get_texture()
		_glass.material_override = mat
		world.add_child(_glass)
	_glass_size = glass_size
	var quad := QuadMesh.new()
	quad.size = glass_size
	_glass.mesh = quad
	_glass.global_transform = glass
	_glass.visible = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_cam.global_transform = from.global_transform
	_cam.make_current()
	create_tween().tween_property(_cam, "global_transform", seat, 0.6).set_trans(Tween.TRANS_SINE)
	_app = "browser"
	_page = "home"
	_note = ""
	service.hud.visible = false       # the desk has its own money and clock beside the monitor
	visible = true
	refresh()


## Stand back up.
func close() -> void:
	if not visible:
		return
	visible = false
	if service != null:
		service.hud.visible = true
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if _glass != null:
		_glass.visible = false
	if _player_cam != null:
		_player_cam.make_current()
	closed.emit()


## The mouse goes onto the glass and into the desktop; typing goes to the
## desktop while something on it (the search box) has focus.
func _input(event: InputEvent) -> void:
	if not visible or _glass == null or _cam == null:
		return
	if event is InputEventMouse:
		var at := _on_screen(event.position)
		var e: InputEventMouse = event.duplicate()
		e.position = at
		e.global_position = at
		_vp.push_input(e, true)
		if Rect2(Vector2.ZERO, SCREEN_PX).has_point(at):
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and _vp.gui_get_focus_owner() != null and not event.is_action("ui_cancel"):
		_vp.push_input(event, true)
		get_viewport().set_input_as_handled()


## Where a point on the game window lands on the desktop, in desktop pixels
## (off the edges if it misses the glass).
func _on_screen(mouse: Vector2) -> Vector2:
	var xf := _glass.global_transform
	var plane := Plane(xf.basis.z.normalized(), xf.origin)
	var hit: Variant = plane.intersects_ray(_cam.project_ray_origin(mouse), _cam.project_ray_normal(mouse))
	if hit == null:
		return Vector2(-1, -1)
	var local: Vector3 = xf.affine_inverse() * (hit as Vector3)
	return Vector2((local.x / _glass_size.x + 0.5) * SCREEN_PX.x, (0.5 - local.y / _glass_size.y) * SCREEN_PX.y)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


# --- What's on screen ----------------------------------------------------------------------

func refresh() -> void:
	_spinners.clear()
	_money.text = "$%s" % _commas(service.wallet.money)
	_rep.text = "Rating: %s" % service.aftercare.rating_text()
	for c in _tasks.get_children():
		c.queue_free()
	for t: Array in [["Check Email", _checked_email], ["Order Materials", _ordered]]:
		var row := HBoxContainer.new()
		row.add_child(_label("[x]" if t[1] else "[  ]", 18, GREEN if t[1] else DIM))
		row.add_child(_label("  " + t[0], 19, TEXT))
		_tasks.add_child(row)
	for c in _content.get_children():
		c.queue_free()
	if _app == "email":
		_tab_title.text = "Mail"
		_address.text = "mail: inbox"
		_email()
		return
	_tab_title.text = "TradesmanGear.com"
	_address.text = "https://www.tradesmangear.com" + ("" if _page == "home" else "/" + _page.replace(" ", "-").replace("&", "and").to_lower())
	_site()


## The items on the page you're on.
func items_shown() -> Array[ShopItem]:
	var out: Array[ShopItem] = []
	for item in ShopItem.all():
		if _page == "home" or (_page == "Deals" and item.was > 0) or item.category == _page \
				or (_page == "search" and (item.name + " " + item.sub).to_lower().contains(_search.to_lower())):
			out.append(item)
	return out


func cart() -> Array[String]:
	return _cart


# --- Doing things ------------------------------------------------------------------------------

func go(page: String) -> void:
	_app = "browser"
	_page = page
	_note = ""
	refresh()


func add_to_cart(id: String) -> void:
	if not id in _cart and service.upgrades.can_buy(ShopItem.of(id)):
		_cart.append(id)
	refresh()


func remove_from_cart(id: String) -> void:
	_cart.erase(id)
	refresh()


func place_order() -> void:
	var why := service.buy_online(_cart)
	if why == "":
		_note = "Order placed! It'll be at your door tomorrow by %d AM." % int(Upgrades.DELIVERY_HOUR)
		_cart.clear()
		_ordered = true
		_page = "cart"
	else:
		_note = why
	refresh()


func open_email() -> void:
	_app = "email"
	_checked_email = true
	refresh()


# --- The website ------------------------------------------------------------------------------

func _site() -> void:
	# Header: logo, search, account, cart.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 18)
	_content.add_child(head)
	var logo := HBoxContainer.new()
	logo.add_child(UiIcon.make("wrench", 46, ORANGE))
	var brand := VBoxContainer.new()
	brand.add_child(_label("TradesmanGear.com", 30, TEXT))
	brand.add_child(_label("Tools  •  Truck Gear  •  Workwear", 15, DIM))
	logo.add_child(brand)
	var logo_button := _flat(logo)
	logo_button.pressed.connect(go.bind("home"))
	head.add_child(logo_button)
	var search := LineEdit.new()
	search.placeholder_text = "Search tools, truck accessories, and gear..."
	search.custom_minimum_size = Vector2(380, 40)
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	search.text = _search
	search.text_submitted.connect(func(t: String) -> void:
		_search = t
		go("search"))
	head.add_child(search)
	var account := VBoxContainer.new()
	account.add_child(UiIcon.make("person", 28, TEXT))
	account.add_child(_label("Balance $%s" % _commas(service.wallet.money), 14, TEXT))
	head.add_child(account)
	var total := 0
	for id in _cart:
		total += service.shop_price(ShopItem.of(id))
	_cart_button = _button("Cart (%d)  $%s" % [_cart.size(), _commas(total)], ORANGE)
	_cart_button.pressed.connect(go.bind("cart"))
	head.add_child(_cart_button)
	# The menu.
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 4)
	_content.add_child(nav)
	var all_items := _button("Shop All", ORANGE if _page == "home" else TEXT, _page == "home")
	all_items.pressed.connect(go.bind("home"))
	nav.add_child(all_items)
	for cat in ShopItem.CATEGORIES + ["Deals"]:
		var b := _button(cat, ORANGE if _page == cat else TEXT, _page == cat)
		b.pressed.connect(go.bind(cat))
		nav.add_child(b)
	if _note != "":
		_content.add_child(_label(_note, 20, GREEN if _note.begins_with("Order placed") else ORANGE))
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	_content.add_child(body)
	if _page == "cart":
		_cart_page(body)
	elif _page.begins_with("item:"):
		_item_page(body, ShopItem.of(_page.trim_prefix("item:")))
	else:
		_shelf(body)


func _shelf(body: HBoxContainer) -> void:
	# Down the side: what's in this part of the shop.
	var side := _panel(CARD)
	side.custom_minimum_size = Vector2(250, 0)
	body.add_child(side)
	var list := VBoxContainer.new()
	side.add_child(list)
	var title := "Featured" if _page == "home" else ("Results" if _page == "search" else _page)
	list.add_child(_label(title, 22, TEXT))
	var items := items_shown()
	for item in items:
		var link := _button(item.name, TEXT, false, 16)
		link.alignment = HORIZONTAL_ALIGNMENT_LEFT
		link.pressed.connect(go.bind("item:" + item.id))
		list.add_child(link)
	var main := VBoxContainer.new()
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 12)
	body.add_child(main)
	if _page == "home":
		var hero := _panel(Color(0.18, 0.13, 0.09))
		hero.custom_minimum_size = Vector2(0, 150)
		main.add_child(hero)
		var hero_row := HBoxContainer.new()
		hero.add_child(hero_row)
		var words := VBoxContainer.new()
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		words.add_child(_label("Truck Gear", 38, TEXT))
		words.add_child(_label("Built for the Trade", 38, TEXT))
		var shop_truck := _button("Shop Truck Accessories  >", BEZEL, true, 18, ORANGE)
		shop_truck.pressed.connect(go.bind("Truck & Vehicle"))
		words.add_child(shop_truck)
		hero_row.add_child(words)
		hero_row.add_child(Preview3D.make(ShopModels.model("ladder_rack"), Vector2i(300, 140), true, _spinners, Vector3(0.8, 0.4, 1.0)))
		main.add_child(_label("Featured Gear", 24, TEXT))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)
	for item in items:
		grid.add_child(_product_card(item))
	if items.is_empty():
		grid.add_child(_label("Nothing found.", 20, DIM))


func _product_card(item: ShopItem) -> Control:
	var card := _panel(CARD)
	card.custom_minimum_size = Vector2(190, 0)
	var box := VBoxContainer.new()
	card.add_child(box)
	var pic := Button.new()
	pic.flat = true
	pic.focus_mode = Control.FOCUS_NONE
	pic.custom_minimum_size = Vector2(170, 110)
	pic.pressed.connect(go.bind("item:" + item.id))
	var view := Preview3D.make(ShopModels.model(item.id), Vector2i(170, 110), false, _spinners)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pic.add_child(view)
	box.add_child(pic)
	box.add_child(_label(item.name, 17, TEXT))
	box.add_child(_label(item.sub, 14, DIM))
	var price_row := HBoxContainer.new()
	var price := _label("$%s" % _commas(service.shop_price(item)), 22, TEXT)
	price.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	price_row.add_child(price)
	price_row.add_child(_buy_button(item, true))
	box.add_child(price_row)
	box.add_child(_label("%s (%d)" % [_stars(item.stars), item.reviews], 14, GOLD))
	return card


func _item_page(body: HBoxContainer, item: ShopItem) -> void:
	body.add_child(Preview3D.make(ShopModels.model(item.id), Vector2i(460, 380), true, _spinners))
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 10)
	body.add_child(info)
	info.add_child(_label(item.name, 32, TEXT))
	info.add_child(_label(item.sub, 18, DIM))
	info.add_child(_label("%s  %.1f  (%d reviews)" % [_stars(item.stars), item.stars, item.reviews], 18, GOLD))
	var price := "$%s" % _commas(service.shop_price(item))
	if item.was > 0:
		price += "   (was $%d)" % item.was
	info.add_child(_label(price, 30, ORANGE if item.was > 0 else TEXT))
	var about := _label(item.description, 18, TEXT)
	about.autowrap_mode = TextServer.AUTOWRAP_WORD
	about.custom_minimum_size = Vector2(420, 0)
	info.add_child(about)
	info.add_child(_label("Ships free. Delivered to your door tomorrow by %d AM." % int(Upgrades.DELIVERY_HOUR), 16, DIM))
	info.add_child(_buy_button(item, false))


## Add to cart, or why you can't.
func _buy_button(item: ShopItem, small: bool) -> Control:
	var state := ""
	if service.upgrades.owns(item.id) and item.buy_once:
		state = "Owned"
	elif service.upgrades.ordered(item.id):
		state = "Arriving tomorrow"
	elif item.id in _cart:
		state = "In cart"
	if state != "":
		return _label(state, 14 if small else 20, GREEN)
	var b := _button("+ Cart" if small else "Add to Cart", BEZEL, true, 15 if small else 22, ORANGE)
	b.pressed.connect(add_to_cart.bind(item.id))
	return b


func _cart_page(body: HBoxContainer) -> void:
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	body.add_child(list)
	list.add_child(_label("Your Cart", 30, TEXT))
	if _cart.is_empty():
		list.add_child(_label("Your cart is empty.", 20, DIM))
	var total := 0
	for id in _cart:
		var item := ShopItem.of(id)
		total += service.shop_price(item)
		var row := _panel(CARD)
		var line := HBoxContainer.new()
		row.add_child(line)
		line.add_child(Preview3D.make(ShopModels.model(id), Vector2i(110, 70), false, _spinners))
		var name := _label("%s\n%s" % [item.name, item.sub], 18, TEXT)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(name)
		line.add_child(_label("$%s" % _commas(service.shop_price(item)), 22, TEXT))
		var x := _button("Remove", TEXT)
		x.pressed.connect(remove_from_cart.bind(id))
		line.add_child(x)
		list.add_child(row)
	var summary := _panel(CARD)
	summary.custom_minimum_size = Vector2(340, 0)
	body.add_child(summary)
	var s := VBoxContainer.new()
	s.add_theme_constant_override("separation", 10)
	summary.add_child(s)
	s.add_child(_label("Order Summary", 24, TEXT))
	s.add_child(_label("Items: $%s" % _commas(total), 19, TEXT))
	s.add_child(_label("Shipping: FREE (next morning)", 19, GREEN))
	s.add_child(_label("Total: $%s" % _commas(total), 26, TEXT))
	s.add_child(_label("Your balance: $%s" % _commas(service.wallet.money), 17, DIM))
	if not _cart.is_empty():
		var buy := _button("Place Order", BEZEL, true, 22, ORANGE)
		buy.pressed.connect(place_order)
		s.add_child(buy)


# --- Email ----------------------------------------------------------------------------------

func _email() -> void:
	_content.add_child(_label("Inbox", 30, TEXT))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	var mails := service.inbox()
	if mails.is_empty():
		list.add_child(_label("No mail yet.", 20, DIM))
	for m: Array in mails:
		var card := _panel(CARD)
		var box := VBoxContainer.new()
		card.add_child(box)
		box.add_child(_label(m[0], 15, DIM))
		box.add_child(_label(m[1], 20, TEXT))
		var text := _label(m[2], 17, TEXT)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD
		text.custom_minimum_size = Vector2(900, 0)
		box.add_child(text)
		list.add_child(card)


# --- Building it -----------------------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	# The desktop, drawn off-screen and shown on the monitor's glass in the world.
	_vp = SubViewport.new()
	_vp.size = SCREEN_PX
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	var monitor := PanelContainer.new()
	monitor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	monitor.add_theme_stylebox_override("panel", _style(BEZEL, 0, Color(0, 0, 0, 0), 0, 6))
	_vp.add_child(monitor)
	var desktop := VBoxContainer.new()
	monitor.add_child(desktop)
	_window = VBoxContainer.new()
	_window.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_window.add_theme_constant_override("separation", 0)
	desktop.add_child(_window)
	# The window: its tab, the address bar, then the page.
	var tabs := _panel(Color(0.16, 0.17, 0.19), 0)
	_window.add_child(tabs)
	var tab_row := HBoxContainer.new()
	tabs.add_child(tab_row)
	tab_row.add_child(UiIcon.make("wrench", 20, ORANGE))
	_tab_title = _label("TradesmanGear.com", 18, TEXT)
	_tab_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_row.add_child(_tab_title)
	var x := _button("X", TEXT)
	x.pressed.connect(close)
	tab_row.add_child(x)
	var bar := _panel(Color(0.12, 0.13, 0.14), 0)
	_window.add_child(bar)
	var bar_row := HBoxContainer.new()
	bar.add_child(bar_row)
	var back := _button("<", TEXT)
	back.pressed.connect(go.bind("home"))
	bar_row.add_child(back)
	var address_box := _panel(Color(0.2, 0.21, 0.23), 14)
	address_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_row.add_child(address_box)
	_address = _label("", 17, TEXT)
	address_box.add_child(_address)
	var page := _panel(PAGE, 0)
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_window.add_child(page)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 12)
	page.add_child(_content)
	# The taskbar: mail, the shop, the clock.
	var task := _panel(Color(0.1, 0.11, 0.13), 0)
	desktop.add_child(task)
	var task_row := HBoxContainer.new()
	task_row.add_theme_constant_override("separation", 10)
	task.add_child(task_row)
	var mail := _button("Mail", TEXT)
	mail.icon = null
	mail.pressed.connect(open_email)
	task_row.add_child(mail)
	var shop := _button("TradesmanGear", ORANGE)
	shop.pressed.connect(go.bind("home"))
	task_row.add_child(shop)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	task_row.add_child(spacer)
	_clock = _label("", 17, TEXT)
	task_row.add_child(_clock)
	var leave := _button("Stand up  (Esc)", TEXT)
	leave.pressed.connect(close)
	task_row.add_child(leave)
	# Beside the monitor: today's office jobs, the money and your rating.
	var office := _panel(Color(0.05, 0.06, 0.07, 0.92), 12)
	office.position = Vector2(20, 20)
	office.custom_minimum_size = Vector2(215, 0)
	_root.add_child(office)
	var office_box := VBoxContainer.new()
	office.add_child(office_box)
	office_box.add_child(_label("Home Office", 22, GOLD))
	_tasks = VBoxContainer.new()
	office_box.add_child(_tasks)
	var corner := HBoxContainer.new()
	corner.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	corner.position = Vector2(-560, 14)
	corner.add_theme_constant_override("separation", 14)
	_root.add_child(corner)
	var money_box := _panel(Color(0.05, 0.06, 0.07, 0.92), 12)
	_money = _label("", 24, GREEN)
	money_box.add_child(_money)
	corner.add_child(money_box)
	var rep_box := _panel(Color(0.05, 0.06, 0.07, 0.92), 12)
	_rep = _label("", 20, TEXT)
	rep_box.add_child(_rep)
	corner.add_child(rep_box)


# --- Look ----------------------------------------------------------------------------------

static func _commas(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out


static func _stars(n: float) -> String:
	var full := int(n)
	return "*".repeat(full) + ("½" if n - full >= 0.5 else "")


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _style(bg: Color, radius: int, border := Color(0, 0, 0, 0), border_w := 0, margin := 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.border_color = border
	s.set_border_width_all(border_w)
	s.content_margin_left = margin
	s.content_margin_right = margin
	s.content_margin_top = margin * 0.7
	s.content_margin_bottom = margin * 0.7
	return s


func _panel(bg: Color, radius := 10) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _style(bg, radius, LINE if radius > 0 else Color(0, 0, 0, 0), 1 if radius > 0 else 0))
	return p


## A plain clickable wrapper round some content.
func _flat(content: Control) -> Button:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = content.get_combined_minimum_size() + Vector2(10, 64)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(content)
	return b


func _button(text: String, fg: Color, filled := false, size := 18, bg := Color(0, 0, 0, 0)) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg.lightened(0.2) if fg != BEZEL else fg)
	var base := bg if bg.a > 0.0 else (Color(0.2, 0.15, 0.08) if filled else Color(0, 0, 0, 0))
	for state in ["normal", "hover", "pressed"]:
		var c := base.lightened(0.12) if state == "hover" else base
		if c.a == 0.0 and state == "hover":
			c = Color(1, 1, 1, 0.06)
		b.add_theme_stylebox_override(state, _style(c, 8))
	return b
