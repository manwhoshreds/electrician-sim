class_name CeilingLayout
extends Node3D
## Laying out recessed lights: you on the floor with a tape measure and a
## pencil, looking straight up at the ceiling. Wherever the cursor is, the
## tape runs out to all four walls and reads the distances in feet and
## inches. Click to put a pencil X there; right click rubs one out. Line a
## new mark up with one you've made and it snaps to it, like a chalk line.
##
## Lives in HouseInterior's space: `room` is the ceiling's rectangle there
## (x along position.x, y along position.z), `ceiling` its height.
## Nothing's cut till you're done: Enter hands the marks back through `done`.

signal done(marks: Array)

const KEYS := [["LMB", "Pencil Mark"], ["RMB", "Rub Out"], ["Shift", "No Snap"], ["Enter", "Done"], ["Esc", "Step Back"]]
const SNAP := 0.0127              # half an inch
const LINE_UP := 0.03             # how close to a mark's line before it snaps on (just over an inch)
const KEEP_CLEAR := 0.2           # from the old light's box and the smoke detector

var room: Rect2
var ceiling := 0.0
var floor_y := 0.0
var count := 4
## [x, z] points nothing goes on: the old light's box, the smoke detector.
var obstacles: Array = []
## What each wall's called, low x, high x, low z, high z.
var wall_names := ["bath wall", "outside wall", "back wall", "closet wall"]
var marks: Array = []

var _open := false
var _player: Node3D
var _cam: Camera3D
var _lamp: OmniLight3D
var _ui: CanvasLayer
var _overlay: Control
var _info: Label
var _cursor := Vector2.INF        # on the ceiling, x/z; INF off it
var _snapped := [false, false]    # lined up with another mark across x, along z


func _ready() -> void:
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.near = 0.05
	_cam.far = 4.0
	add_child(_cam)
	_lamp = OmniLight3D.new()
	_lamp.light_energy = 0.9
	_lamp.omni_range = 6.0
	_lamp.visible = false
	add_child(_lamp)
	_ui = CanvasLayer.new()
	_ui.layer = 2
	_ui.visible = false
	add_child(_ui)
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	_ui.add_child(_overlay)
	# What the tape says about the room, in a card bottom left, over the key hints.
	var card := PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	card.offset_left = 24
	card.offset_bottom = -84
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.1, 0.88)
	style.border_color = Color(0.95, 0.75, 0.2)
	style.border_width_left = 4
	style.set_corner_radius_all(10)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	card.add_theme_stylebox_override("panel", style)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(card)
	_info = Label.new()
	_info.add_theme_font_size_override("font_size", 18)
	_info.add_theme_color_override("font_color", Color(0.95, 0.95, 0.92))
	card.add_child(_info)


func open(p: Node3D) -> void:
	_player = p
	_open = true
	p.target = self
	if p.get("hud") != null:
		p.hud.set_closeup(true, KEYS)
	var c := room.get_center()
	_cam.position = Vector3(c.x, floor_y + 1.0, c.y)
	_cam.basis = Basis.looking_at(Vector3.UP, Vector3.FORWARD)     # straight up, the back wall at the top of the screen
	var vp := get_viewport().get_visible_rect().size
	var aspect := vp.x / maxf(vp.y, 1.0)
	_cam.size = maxf(room.size.y, room.size.x / aspect) * 1.18
	_cam.make_current()
	_lamp.position = Vector3(c.x, floor_y + 1.2, c.y)
	_lamp.visible = true
	_ui.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	_open = false
	_lamp.visible = false
	_ui.visible = false
	if _player != null:
		_player.target = null
		if _player.get("hud") != null:
			_player.hud.set_closeup(false)
		if _player.get("camera") != null:
			(_player.camera as Camera3D).make_current()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func is_open() -> bool:
	return _open


