class_name TouchControls
extends Control

# ============================================================
#  تحكم اللمس:
#  - النص الأيسر من الشاشة: جويستيك ديناميكي (يظهر وين ما تلمس)
#  - يمين: زر DRIFT + زر BRAKE (بريك/رجوع)
#  - التسارع تلقائي (المعيار بألعاب سيارات الموبايل)
#  - يدمج الكيبورد تلقائياً للتجربة على الحاسبة
# ============================================================

const JOY_RADIUS := 110.0
const KNOB_RADIUS := 42.0
const DRIFT_RADIUS := 92.0
const BRAKE_RADIUS := 70.0

var _steer_touch := -1
var _steer_origin := Vector2.ZERO
var _steer_pos := Vector2.ZERO
var _touch_steer := 0.0
var _drift_touch := -1
var _brake_touch := -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


# ---------- الواجهة اللي تقرأها السيارة ----------

func get_steer() -> float:
	var kb := Input.get_axis("ui_left", "ui_right")
	if Input.is_key_pressed(KEY_A):
		kb = -1.0
	elif Input.is_key_pressed(KEY_D):
		kb = 1.0
	if absf(kb) > 0.01:
		return kb
	return _touch_steer


func is_drifting() -> bool:
	return _drift_touch != -1 or Input.is_key_pressed(KEY_SPACE)


func is_braking() -> bool:
	return _brake_touch != -1 or Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S)


# ---------- معالجة اللمس (متعدد الأصابع) ----------

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_on_touch_down(event.index, event.position)
		else:
			_on_touch_up(event.index)
	elif event is InputEventScreenDrag:
		_on_touch_move(event.index, event.position)


func _on_touch_down(index: int, pos: Vector2) -> void:
	if pos.distance_to(_drift_center()) <= DRIFT_RADIUS:
		_drift_touch = index
	elif pos.distance_to(_brake_center()) <= BRAKE_RADIUS:
		_brake_touch = index
	elif pos.x < size.x * 0.55:
		_steer_touch = index
		_steer_origin = pos
		_steer_pos = pos
		_touch_steer = 0.0
	queue_redraw()


func _on_touch_move(index: int, pos: Vector2) -> void:
	if index != _steer_touch:
		return
	var offset := pos - _steer_origin
	if offset.length() > JOY_RADIUS:
		offset = offset.normalized() * JOY_RADIUS
	_steer_pos = _steer_origin + offset
	_touch_steer = clampf(offset.x / JOY_RADIUS, -1.0, 1.0)
	queue_redraw()


func _on_touch_up(index: int) -> void:
	if index == _steer_touch:
		_steer_touch = -1
		_touch_steer = 0.0
	if index == _drift_touch:
		_drift_touch = -1
	if index == _brake_touch:
		_brake_touch = -1
	queue_redraw()


# ---------- الرسم ----------

func _draw() -> void:
	if _steer_touch != -1:
		draw_circle(_steer_origin, JOY_RADIUS, Color(1, 1, 1, 0.08))
		draw_arc(_steer_origin, JOY_RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.35), 3.0)
		draw_circle(_steer_pos, KNOB_RADIUS, Color(1, 1, 1, 0.45))
	else:
		var hint := Vector2(190.0, size.y - 160.0)
		draw_arc(hint, 70.0, 0.0, TAU, 40, Color(1, 1, 1, 0.12), 3.0)
		_draw_label(hint, "STEER", 18, Color(1, 1, 1, 0.25))

	_draw_button(_drift_center(), DRIFT_RADIUS, "DRIFT", _drift_touch != -1, Color(1.0, 0.55, 0.1))
	_draw_button(_brake_center(), BRAKE_RADIUS, "BRAKE", _brake_touch != -1, Color(0.9, 0.2, 0.2))


func _draw_button(center: Vector2, radius: float, label: String, pressed: bool, color: Color) -> void:
	var fill := color
	fill.a = 0.55 if pressed else 0.22
	draw_circle(center, radius, fill)
	draw_arc(center, radius, 0.0, TAU, 48, Color(color.r, color.g, color.b, 0.8), 3.0)
	_draw_label(center, label, 24, Color(1, 1, 1, 0.9))


func _draw_label(center: Vector2, text: String, font_size: int, color: Color) -> void:
	var w := 220.0
	var pos := center + Vector2(-w / 2.0, font_size * 0.35)
	draw_string(ThemeDB.fallback_font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, w, font_size, color)


func _drift_center() -> Vector2:
	return Vector2(size.x - 140.0, size.y - 150.0)


func _brake_center() -> Vector2:
	return Vector2(size.x - 330.0, size.y - 120.0)
