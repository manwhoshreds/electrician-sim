class_name UiIcon
extends Control
## A small line icon, drawn rather than loaded, so the UI needs no image files
## or icon fonts. Shapes are drawn on a 24 x 24 grid and scaled to fit.

var kind := ""
var color := Color.WHITE


static func make(kind_: String, size_px: float, color_: Color) -> UiIcon:
	var i := UiIcon.new()
	i.kind = kind_
	i.color = color_
	i.custom_minimum_size = Vector2(size_px, size_px)
	i.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	i.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return i


func _draw() -> void:
	var s := minf(size.x, size.y) / 24.0
	var o := (size - Vector2(24, 24) * s) / 2.0
	var p := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * s
	var w := 2.0 * s
	match kind:
		"play":
			draw_colored_polygon(PackedVector2Array([p.call(6, 4), p.call(20, 12), p.call(6, 20)]), color)
		"pause":
			draw_rect(Rect2(p.call(5, 3), Vector2(5, 18) * s), color)
			draw_rect(Rect2(p.call(14, 3), Vector2(5, 18) * s), color)
		"save":
			_poly([p.call(4, 3), p.call(17, 3), p.call(21, 7), p.call(21, 21), p.call(4, 21), p.call(4, 3)], w)
			draw_rect(Rect2(p.call(8, 3), Vector2(8, 5) * s), color, false, w)
			draw_rect(Rect2(p.call(8, 13), Vector2(9, 8) * s), color, false, w)
		"folder":
			_poly([p.call(3, 6), p.call(9, 6), p.call(11, 8), p.call(21, 8), p.call(21, 19), p.call(3, 19), p.call(3, 6)], w)
		"calendar":
			draw_rect(Rect2(p.call(3, 5), Vector2(18, 16) * s), color, false, w)
			draw_line(p.call(3, 10), p.call(21, 10), color, w)
			draw_line(p.call(8, 3), p.call(8, 7), color, w)
			draw_line(p.call(16, 3), p.call(16, 7), color, w)
			for x in [8, 12, 16]:
				draw_rect(Rect2(p.call(x - 1, 14), Vector2(2, 2) * s), color)
		"clock":
			draw_arc(p.call(12, 12), 9 * s, 0, TAU, 32, color, w)
			draw_line(p.call(12, 12), p.call(12, 7), color, w)
			draw_line(p.call(12, 12), p.call(16, 14), color, w)
		"gear":
			draw_arc(p.call(12, 12), 6 * s, 0, TAU, 24, color, w)
			draw_arc(p.call(12, 12), 2.2 * s, 0, TAU, 12, color, w)
			for i in 8:
				var a := i * TAU / 8.0
				draw_line(p.call(12, 12) + Vector2(cos(a), sin(a)) * 6 * s, p.call(12, 12) + Vector2(cos(a), sin(a)) * 9.5 * s, color, w * 1.4)
		"gamepad":
			draw_rect(Rect2(p.call(2, 7), Vector2(20, 11) * s), color, false, w)
			draw_line(p.call(7, 10), p.call(7, 15), color, w)
			draw_line(p.call(4.5, 12.5), p.call(9.5, 12.5), color, w)
			draw_circle(p.call(16, 11), 1.3 * s, color)
			draw_circle(p.call(18.5, 14), 1.3 * s, color)
		"help":
			draw_arc(p.call(12, 12), 9 * s, 0, TAU, 32, color, w)
			_glyph("?", p.call(12, 12), 14 * s)
		"info":
			draw_arc(p.call(12, 12), 9 * s, 0, TAU, 32, color, w)
			_glyph("i", p.call(12, 12), 13 * s)
		"home", "house":
			_poly([p.call(3, 11), p.call(12, 3), p.call(21, 11)], w)
			_poly([p.call(5, 10), p.call(5, 21), p.call(19, 21), p.call(19, 10)], w)
			draw_rect(Rect2(p.call(10, 14), Vector2(4, 7) * s), color, false, w)
		"power":
			draw_arc(p.call(12, 13), 8 * s, -PI / 2 + 0.7, -PI / 2 + TAU - 0.7, 28, color, w)
			draw_line(p.call(12, 3), p.call(12, 12), color, w)
		"wrench":
			draw_line(p.call(5, 19), p.call(14, 10), color, w * 1.6)
			draw_arc(p.call(16.5, 7.5), 4.5 * s, 0.9, 0.9 + TAU - 1.6, 20, color, w * 1.5)
		"star":
			var pts := PackedVector2Array()
			for i in 10:
				var r := 10.0 if i % 2 == 0 else 4.2
				var a := -PI / 2.0 + i * TAU / 10.0
				pts.append(p.call(12, 12.8) + Vector2(cos(a), sin(a)) * r * s)
			draw_colored_polygon(pts, color)
		"list":
			for y in [6, 12, 18]:
				draw_circle(p.call(4.5, y), 1.4 * s, color)
				draw_line(p.call(8, y), p.call(21, y), color, w)
		"dollar":
			_glyph("$", p.call(12, 12), 20 * s)
		"money":
			draw_rect(Rect2(p.call(2, 6), Vector2(20, 12) * s), color, false, w)
			draw_arc(p.call(12, 12), 3 * s, 0, TAU, 16, color, w)
		"chart":
			draw_rect(Rect2(p.call(4, 13), Vector2(4, 8) * s), color)
			draw_rect(Rect2(p.call(10, 9), Vector2(4, 12) * s), color)
			draw_rect(Rect2(p.call(16, 4), Vector2(4, 17) * s), color)
		"box":
			_poly([p.call(12, 3), p.call(21, 7.5), p.call(21, 16.5), p.call(12, 21), p.call(3, 16.5), p.call(3, 7.5), p.call(12, 3)], w)
			_poly([p.call(3, 7.5), p.call(12, 12), p.call(21, 7.5)], w)
			draw_line(p.call(12, 12), p.call(12, 21), color, w)
		"mail":
			draw_rect(Rect2(p.call(3, 6), Vector2(18, 13) * s), color, false, w)
			_poly([p.call(3, 7), p.call(12, 14), p.call(21, 7)], w)
		"trend":
			_poly([p.call(3, 18), p.call(9, 12), p.call(13, 15), p.call(21, 7)], w)
			_poly([p.call(15, 7), p.call(21, 7), p.call(21, 13)], w)
		"chat":
			_poly([p.call(3, 5), p.call(21, 5), p.call(21, 16), p.call(10, 16), p.call(5, 20), p.call(6, 16), p.call(3, 16), p.call(3, 5)], w)
			for x in [8, 12, 16]:
				draw_circle(p.call(x, 10.5), 1.2 * s, color)
		"clipboard":
			draw_rect(Rect2(p.call(5, 4), Vector2(14, 18) * s), color, false, w)
			draw_rect(Rect2(p.call(9, 2), Vector2(6, 4) * s), color)
			for y in [11, 15, 19]:
				draw_line(p.call(8, y - 1), p.call(16, y - 1), color, w * 0.8)
		"target":
			for r in [9.0, 5.5, 2.0]:
				draw_arc(p.call(12, 12), r * s, 0, TAU, 28, color, w)
		"pin":
			draw_arc(p.call(12, 9), 5.5 * s, 0, TAU, 24, color, w)
			_poly([p.call(7.5, 12), p.call(12, 21), p.call(16.5, 12)], w)
			draw_circle(p.call(12, 9), 1.8 * s, color)
		"briefcase":
			draw_rect(Rect2(p.call(3, 8), Vector2(18, 12) * s), color)
			draw_rect(Rect2(p.call(9, 4), Vector2(6, 4) * s), color, false, w)
		"bolt":
			var pts := PackedVector2Array()
			for v: Vector2 in [Vector2(14, 2), Vector2(4, 13), Vector2(11, 13), Vector2(8, 22), Vector2(20, 9), Vector2(13, 9), Vector2(17, 2)]:
				pts.append(p.call(v.x, v.y))
			draw_colored_polygon(pts, color)
		"plus":
			draw_arc(p.call(12, 12), 9 * s, 0, TAU, 32, color, w)
			draw_line(p.call(12, 7), p.call(12, 17), color, w)
			draw_line(p.call(7, 12), p.call(17, 12), color, w)
		"person":
			draw_circle(p.call(12, 9), 4.5 * s, color)
			draw_colored_polygon(PackedVector2Array([p.call(4, 21), p.call(6, 15), p.call(12, 14), p.call(18, 15), p.call(20, 21)]), color)
		"book":
			draw_rect(Rect2(p.call(4, 3), Vector2(16, 18) * s), color, false, w)
			for y in [8, 12, 16]:
				draw_line(p.call(8, y), p.call(16, y), color, w * 0.8)


func _poly(points: Array, width: float) -> void:
	draw_polyline(PackedVector2Array(points), color, width, true)


func _glyph(text: String, center: Vector2, px: float) -> void:
	var font := ThemeDB.fallback_font
	var sz := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(px))
	draw_string(font, center + Vector2(-sz.x / 2.0, px * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(px), color)