func _process(_delta: float) -> void:
	if not _open:
		return
	_cursor = _ceiling_point(get_viewport().get_mouse_position())
	if _cursor != Vector2.INF and not Input.is_key_pressed(KEY_SHIFT):
		_cursor = snapped_point(_cursor)
	else:
		_snapped = [false, false]
	_info.text = _info_text()
	_overlay.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and (event.physical_keycode == KEY_ENTER or event.physical_keycode == KEY_KP_ENTER):
		if marks.size() == count:
			close()
			done.emit(marks.duplicate(true))
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		var at := _ceiling_point(event.position)
		if at != Vector2.INF:
			if event.button_index == MOUSE_BUTTON_LEFT:
				place(_cursor if _cursor != Vector2.INF else at)
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				rub_out(at)
		get_viewport().set_input_as_handled()


# --- The marks -----------------------------------------------------------------------

## A pencil X here. "" if it went down, or why not.
func place(at: Vector2) -> String:
	if marks.size() >= count:
		return "full"
	if not room.grow(-0.05).has_point(at):
		return "wall"
	for o: Array in obstacles:
		if at.distance_to(Vector2(o[0], o[1])) < KEEP_CLEAR:
			return "obstacle"
	for m: Array in marks:
		if at.distance_to(Vector2(m[0], m[1])) < 0.25:
			return "too_close"
	marks.append([at.x, at.y])
	return ""


func rub_out(at: Vector2) -> void:
	var best := -1
	var best_d := 0.25
	for i in marks.size():
		var d := at.distance_to(Vector2(marks[i][0], marks[i][1]))
		if d < best_d:
			best = i
			best_d = d
	if best >= 0:
		marks.remove_at(best)


## To the nearest half inch from the walls, and onto another mark's line if
## it's close: square with the room, the way a chalk line does it.
func snapped_point(at: Vector2) -> Vector2:
	var p := Vector2(room.position.x + snappedf(at.x - room.position.x, SNAP), room.position.y + snappedf(at.y - room.position.y, SNAP))
	_snapped = [false, false]
	for m: Array in marks:
		if absf(at.x - float(m[0])) < LINE_UP:
			p.x = float(m[0])
			_snapped[0] = true
		if absf(at.y - float(m[1])) < LINE_UP:
			p.y = float(m[1])
			_snapped[1] = true
	var c := room.get_center()
	if not _snapped[0] and absf(at.x - c.x) < LINE_UP * 0.5:
		p.x = c.x
	if not _snapped[1] and absf(at.y - c.y) < LINE_UP * 0.5:
		p.y = c.y
	return p


## Where the mouse is pointing on the ceiling, x/z, or INF if it's off it.
func _ceiling_point(mouse: Vector2) -> Vector2:
	var from := _cam.project_ray_origin(mouse)
	var dir := _cam.project_ray_normal(mouse)
	if absf(dir.y) < 0.001:
		return Vector2.INF
	var t := (ceiling - to_local(from).y) / dir.y
	var hit := to_local(from) + dir * t
	var p := Vector2(hit.x, hit.z)
	return p if room.has_point(p) else Vector2.INF


# --- Grading ---------------------------------------------------------------------------

## What the customer will make of the layout, in their words: [] if it's
## right. Four lights in a rectangle, square with the walls, centred in the
## room, about a quarter of the way in from each wall.
static func flaws(marks_: Array, room_: Rect2) -> Array[String]:
	var out: Array[String] = []
	if marks_.size() != 4:
		return out
	var xs: Array = marks_.map(func(m: Array) -> float: return float(m[0]))
	var zs: Array = marks_.map(func(m: Array) -> float: return float(m[1]))
	xs.sort()
	zs.sort()
	var lined := absf(xs[0] - xs[1]) < 0.04 and absf(xs[2] - xs[3]) < 0.04 and absf(zs[0] - zs[1]) < 0.04 and absf(zs[2] - zs[3]) < 0.04
	if not lined:
		out.append("The lights aren't in straight lines. I notice it every time I look up.")
		return out
	var cols := [(xs[0] + xs[1]) / 2.0, (xs[2] + xs[3]) / 2.0]
	var rows := [(zs[0] + zs[1]) / 2.0, (zs[2] + zs[3]) / 2.0]
	var c := room_.get_center()
	if absf((cols[0] + cols[1]) / 2.0 - c.x) > 0.076 or absf((rows[0] + rows[1]) / 2.0 - c.y) > 0.076:
		out.append("They're not centred in the room. It's all bunched toward one side.")
	var bunched := false
	var crowding := false
	for pair: Array in [[cols, room_.position.x, room_.end.x], [rows, room_.position.y, room_.end.y]]:
		var a: Array = pair[0]
		var spacing: float = a[1] - a[0]
		var off: float = minf(a[0] - float(pair[1]), float(pair[2]) - a[1])
		if spacing < 0.9 or off > spacing * 0.75:
			bunched = true
		elif off < 0.45 or off < spacing * 0.3:
			crowding = true
	if bunched:
		out.append("They're all crowded in the middle. The corners of the room are dark.")
	elif crowding:
		out.append("They're so close to the walls. It just lights up the walls.")
	return out


