class_name TouchControls
extends Control

# ============================================================
#  تحكم اللمس - المرحلة 4:
#  يسار: جويستيك ديناميكي
#  يمين: FIRE (رشاش) + SPEC (السلاح الخاص + العدد)
#         + بدّل + DRIFT + BRAKE — كلها تشتغل سوية
# ============================================================

const JOY_RADIUS := 110.0
const KNOB_RADIUS := 42.0
const FIRE_RADIUS := 90.0
const SPEC_RADIUS := 58.0
const CYCLE_RADIUS := 34.0
const MINE_RADIUS := 58.0
const BOOST_RADIUS := 72.0
const DRIFT_RADIUS := 62.0
const BRAKE_RADIUS := 52.0

var special_text := "-"
var mine_text := "لغم 0"
var mine_charge := 0.0
var boost_ratio := 1.0

var _steer_touch := -1
var _steer_origin := Vector2.ZERO
var _steer_pos := Vector2.ZERO
var _touch_steer := 0.0
var _touch_throttle := 0.0
var _fire_touch := -1
var _spec_touch := -1
var _cycle_touch := -1
var _mine_touch := -1
var _boost_touch := -1
var _drift_touch := -1
var _brake_touch := -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# نتأكد إن الحجم يملأ الشاشة ونعيد الرسم أول ما يجهز الحجم
	resized.connect(queue_redraw)
	get_viewport().size_changed.connect(_on_viewport_resize)
	call_deferred("_force_size")


func _force_size() -> void:
	var vp := get_viewport().get_visible_rect().size
	size = vp
	position = Vector2.ZERO
	queue_redraw()


func _on_viewport_resize() -> void:
	_force_size()


func _process(_delta: float) -> void:
	# ضمان بقاء الأزرار مرسومة ومطابقة لحجم الشاشة
	var vp := get_viewport().get_visible_rect().size
	if size != vp:
		size = vp
		queue_redraw()


func set_special_text(t: String) -> void:
	special_text = t
	queue_redraw()


func set_mine_text(t: String) -> void:
	mine_text = t
	queue_redraw()


func set_mine_charge(r: float) -> void:
	mine_charge = r
	queue_redraw()


func set_boost_ratio(r: float) -> void:
	boost_ratio = r
	queue_redraw()


func is_boost_pressed() -> bool:
	return _boost_touch != -1 or Input.is_key_pressed(KEY_SHIFT)


func is_mine_pressed() -> bool:
	return _mine_touch != -1 or Input.is_key_pressed(KEY_R)


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


func get_throttle() -> float:
	# لوحة المفاتيح: أسهم فوق/تحت أو W
	var kb := 0.0
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		kb = 1.0
	elif Input.is_key_pressed(KEY_DOWN):
		kb = -1.0
	if absf(kb) > 0.01:
		return kb
	return _touch_throttle


func is_drifting() -> bool:
	return _drift_touch != -1 or Input.is_key_pressed(KEY_SPACE)


func is_braking() -> bool:
	return _brake_touch != -1 or Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S)


func is_firing() -> bool:
	return _fire_touch != -1 or Input.is_key_pressed(KEY_F) or Input.is_key_pressed(KEY_ENTER)


func is_special_pressed() -> bool:
	return _spec_touch != -1 or Input.is_key_pressed(KEY_Q)


func is_cycle_pressed() -> bool:
	return _cycle_touch != -1 or Input.is_key_pressed(KEY_E)


# ---------- معالجة اللمس ----------

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_on_touch_down(event.index, event.position)
		else:
			_on_touch_up(event.index)
	elif event is InputEventScreenDrag:
		_on_touch_move(event.index, event.position)


func _on_touch_down(index: int, pos: Vector2) -> void:
	if pos.distance_to(_fire_center()) <= FIRE_RADIUS:
		_fire_touch = index
	elif pos.distance_to(_spec_center()) <= SPEC_RADIUS:
		_spec_touch = index
	elif pos.distance_to(_cycle_center()) <= CYCLE_RADIUS:
		_cycle_touch = index
	elif pos.distance_to(_mine_center()) <= MINE_RADIUS:
		_mine_touch = index
	elif pos.distance_to(_boost_center()) <= BOOST_RADIUS:
		_boost_touch = index
	elif pos.distance_to(_drift_center()) <= DRIFT_RADIUS:
		_drift_touch = index
	elif pos.distance_to(_brake_center()) <= BRAKE_RADIUS:
		_brake_touch = index
	elif pos.x < size.x * 0.5:
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
	# فوق = تسارع، تحت = بريك/رجوع (Y بالشاشة يزيد للأسفل)
	_touch_throttle = clampf(-offset.y / JOY_RADIUS, -1.0, 1.0)
	queue_redraw()


