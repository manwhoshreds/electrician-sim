class_name TruckScreen
extends CanvasLayer
## The truck's inventory, at the tailgate: everything on board on shelves by
## category, each with a picture of the real part (the game's own models,
## turning in a little window), its details, and the job bag along the bottom
## that you fill to carry into the house. The game stays visible behind it.
##
## Click a part: one into the bag. Right click: as many as fit. Click a bag
## slot: put it back. Esc or Done: close the doors.

signal closed

const GOLD := Color(0.98, 0.73, 0.16)
const TEXT := Color(0.93, 0.94, 0.95)
const DIM := Color(0.66, 0.69, 0.73)
const CARD := Color(0.06, 0.07, 0.08, 0.9)
const TILE := Color(0.11, 0.12, 0.13, 0.95)
const LINE := Color(0.3, 0.31, 0.33, 0.9)

## The game's models for each part: [file, [nodes in it]] or [file] for the whole scene.
const INTERIOR := "res://assets/interior/interior.glb"
const SMOKE := "res://assets/smoke_detector/smoke_detector.glb"
const MODELS := {
	"Receptacle": [INTERIOR, ["Duplex"]], "GFCI": [INTERIOR, ["GFCIDevice", "GFCITest", "GFCIReset"]],
	"Switch": [INTERIOR, ["SwitchDevice", "SwitchLever"]], "Dimmer": [INTERIOR, ["DimmerDevice"]],
	"ThreeWay": [INTERIOR, ["ThreeWayDevice", "SwitchLever"]], "Range": [INTERIOR, ["RangeDevice"]],
	"Fixture": [INTERIOR, ["FixtureCanopy", "FixtureBulb", "FixtureShade"]], "Fan": [INTERIOR, ["FanBody", "FanBlades"]],
	"OldWork": [INTERIOR, ["DeviceBox"]], "Smoke": [SMOKE, ["SmokeDetector", "SmokeLED"]],
	"breaker15": ["res://assets/panel/breaker_1p.glb"], "breaker20": ["res://assets/panel/breaker_1p.glb"],
	"breaker30": ["res://assets/panel/breaker_2p.glb"],
}

var inventory: Inventory
var _vehicle := "truck"
var _capacity := 8
var _category := ""              # "" is All Items
var _selected := ""
var _libs := {}                  # file -> an instance to copy models out of
var _root: Control
var _title: Label
var _load_text: Label
var _load_bar: ProgressBar
var _categories: VBoxContainer
var _grid: GridContainer
var _detail: VBoxContainer
var _bag_title: Label
var _bag_slots: GridContainer
var _spinners: Array[Node3D] = []


func _ready() -> void:
	layer = 6
	visible = false
	_build()


func _exit_tree() -> void:
	for lib: Node in _libs.values():
		if is_instance_valid(lib):
			lib.free()


func open(inventory_: Inventory, van: Van, capacity: int) -> void:
	inventory = inventory_
	_vehicle = van.spec()["word"] if van != null else "truck"
	_capacity = capacity
	if _selected == "" or (inventory.count(_selected) == 0 and not inventory.has(_selected)):
		_selected = _first_on_board()
	visible = true
	refresh()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact")):
		close()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	for s in _spinners:
		if is_instance_valid(s):
			s.rotation.y += delta * 0.6


# --- What's shown ---------------------------------------------------------------------

## The parts to show on the shelf you're looking at: on board, or in your bag.
func shown() -> Array[PartSpec]:
	var out: Array[PartSpec] = []
	for p in PartSpec.all():
		if (inventory.count(p.id) > 0 or inventory.has(p.id)) and (_category == "" or p.category == _category):
			out.append(p)
	return out


func _first_on_board() -> String:
	for p in PartSpec.all():
		if inventory.count(p.id) > 0:
			return p.id
	return ""


## Everything on screen, rebuilt from the inventory.
func refresh() -> void:
	_spinners.clear()
	_title.text = "%s Inventory" % _vehicle.capitalize()
	var used := inventory.load_used()
	_load_text.text = "Load:  %d / %d spaces" % [used, _capacity]
	_load_bar.max_value = _capacity
	_load_bar.value = used
	for c in _categories.get_children():
		c.queue_free()
	_category_button("All Items", "")
	for cat in PartSpec.CATEGORIES:
		if PartSpec.all().any(func(p: PartSpec) -> bool: return p.category == cat and (inventory.count(p.id) > 0 or inventory.has(p.id))):
			_category_button(cat, cat)
	for c in _grid.get_children():
		c.queue_free()
	var parts := shown()
	for p in parts:
		_grid.add_child(_tile(p))
	if parts.is_empty():
		var empty := _label("Nothing on board%s. Stock up at the supply house downtown." % ("" if _category == "" else " here"), 20, DIM)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD
		empty.custom_minimum_size = Vector2(700, 0)
		_grid.add_child(empty)
	_fill_detail()
	_bag_title.text = "Job Bag (%d / %d)" % [inventory.bag.size(), inventory.bag_slots]
	for c in _bag_slots.get_children():
		c.queue_free()
	for i in inventory.bag_slots:
		_bag_slots.add_child(_bag_slot(inventory.bag[i] if i < inventory.bag.size() else ""))