# --- Feet and inches -------------------------------------------------------------------

## 1.2 m -> 3' 11 1/4", to the nearest quarter inch.
static func feet_inches(metres: float) -> String:
	var quarters := roundi(metres / 0.0254 * 4.0)
	var feet := quarters / 48
	var rest := quarters % 48
	var inches := rest / 4
	var frac: String = ["", " 1/4", " 1/2", " 3/4"][rest % 4]
	return "%d' %d%s\"" % [feet, inches, frac]


func _info_text() -> String:
	var lines: Array[String] = []
	lines.append("ROOM  %s x %s   ceiling %s" % [feet_inches(room.size.x), feet_inches(room.size.y), feet_inches(ceiling - floor_y)])
	lines.append("Rule of thumb: space them about half the ceiling height apart, and half that off the walls.")
	lines.append("For four in a square room: a quarter of the way in from each wall.")
	lines.append("Pencil marks: %d of %d%s" % [marks.size(), count, "   Enter when you're happy" if marks.size() == count else ""])
	return "\n".join(lines)


func _draw_overlay() -> void:
	var font := ThemeDB.fallback_font
	var tape := Color(1.0, 0.82, 0.1)
	var pencil := Color(0.12, 0.12, 0.14)
	for m: Array in marks:
		_draw_x(Vector2(m[0], m[1]), pencil, 9.0)
	if _cursor == Vector2.INF:
		return
	var p := _cursor
	var ends := [Vector2(room.position.x, p.y), Vector2(room.end.x, p.y), Vector2(p.x, room.position.y), Vector2(p.x, room.end.y)]
	for i in 4:
		var a := _screen(p)
		var b := _screen(ends[i])
		_overlay.draw_line(a, b, tape, 3.0)
		var text := "%s  to the %s" % [feet_inches(p.distance_to(ends[i])), wall_names[i]]
		var mid := a.lerp(b, 0.5) + Vector2(8, -8)
		_overlay.draw_string_outline(font, mid, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, 5, Color(0, 0, 0, 0.85))
		_overlay.draw_string(font, mid, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(1, 1, 1))
	# Chalk lines to the mark it's lined up with.
	var chalk := Color(0.4, 0.75, 1.0, 0.9)
	if _snapped[0]:
		_overlay.draw_dashed_line(_screen(Vector2(p.x, room.position.y)), _screen(Vector2(p.x, room.end.y)), chalk, 2.0, 10.0)
	if _snapped[1]:
		_overlay.draw_dashed_line(_screen(Vector2(room.position.x, p.y)), _screen(Vector2(room.end.x, p.y)), chalk, 2.0, 10.0)
	_draw_x(p, tape if marks.size() < count else Color(0.6, 0.6, 0.6), 7.0)


func _draw_x(at: Vector2, c: Color, r: float) -> void:
	var s := _screen(at)
	_overlay.draw_line(s + Vector2(-r, -r), s + Vector2(r, r), c, 3.0)
	_overlay.draw_line(s + Vector2(-r, r), s + Vector2(r, -r), c, 3.0)


func _screen(at: Vector2) -> Vector2:
	return _cam.unproject_position(to_global(Vector3(at.x, ceiling, at.y)))