func _on_touch_up(index: int) -> void:
	if index == _steer_touch:
		_steer_touch = -1
		_touch_steer = 0.0
		_touch_throttle = 0.0
	if index == _fire_touch:
		_fire_touch = -1
	if index == _spec_touch:
		_spec_touch = -1
	if index == _cycle_touch:
		_cycle_touch = -1
	if index == _mine_touch:
		_mine_touch = -1
	if index == _boost_touch:
		_boost_touch = -1
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
		# سهم فوق/تحت يوضح إن الجويستيك يسوق
		draw_line(hint + Vector2(0, -34), hint + Vector2(0, -50), Color(1, 1, 1, 0.3), 3.0)
		draw_line(hint + Vector2(-7, -44), hint + Vector2(0, -52), Color(1, 1, 1, 0.3), 3.0)
		draw_line(hint + Vector2(7, -44), hint + Vector2(0, -52), Color(1, 1, 1, 0.3), 3.0)
		_draw_label(hint, "قود", 20, Color(1, 1, 1, 0.3))

	_draw_button(_fire_center(), FIRE_RADIUS, "FIRE", _fire_touch != -1, Color(0.95, 0.25, 0.2))
	_draw_button(_spec_center(), SPEC_RADIUS, special_text, _spec_touch != -1, Color(0.62, 0.3, 0.85))
	_draw_button(_cycle_center(), CYCLE_RADIUS, "بدّل", _cycle_touch != -1, Color(0.3, 0.32, 0.38))
	_draw_mine_button()
	_draw_boost_button()
	_draw_button(_drift_center(), DRIFT_RADIUS, "DRIFT", _drift_touch != -1, Color(1.0, 0.55, 0.1))
	_draw_button(_brake_center(), BRAKE_RADIUS, "BRAKE", _brake_touch != -1, Color(0.35, 0.55, 0.9))


func _draw_mine_button() -> void:
	var c := _mine_center()
	_draw_button(c, MINE_RADIUS, mine_text, _mine_touch != -1, Color(0.75, 0.68, 0.15))
	# حلقة الشحن وقت الضغط المطول
	if mine_charge > 0.0:
		draw_arc(c, MINE_RADIUS + 6.0, -PI / 2.0, -PI / 2.0 + TAU * mine_charge, 48, Color(1.0, 0.35, 0.1), 5.0)


func _draw_boost_button() -> void:
	var c := _boost_center()
	var col := Color(0.2, 0.7, 1.0)
	_draw_button(c, BOOST_RADIUS, "NITRO", _boost_touch != -1, col)
	# قوس يمثل مخزون البوست
	draw_arc(c, BOOST_RADIUS + 6.0, -PI / 2.0, -PI / 2.0 + TAU * clampf(boost_ratio, 0.0, 1.0), 48, Color(0.3, 0.85, 1.0, 0.9), 5.0)


func _draw_button(center: Vector2, radius: float, label: String, pressed: bool, color: Color) -> void:
	var fill := color
	fill.a = 0.55 if pressed else 0.22
	draw_circle(center, radius, fill)
	draw_arc(center, radius, 0.0, TAU, 48, Color(color.r, color.g, color.b, 0.8), 3.0)
	var fs := 24 if radius > 50.0 else 16
	_draw_label(center, label, fs, Color(1, 1, 1, 0.9))


func _draw_label(center: Vector2, text: String, font_size: int, color: Color) -> void:
	var w := 220.0
	var pos := center + Vector2(-w / 2.0, font_size * 0.35)
	draw_string(ThemeDB.fallback_font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, w, font_size, color)


# تخطيط الأزرار (يمين الشاشة):
#   FIRE أسفل يمين، وفوقه SPEC ثم زر بدّل
#   NITRO يسار FIRE، وفوقه MINE
#   DRIFT وBRAKE أقصى اليسار من المجموعة
func _fire_center() -> Vector2:
	return Vector2(size.x - 120.0, size.y - 130.0)


func _spec_center() -> Vector2:
	return Vector2(size.x - 125.0, size.y - 300.0)


func _cycle_center() -> Vector2:
	return Vector2(size.x - 200.0, size.y - 388.0)


func _boost_center() -> Vector2:
	return Vector2(size.x - 285.0, size.y - 150.0)


func _mine_center() -> Vector2:
	return Vector2(size.x - 285.0, size.y - 305.0)


func _drift_center() -> Vector2:
	return Vector2(size.x - 430.0, size.y - 130.0)


func _brake_center() -> Vector2:
	return Vector2(size.x - 445.0, size.y - 285.0)