# --- Doing things -------------------------------------------------------------------------

## One into the bag. Says why not, if it can't.
func take(part: String) -> void:
	_selected = part
	var why := ""
	if inventory.bag_full():
		why = "Your bag's full."
	elif not inventory.take(part):
		why = "None left on the %s." % _vehicle
	refresh()
	_flash(why)


func take_all(part: String) -> void:
	_selected = part
	var why := ""
	if inventory.take_all(part) == 0:
		why = "Your bag's full." if inventory.bag_full() else "None left on the %s." % _vehicle
	refresh()
	_flash(why)


func put_back(part: String) -> void:
	inventory.put_back(part)
	refresh()


func clear_bag() -> void:
	inventory.clear_bag()
	refresh()


## A word about why that didn't work, where the bag's title is, till the next change.
func _flash(text: String) -> void:
	if text != "":
		_bag_title.text = text


# --- Building it ---------------------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.45)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(shade)
	var page := MarginContainer.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		page.add_theme_constant_override("margin_" + side, 40)
	_root.add_child(page)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 18)
	page.add_child(rows)

	# Title on the left, the load on the right.
	var top := HBoxContainer.new()
	rows.add_child(top)
	var head := _card(Color(0, 0, 0, 0))
	top.add_child(head)
	var head_row := HBoxContainer.new()
	head_row.add_theme_constant_override("separation", 16)
	head.add_child(head_row)
	var badge := _panel(Color(0.03, 0.03, 0.03, 0.95), 10, GOLD.darkened(0.3))
	badge.custom_minimum_size = Vector2(84, 84)
	badge.add_child(UiIcon.make("box", 52, GOLD))
	head_row.add_child(badge)
	var words := VBoxContainer.new()
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	head_row.add_child(words)
	_title = _label("Truck Inventory", 40, TEXT)
	words.add_child(_title)
	words.add_child(_label("Select items to take to the job site", 20, DIM))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	var load_card := _card(CARD)
	load_card.custom_minimum_size = Vector2(380, 0)
	top.add_child(load_card)
	var load_box := VBoxContainer.new()
	load_card.add_child(load_box)
	_load_text = _label("", 22, TEXT)
	_load_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	load_box.add_child(_load_text)
	_load_bar = ProgressBar.new()
	_load_bar.show_percentage = false
	_load_bar.custom_minimum_size = Vector2(0, 14)
	_load_bar.add_theme_stylebox_override("background", _style(Color(0.25, 0.25, 0.27), 7))
	_load_bar.add_theme_stylebox_override("fill", _style(GOLD, 7))
	load_box.add_child(_load_bar)

	# The shelves, the parts, and the details.
	var middle := HBoxContainer.new()
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.add_theme_constant_override("separation", 18)
	rows.add_child(middle)
	var side := _card(CARD)
	side.custom_minimum_size = Vector2(260, 0)
	middle.add_child(side)
	_categories = VBoxContainer.new()
	_categories.add_theme_constant_override("separation", 6)
	side.add_child(_categories)
	var shelf := _card(CARD)
	shelf.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.add_child(shelf)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	shelf.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(_grid)
	var detail_card := _card(CARD)
	detail_card.custom_minimum_size = Vector2(380, 0)
	middle.add_child(detail_card)
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 8)
	detail_card.add_child(_detail)

	# Keys on the left, the bag in the middle, the buttons on the right.
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 18)
	rows.add_child(bottom)
	var keys := VBoxContainer.new()
	keys.alignment = BoxContainer.ALIGNMENT_CENTER
	keys.custom_minimum_size = Vector2(260, 0)
	bottom.add_child(keys)
	for k: Array in [["Click", "Add to job bag"], ["Right click", "Take all"], ["Click bag slot", "Put it back"], ["Esc", "Done"]]:
		var row := HBoxContainer.new()
		var key := _panel(Color(0.18, 0.18, 0.2, 0.95), 6, GOLD.darkened(0.2))
		key.add_child(_label(k[0], 15, GOLD))
		row.add_child(key)
		row.add_child(_label("  " + k[1], 17, TEXT))
		keys.add_child(row)
	var bag := _card(CARD)
	bag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(bag)
	var bag_box := VBoxContainer.new()
	bag.add_child(bag_box)
	_bag_title = _label("Job Bag", 22, TEXT)
	bag_box.add_child(_bag_title)
	_bag_slots = GridContainer.new()
	_bag_slots.columns = 9
	_bag_slots.add_theme_constant_override("h_separation", 8)
	_bag_slots.add_theme_constant_override("v_separation", 8)
	bag_box.add_child(_bag_slots)
	var buttons := _card(CARD)
	bottom.add_child(buttons)
	var button_row := HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_theme_constant_override("separation", 14)
	buttons.add_child(button_row)
	var clear := _button("Clear Bag", false)
	clear.pressed.connect(clear_bag)
	button_row.add_child(clear)
	var done := _button("Done", true)
	done.pressed.connect(close)
	button_row.add_child(done)


func _category_button(text: String, cat: String) -> void:
	var b := _button(text, cat == _category)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 48)
	b.pressed.connect(func() -> void:
		_category = cat
		refresh())
	_categories.add_child(b)


## A part on the shelf: its picture, name, and how many are on board.
func _tile(p: PartSpec) -> Control:
	var tile := Button.new()
	tile.custom_minimum_size = Vector2(210, 190)
	tile.focus_mode = Control.FOCUS_NONE
	var chosen := p.id == _selected
	for state in ["normal", "hover", "pressed"]:
		tile.add_theme_stylebox_override(state, _style(TILE.lightened(0.06 if state == "hover" else 0.0), 10,
				GOLD if chosen else LINE, 3 if chosen else 1))
	tile.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			if e.button_index == MOUSE_BUTTON_LEFT:
				take(p.id)
			elif e.button_index == MOUSE_BUTTON_RIGHT:
				take_all(p.id))
	tile.mouse_entered.connect(func() -> void:
		if _selected != p.id:
			_selected = p.id
			_fill_detail())
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(box)
	var pic := _preview(p.id, Vector2i(194, 110), false)
	box.add_child(pic)
	var name_row := HBoxContainer.new()
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name_row)
	var name := _label(p.short_name(), 18, TEXT)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(name)
	var count := _panel(Color(0.02, 0.02, 0.02, 0.9), 5, LINE)
	count.add_child(_label("x%d" % inventory.count(p.id), 18, TEXT))
	name_row.add_child(count)
	var bagged := inventory.in_bag(p.id)
	box.add_child(_label(("%d in your bag" % bagged) if bagged > 0 else p.category, 14, GOLD if bagged > 0 else DIM))
	return tile


func _fill_detail() -> void:
	for c in _detail.get_children():
		c.queue_free()
	if _selected == "":
		_detail.add_child(_label("The %s's empty." % _vehicle, 20, DIM))
		return
	var p := PartSpec.of(_selected)
	_detail.add_child(_preview(p.id, Vector2i(340, 230), true))
	_detail.add_child(_label(p.name, 26, TEXT))
	_detail.add_child(_label(p.category, 18, DIM))
	var rule := ColorRect.new()
	rule.color = LINE
	rule.custom_minimum_size = Vector2(0, 1)
	_detail.add_child(rule)
	for row: Array in [["On the %s:" % _vehicle, str(inventory.count(p.id))], ["In your bag:", str(inventory.in_bag(p.id))],
			["Takes up:", "%d space%s" % [p.size, "" if p.size == 1 else "s"]], ["Supply house price:", "$%d" % p.price]]:
		var line := HBoxContainer.new()
		var k := _label(row[0], 19, TEXT)
		k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(k)
		line.add_child(_label(row[1], 19, TEXT))
		_detail.add_child(line)
	var about := _label(p.description, 17, DIM)
	about.autowrap_mode = TextServer.AUTOWRAP_WORD
	about.custom_minimum_size = Vector2(340, 0)
	_detail.add_child(about)


func _bag_slot(part: String) -> Control:
	var slot := Button.new()
	slot.custom_minimum_size = Vector2(92, 80)
	slot.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed", "disabled"]:
		slot.add_theme_stylebox_override(state, _style(TILE.lightened(0.06 if state == "hover" and part != "" else 0.0), 8, LINE))
	if part == "":
		slot.disabled = true
		return slot
	slot.tooltip_text = "%s: click to put it back" % PartSpec.of(part).name
	slot.pressed.connect(put_back.bind(part))
	var pic := _preview(part, Vector2i(84, 72), false)
	pic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 4)
	slot.add_child(pic)
	return slot


# --- Pictures of the parts ---------------------------------------------------------------------

func _preview(part: String, size_px: Vector2i, spin: bool) -> Control:
	return Preview3D.make(part_model(part), size_px, spin, _spinners)


## The part's model: the game's own where there is one, a simple one where not.
func part_model(part: String) -> Node3D:
	if part in ["Wafer", "Blank", "Romex", "GuardStrip"]:
		return RecessedModels.part_model(part)
	var root := Node3D.new()
	if MODELS.has(part):
		var spec: Array = MODELS[part]
		if spec.size() == 1:
			root.add_child((load(spec[0]) as PackedScene).instantiate())
		else:
			var lib := _lib(spec[0])
			for n: String in spec[1]:
				var copy := lib.get_node(n).duplicate() as Node3D
				copy.transform = Transform3D.IDENTITY
				root.add_child(copy)
		if part == "Smoke":
			for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
				for i in mi.mesh.get_surface_count():
					var m := mi.mesh.surface_get_material(i) as BaseMaterial3D
					if m != null:
						m.vertex_color_use_as_albedo = true
		return root
	match part:
		"Battery9V":
			_block(root, Vector3(0.026, 0.048, 0.017), Vector3.ZERO, Color(0.1, 0.2, 0.5))
			_block(root, Vector3(0.026, 0.012, 0.0172), Vector3(0, -0.016, 0), Color(0.75, 0.62, 0.15))
			_block(root, Vector3(0.007, 0.004, 0.007), Vector3(-0.006, 0.026, 0), Color(0.75, 0.76, 0.78))
			_block(root, Vector3(0.008, 0.004, 0.008), Vector3(0.006, 0.026, 0), Color(0.75, 0.76, 0.78))
		"Element":
			var hex := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.024
			cyl.bottom_radius = 0.024
			cyl.height = 0.01
			cyl.radial_segments = 6
			hex.mesh = cyl
			hex.material_override = _mat(Color(0.7, 0.71, 0.73), 0.9)
			root.add_child(hex)
			for x in [-0.008, 0.008]:
				var rod := MeshInstance3D.new()
				var r := CylinderMesh.new()
				r.top_radius = 0.004
				r.bottom_radius = 0.004
				r.height = 0.26
				rod.mesh = r
				rod.material_override = _mat(Color(0.72, 0.5, 0.3), 0.8)
				rod.position = Vector3(x, -0.135, 0)
				root.add_child(rod)
			_block(root, Vector3(0.024, 0.006, 0.006), Vector3(0, -0.265, 0), Color(0.72, 0.5, 0.3))
			root.rotation.z = PI / 2       # lying along the shelf
		"GardenHose":
			var coil := MeshInstance3D.new()
			var torus := TorusMesh.new()
			torus.inner_radius = 0.035
			torus.outer_radius = 0.06
			coil.mesh = torus
			coil.material_override = _mat(Color(0.15, 0.55, 0.2), 0.5)
			coil.rotation.x = PI / 2
			root.add_child(coil)
			_block(root, Vector3(0.018, 0.022, 0.018), Vector3(0.06, 0, 0.0), Color(0.75, 0.62, 0.15))   # the brass fitting
		_:
			_block(root, Vector3(0.05, 0.05, 0.05), Vector3.ZERO, Color(0.6, 0.6, 0.6))
	return root


func _lib(file: String) -> Node:
	if not _libs.has(file):
		_libs[file] = (load(file) as PackedScene).instantiate()
	return _libs[file]


func _block(parent: Node3D, size: Vector3, at: Vector3, c: Color) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = _mat(c, 0.2)
	mi.position = at
	parent.add_child(mi)


static func _mat(c: Color, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = 0.4
	return m


# --- Look ------------------------------------------------------------------------------------

func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _style(bg: Color, radius: int, border := Color(0, 0, 0, 0), border_w := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.border_color = border
	s.set_border_width_all(border_w if border.a > 0.0 else 0)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


func _panel(bg: Color, radius: int, border := Color(0, 0, 0, 0)) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", _style(bg, radius, border, 1))
	return p


func _card(bg: Color) -> PanelContainer:
	var c := _panel(bg, 12, LINE if bg.a > 0.0 else Color(0, 0, 0, 0))
	c.add_theme_stylebox_override("panel", _style(bg, 12, LINE if bg.a > 0.0 else Color(0, 0, 0, 0), 1))
	return c


func _button(text: String, gold: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(150, 54)
	b.add_theme_font_size_override("font_size", 21)
	var fg := GOLD if gold else TEXT
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg)
	for state in ["normal", "hover", "pressed"]:
		var bg := Color(0.08, 0.07, 0.03, 0.95) if gold else Color(0.14, 0.15, 0.16, 0.95)
		b.add_theme_stylebox_override(state, _style(bg.lightened(0.08 if state == "hover" else 0.0), 10, GOLD if gold else LINE, 2 if gold else 1))
	return b
