extends Control

# ============================================================
#  القائمة الرئيسية + اختيار الشخصيات (ستايل ببجي)
#  START GAME -> بطاقة الشخصية + سيارتها تدور 3D -> المعركة
# ============================================================

var _title_page: Control
var _t_title: Label
var _t_sub: Label
var _t_start: Button
var _start_pulse := false
var _select_page: Control
var _map_page: Control
var _map_cards: Array = []
var _map_index := 0
var _portrait: TextureRect
var _portrait_fallback: Label
var _portrait_panel: Panel
var _name_label: Label
var _desc_label: Label
var _counter_label: Label
var _battle_btn: Button
var _ai_btn: Button
var _mp_btn: Button
var _stat_fills: Array = []
var _preview_car: ArcadeCar
var _preview_model: Node3D = null
var _index := 0


func _ready() -> void:
	_build_title_page()
	_build_select_page()
	_build_map_page()
	_show_title()


func _process(delta: float) -> void:
	if _preview_car != null and _select_page.visible:
		_preview_car.rotation.y += delta * 0.9


# ============================================================
#  صفحة البداية
# ============================================================

func _build_title_page() -> void:
	_title_page = Control.new()
	_title_page.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_title_page)

	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.07, 0.1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title_page.add_child(bg)

	var strip := ColorRect.new()
	strip.color = Color(0.85, 0.16, 0.1, 0.9)
	strip.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	strip.offset_top = 118
	strip.offset_bottom = 126
	_title_page.add_child(strip)

	var title := Label.new()
	title.text = "METAL ARENA"
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 130
	title.offset_bottom = 250
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 88)
	title.add_theme_color_override("font_color", Color(1, 1, 1))
	title.add_theme_color_override("font_shadow_color", Color(0.85, 0.16, 0.1, 0.7))
	title.add_theme_constant_override("shadow_offset_x", 4)
	title.add_theme_constant_override("shadow_offset_y", 4)
	_title_page.add_child(title)
	_t_title = title

	var sub := Label.new()
	sub.text = "حرب سيارات — ساحة الموت"
	sub.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	sub.offset_top = 252
	sub.offset_bottom = 300
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 28)
	sub.add_theme_color_override("font_color", Color(0.7, 0.72, 0.78))
	_title_page.add_child(sub)
	_t_sub = sub

	var start := _make_button("START GAME", 42, Color(0.85, 0.16, 0.1))
	start.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	start.offset_left = -210
	start.offset_right = 210
	start.offset_top = 70
	start.offset_bottom = 165
	start.pressed.connect(_show_select)
	_title_page.add_child(start)
	_t_start = start

	var ver := Label.new()
	ver.text = "v0.3 — المرحلة 2"
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	ver.offset_left = 20
	ver.offset_top = -46
	ver.offset_right = 320
	ver.offset_bottom = -14
	ver.add_theme_font_size_override("font_size", 20)
	ver.add_theme_color_override("font_color", Color(0.5, 0.52, 0.58))
	_title_page.add_child(ver)


# ============================================================
#  صفحة اختيار الشخصية
# ============================================================

func _build_select_page() -> void:
	_select_page = Control.new()
	_select_page.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_select_page)

	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.11)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_select_page.add_child(bg)

	var header := Label.new()
	header.text = "اختار مقاتلك"
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.offset_top = 18
	header.offset_bottom = 70
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 38)
	header.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	_select_page.add_child(header)

	var back := _make_button("◀ رجوع", 24, Color(0.2, 0.22, 0.28))
	back.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	back.offset_left = 20
	back.offset_top = 16
	back.offset_right = 175
	back.offset_bottom = 72
	back.pressed.connect(_show_title)
	_select_page.add_child(back)

	# اختيار الوضع (فوق يمين)
	var mode_label := Label.new()
	mode_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	mode_label.offset_left = -430
	mode_label.offset_right = -20
	mode_label.offset_top = 16
	mode_label.offset_bottom = 44
	mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	mode_label.add_theme_font_size_override("font_size", 20)
	mode_label.add_theme_color_override("font_color", Color(0.6, 0.62, 0.7))
	mode_label.text = "الوضع:"
	_select_page.add_child(mode_label)

	_ai_btn = _make_button("ضد الكمبيوتر", 20, Color(0.85, 0.16, 0.1))
	_ai_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_ai_btn.offset_left = -430
	_ai_btn.offset_right = -235
	_ai_btn.offset_top = 46
	_ai_btn.offset_bottom = 92
	_ai_btn.pressed.connect(func() -> void: _set_mode(Global.Mode.AI))
	_select_page.add_child(_ai_btn)

	_mp_btn = _make_button("لاعبين (قريباً)", 20, Color(0.25, 0.27, 0.32))
	_mp_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_mp_btn.offset_left = -225
	_mp_btn.offset_right = -20
	_mp_btn.offset_top = 46
	_mp_btn.offset_bottom = 92
	_mp_btn.pressed.connect(func() -> void: _set_mode(Global.Mode.LOCAL_MP))
	_select_page.add_child(_mp_btn)

	# بطاقة الصورة
	_portrait_panel = Panel.new()
	_portrait_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_portrait_panel.offset_left = 150
	_portrait_panel.offset_top = 92
	_portrait_panel.offset_right = 505
	_portrait_panel.offset_bottom = 447
	_select_page.add_child(_portrait_panel)

	_portrait = TextureRect.new()
	_portrait.set_anchors_preset(Control.PRESET_FULL_RECT)
	_portrait.offset_left = 5
	_portrait.offset_top = 5
	_portrait.offset_right = -5
	_portrait.offset_bottom = -5
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_portrait_panel.add_child(_portrait)

	_portrait_fallback = Label.new()
	_portrait_fallback.set_anchors_preset(Control.PRESET_FULL_RECT)
	_portrait_fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_portrait_fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_portrait_fallback.add_theme_font_size_override("font_size", 150)
	_portrait_fallback.add_theme_color_override("font_color", Color(1, 1, 1, 0.25))
	_portrait_panel.add_child(_portrait_fallback)

	_name_label = Label.new()
	_name_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_name_label.offset_left = 150
	_name_label.offset_top = 452
	_name_label.offset_right = 505
	_name_label.offset_bottom = 505
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 40)
	_select_page.add_child(_name_label)

	_desc_label = Label.new()
	_desc_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_desc_label.offset_left = 120
	_desc_label.offset_top = 505
	_desc_label.offset_right = 535
	_desc_label.offset_bottom = 540
	_desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_desc_label.add_theme_font_size_override("font_size", 21)
	_desc_label.add_theme_color_override("font_color", Color(0.68, 0.7, 0.76))
	_select_page.add_child(_desc_label)

	# أشرطة المواصفات
	var stat_names := ["السرعة", "الدروع", "الضرر"]
	for i in 3:
		var y := 556 + i * 42
		var nl := Label.new()
		nl.text = stat_names[i]
		nl.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		nl.offset_left = 150
		nl.offset_top = y
		nl.offset_right = 260
		nl.offset_bottom = y + 30
		nl.add_theme_font_size_override("font_size", 22)
		_select_page.add_child(nl)

		var bar_bg := ColorRect.new()
		bar_bg.color = Color(0, 0, 0, 0.45)
		bar_bg.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		bar_bg.offset_left = 270
		bar_bg.offset_top = y + 5
		bar_bg.offset_right = 505
		bar_bg.offset_bottom = y + 25
		_select_page.add_child(bar_bg)

		var fill := ColorRect.new()
		fill.color = Color(0.9, 0.65, 0.15)
		fill.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		fill.offset_left = 272
		fill.offset_top = y + 7
		fill.offset_right = 272 + 231
		fill.offset_bottom = y + 23
		_select_page.add_child(fill)
		_stat_fills.append(fill)

	# معاينة السيارة 3D
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	svc.offset_left = -650
	svc.offset_top = 100
	svc.offset_right = -60
	svc.offset_bottom = 545
	_select_page.add_child(svc)

	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	svc.add_child(vp)

	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.72, 0.8)
	env.ambient_light_energy = 1.1
	var wenv := WorldEnvironment.new()
	wenv.environment = env
	vp.add_child(wenv)

	var lt := DirectionalLight3D.new()
	lt.rotation_degrees = Vector3(-45.0, -35.0, 0.0)
	lt.light_energy = 1.1
	vp.add_child(lt)

	var cam := Camera3D.new()
	vp.add_child(cam)
	cam.position = Vector3(2.6, 1.5, 3.1)
	cam.look_at(Vector3(0.0, 0.1, 0.0), Vector3.UP)

	_preview_car = ArcadeCar.new()
	_preview_car.input_enabled = false
	_preview_car.freeze = true
	vp.add_child(_preview_car)
	_preview_car.position = Vector3(0.0, -0.2, 0.0)

	var car_hint := Label.new()
	car_hint.text = "سيارة المقاتل"
	car_hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	car_hint.offset_left = -650
	car_hint.offset_top = 548
	car_hint.offset_right = -60
	car_hint.offset_bottom = 582
	car_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	car_hint.add_theme_font_size_override("font_size", 22)
	car_hint.add_theme_color_override("font_color", Color(0.6, 0.62, 0.7))
	_select_page.add_child(car_hint)

	# أسهم التبديل
	var left := _make_button("◀", 46, Color(0.2, 0.22, 0.28))
	left.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	left.offset_left = 18
	left.offset_top = -55
	left.offset_right = 118
	left.offset_bottom = 55
	left.pressed.connect(_prev_character)
	_select_page.add_child(left)

	var right := _make_button("▶", 46, Color(0.2, 0.22, 0.28))
	right.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	right.offset_left = -118
	right.offset_top = -55
	right.offset_right = -18
	right.offset_bottom = 55
	right.pressed.connect(_next_character)
	_select_page.add_child(right)

	_counter_label = Label.new()
	_counter_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_counter_label.offset_left = 150
	_counter_label.offset_top = -60
	_counter_label.offset_right = 505
	_counter_label.offset_bottom = -22
	_counter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_counter_label.add_theme_font_size_override("font_size", 24)
	_counter_label.add_theme_color_override("font_color", Color(0.6, 0.62, 0.7))
	_select_page.add_child(_counter_label)

	_battle_btn = _make_button("⚔ ابدأ المعركة", 36, Color(0.85, 0.16, 0.1))
	_battle_btn.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_battle_btn.offset_left = -470
	_battle_btn.offset_top = -125
	_battle_btn.offset_right = -70
	_battle_btn.offset_bottom = -35
	_battle_btn.pressed.connect(_start_battle)
	_select_page.add_child(_battle_btn)


# ============================================================
#  المنطق
# ============================================================

func _show_title() -> void:
	if _map_page != null:
		_map_page.visible = false
	_title_page.visible = true
	_animate_title_entrance()


func _animate_title_entrance() -> void:
	await get_tree().process_frame
	if _t_title == null:
		return
	# العنوان: يدخل بتكبير مرتد + تلاشي
	_t_title.pivot_offset = _t_title.size * 0.5
	_t_title.scale = Vector2(1.5, 1.5)
	_t_title.modulate.a = 0.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_t_title, "scale", Vector2.ONE, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_t_title, "modulate:a", 1.0, 0.3)
	# العنوان الفرعي: تلاشي متأخر
	_t_sub.modulate.a = 0.0
	var tw2 := create_tween()
	tw2.tween_interval(0.3)
	tw2.tween_property(_t_sub, "modulate:a", 1.0, 0.35)
	# زر البداية: يطلع من تحت بارتداد
	_t_start.pivot_offset = _t_start.size * 0.5
	_t_start.scale = Vector2(0.6, 0.6)
	_t_start.modulate.a = 0.0
	var tw3 := create_tween()
	tw3.tween_interval(0.5)
	tw3.set_parallel(false)
	var p := tw3.parallel()
	p.tween_property(_t_start, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	p.tween_property(_t_start, "modulate:a", 1.0, 0.25)
	# نبض مستمر خفيف على الزر (مرة وحدة)
	if not _start_pulse:
		_start_pulse = true
		var pulse := create_tween()
		pulse.set_loops()
		pulse.tween_interval(1.0)
		pulse.tween_property(_t_start, "scale", Vector2(1.05, 1.05), 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		pulse.tween_property(_t_start, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_select_page.visible = false


func _show_select() -> void:
	if _map_page != null:
		_map_page.visible = false
	_title_page.visible = false
	_select_page.visible = true
	_refresh_mode()
	_refresh()


func _set_mode(m: int) -> void:
	# اللاعبين المحلي لسه ما تفعّل - نبقى على AI ونبيّن رسالة
	if m == Global.Mode.LOCAL_MP:
		_mp_btn.text = "قريباً..."
		return
	Global.game_mode = m
	_refresh_mode()


func _refresh_mode() -> void:
	# نبرز الزر الفعّال
	var active := Color(0.85, 0.16, 0.1)
	var inactive := Color(0.25, 0.27, 0.32)
	_style_button(_ai_btn, active if Global.game_mode == Global.Mode.AI else inactive)
	_style_button(_mp_btn, Color(0.2, 0.21, 0.24))
	_mp_btn.text = "لاعبين (قريباً)"


func _style_button(b: Button, color: Color) -> void:
	var normal: StyleBoxFlat = b.get_theme_stylebox("normal")
	if normal != null:
		normal.bg_color = color


func _prev_character() -> void:
	_index = (_index - 1 + Content.count()) % Content.count()
	_refresh()


func _next_character() -> void:
	_index = (_index + 1) % Content.count()
	_refresh()


func _start_battle() -> void:
	Global.selected_character = _index
	_show_maps()


# ============================================================
#  صفحة اختيار الميدان
# ============================================================


func _build_map_page() -> void:
	_map_page = Control.new()
	_map_page.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_page.visible = false
	add_child(_map_page)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.08, 0.09, 0.12)
	_map_page.add_child(bg)

	var header := Label.new()
	header.text = "اختار الميدان"
	header.set_anchors_preset(Control.PRESET_TOP_WIDE)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.position.y = 42
	header.add_theme_font_size_override("font_size", 40)
	header.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0))
	_map_page.add_child(header)

	var back := Button.new()
	back.text = "◀ رجوع"
	back.position = Vector2(30, 30)
	back.custom_minimum_size = Vector2(140, 54)
	back.add_theme_font_size_override("font_size", 22)
	back.pressed.connect(_show_select)
	_map_page.add_child(back)

	# ⚙️ لوحة إعدادات المباراة (يسار)
	_build_match_settings()

	# بطاقات الخرائط
	_map_cards.clear()
	for i in Maps.count():
		var m: Dictionary = Maps.get_map(i)
		var card := Panel.new()
		var cw := 400.0
		var gap := 40.0
		var n: int = Maps.count()
		var total := n * cw + (n - 1) * gap
		var x0 := (1280.0 - total) * 0.5
		card.custom_minimum_size = Vector2(cw, 370)
		card.position = Vector2(x0 + i * (cw + gap), 108)
		card.size = Vector2(cw, 370)
		_map_page.add_child(card)

		var preview := ColorRect.new()
		preview.position = Vector2(18, 18)
		preview.size = Vector2(364, 150)
		preview.color = (m["color"] as Color).darkened(0.55)
		card.add_child(preview)

		var icon := Label.new()
		icon.text = m["icon"]
		icon.position = Vector2(18, 18)
		icon.size = Vector2(364, 150)
		icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		icon.add_theme_font_size_override("font_size", 70)
		card.add_child(icon)

		var nm := Label.new()
		nm.text = m["name"]
		nm.position = Vector2(18, 180)
		nm.size = Vector2(364, 40)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.add_theme_font_size_override("font_size", 30)
		nm.add_theme_color_override("font_color", Color(1, 1, 1))
		card.add_child(nm)

		var ds := Label.new()
		ds.text = m["desc"]
		ds.position = Vector2(22, 222)
		ds.size = Vector2(356, 60)
		ds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ds.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ds.add_theme_font_size_override("font_size", 17)
		ds.add_theme_color_override("font_color", Color(0.65, 0.67, 0.72))
		card.add_child(ds)

		var tg := Label.new()
		tg.text = m["tags"]
		tg.position = Vector2(18, 288)
		tg.size = Vector2(364, 26)
		tg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tg.add_theme_font_size_override("font_size", 15)
		tg.add_theme_color_override("font_color", m["color"])
		card.add_child(tg)

		var btn := Button.new()
		btn.flat = true
		btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		btn.pressed.connect(_on_map_picked.bind(i))
		card.add_child(btn)
		_map_cards.append(card)

	_refresh_map_cards()


# ⚙️ إعدادات المباراة: عدد القتل + الوقت + المطر
const SCORE_OPTIONS = [3, 5, 8, 12, 20]
const TIME_OPTIONS = [
	{"label": "🎲 عشوائي", "value": -1.0},
	{"label": "🌅 صباح", "value": 0.3},
	{"label": "☀️ ظهر", "value": 0.5},
	{"label": "🌇 غروب", "value": 0.75},
	{"label": "🌙 ليل", "value": 0.95},
]
const RAIN_OPTIONS = [
	{"label": "🎲 عشوائي", "value": -1},
	{"label": "☀️ صافي", "value": 0},
	{"label": "🌧️ ممطر", "value": 1},
]
const ENEMY_OPTIONS = [1, 2, 3, 4, 5, 6, 7]
const DIFF_OPTIONS = [
	{"label": "😴 سهل", "value": 1},
	{"label": "🙂 عادي", "value": 2},
	{"label": "😠 صعب", "value": 3},
	{"label": "💀 قاتل", "value": 4},
]

var _score_idx := 2      # 8 قتلات
var _time_idx := 0       # عشوائي
var _rain_idx := 0       # عشوائي
var _enemy_idx := 3      # 4 أعداء
var _diff_idx := 1       # عادي
var _score_btn: Button
var _time_btn: Button
var _rain_btn: Button
var _enemy_btn: Button
var _diff_btn: Button


func _build_match_settings() -> void:
	var box := Panel.new()
	box.position = Vector2(30, 500)
	box.size = Vector2(1220, 100)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.11, 0.14)
	sb.border_color = Color(0.25, 0.27, 0.32)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	box.add_theme_stylebox_override("panel", sb)
	_map_page.add_child(box)

	# خمس إعدادات بصف واحد (تسع بأي شاشة)
	_score_btn = _make_setting(box, 18, "🏆 القتلات", _on_score_pressed)
	_enemy_btn = _make_setting(box, 262, "👾 الأعداء", _on_enemy_pressed)
	_diff_btn = _make_setting(box, 506, "⚔️ الصعوبة", _on_diff_pressed)
	_time_btn = _make_setting(box, 750, "🕐 الوقت", _on_time_pressed)
	_rain_btn = _make_setting(box, 994, "🌦️ الطقس", _on_rain_pressed)
	_refresh_settings()


func _make_setting(box: Panel, x: float, label: String, cb: Callable) -> Button:
	var lb := Label.new()
	lb.text = label
	lb.position = Vector2(x, 8)
	lb.size = Vector2(226, 22)
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb.add_theme_font_size_override("font_size", 16)
	lb.add_theme_color_override("font_color", Color(0.62, 0.65, 0.72))
	box.add_child(lb)

	var btn := Button.new()
	btn.position = Vector2(x, 36)
	btn.size = Vector2(226, 48)
	btn.custom_minimum_size = Vector2(226, 48)
	btn.add_theme_font_size_override("font_size", 21)
	btn.pressed.connect(cb)
	box.add_child(btn)
	return btn


func _refresh_settings() -> void:
	_score_btn.text = "%d  ▸" % SCORE_OPTIONS[_score_idx]
	_time_btn.text = "%s  ▸" % TIME_OPTIONS[_time_idx]["label"]
	_rain_btn.text = "%s  ▸" % RAIN_OPTIONS[_rain_idx]["label"]
	_enemy_btn.text = "%d  ▸" % ENEMY_OPTIONS[_enemy_idx]
	_diff_btn.text = "%s  ▸" % DIFF_OPTIONS[_diff_idx]["label"]


func _on_enemy_pressed() -> void:
	_enemy_idx = (_enemy_idx + 1) % ENEMY_OPTIONS.size()
	_refresh_settings()
	_pop_btn(_enemy_btn)


func _on_diff_pressed() -> void:
	_diff_idx = (_diff_idx + 1) % DIFF_OPTIONS.size()
	_refresh_settings()
	_pop_btn(_diff_btn)


func _on_score_pressed() -> void:
	_score_idx = (_score_idx + 1) % SCORE_OPTIONS.size()
	_refresh_settings()
	_pop_btn(_score_btn)


func _on_time_pressed() -> void:
	_time_idx = (_time_idx + 1) % TIME_OPTIONS.size()
	_refresh_settings()
	_pop_btn(_time_btn)


func _on_rain_pressed() -> void:
	_rain_idx = (_rain_idx + 1) % RAIN_OPTIONS.size()
	_refresh_settings()
	_pop_btn(_rain_btn)


func _pop_btn(b: Button) -> void:
	b.pivot_offset = b.size * 0.5
	var tw := create_tween()
	tw.tween_property(b, "scale", Vector2(1.08, 1.08), 0.08).set_trans(Tween.TRANS_SINE)
	tw.tween_property(b, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_SINE)


func _refresh_map_cards() -> void:
	for i in _map_cards.size():
		var card: Panel = _map_cards[i]
		var sel := i == _map_index
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.13, 0.14, 0.18) if sel else Color(0.1, 0.11, 0.14)
		sb.border_color = Maps.get_map(i)["color"] if sel else Color(0.2, 0.21, 0.25)
		sb.set_border_width_all(4 if sel else 2)
		sb.set_corner_radius_all(14)
		card.add_theme_stylebox_override("panel", sb)


func _on_map_picked(i: int) -> void:
	_map_index = i
	_refresh_map_cards()
	var card: Panel = _map_cards[i]
	card.pivot_offset = card.size * 0.5
	var tw := create_tween()
	tw.tween_property(card, "scale", Vector2(1.05, 1.05), 0.12).set_trans(Tween.TRANS_SINE)
	tw.tween_property(card, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(_launch_map)


func _launch_map() -> void:
	Global.selected_map = _map_index
	# ⚙️ نمرر إعدادات المباراة
	Global.score_to_win = SCORE_OPTIONS[_score_idx]
	Global.time_of_day = float(TIME_OPTIONS[_time_idx]["value"])
	Global.rain = int(RAIN_OPTIONS[_rain_idx]["value"])
	Global.enemy_count = ENEMY_OPTIONS[_enemy_idx]
	Global.difficulty = int(DIFF_OPTIONS[_diff_idx]["value"])
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _show_maps() -> void:
	_title_page.visible = false
	_select_page.visible = false
	_map_page.visible = true
	# أنيميشن دخول البطاقات
	for i in _map_cards.size():
		var card: Panel = _map_cards[i]
		card.pivot_offset = card.size * 0.5
		card.scale = Vector2(0.85, 0.85)
		card.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_interval(i * 0.1)
		var p := tw.parallel()
		p.tween_property(card, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		p.tween_property(card, "modulate:a", 1.0, 0.3)


func _refresh() -> void:
	var ch: Dictionary = Content.get_character(_index)
	var stats: Dictionary = ch["stats"]

	_name_label.text = ch["name"]
	_desc_label.text = ch["subtitle"]
	_counter_label.text = "%d / %d" % [_index + 1, Content.count()]

	# الصورة (portrait من ملف الشخصية)
	if ch["portrait"] != null:
		_portrait.texture = ch["portrait"]
		_portrait.visible = true
		_portrait_fallback.visible = false
	else:
		_portrait.visible = false
		_portrait_fallback.visible = true
		_portrait_fallback.text = ch["name"].substr(0, 2)

	var col := Color(stats["color"][0], stats["color"][1], stats["color"][2])

	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0.11, 0.12, 0.16)
	frame.border_color = col
	frame.set_border_width_all(4)
	frame.set_corner_radius_all(12)
	_portrait_panel.add_theme_stylebox_override("panel", frame)
	_name_label.add_theme_color_override("font_color", Color(1, 1, 1))

	# أشرطة الإحصائيات حسب الفئة
	var speed_r: float = clampf((stats["max_speed"] - 20.0) / 22.0, 0.05, 1.0)
	var hp_r: float = clampf((stats["max_health"] - 50.0) / 130.0, 0.05, 1.0)
	var dmg_r: float = clampf((stats["gun_damage"] - 3.0) / 5.0, 0.05, 1.0)
	var ratios := [speed_r, hp_r, dmg_r]
	for i in 3:
		var fill: ColorRect = _stat_fills[i]
		fill.color = col
		var target: float = fill.offset_left + 231.0 * ratios[i]
		var tw := create_tween()
		tw.tween_property(fill, "offset_right", target, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	# أنيميشن دخول: الصورة تنبض والنصوص تتلاشى للداخل
	if _portrait_panel.size != Vector2.ZERO:
		_portrait_panel.pivot_offset = _portrait_panel.size * 0.5
		_portrait_panel.scale = Vector2(0.92, 0.92)
		_portrait_panel.modulate.a = 0.55
		var ptw := create_tween()
		ptw.set_parallel(true)
		ptw.tween_property(_portrait_panel, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		ptw.tween_property(_portrait_panel, "modulate:a", 1.0, 0.2)
	for lbl in [_name_label, _desc_label]:
		lbl.modulate.a = 0.0
		var ltw := create_tween()
		ltw.tween_property(lbl, "modulate:a", 1.0, 0.3)

	# تحديث معاينة السيارة (الموديل + اللون + الحجم)
	_update_preview(ch, col)

	_battle_btn.disabled = false
	_battle_btn.text = "⚔ ابدأ المعركة"


func _update_preview(ch: Dictionary, col: Color) -> void:
	if _preview_car == null:
		return
	# نرجّع الشكل الأصلي أول (يشيل الموديل السابق ويظهر المرسوم)
	_preview_car.clear_custom_model()
	_preview_model = null
	_preview_car.set_body_color(col)
	_preview_car.apply_class(ch["stats"])
	# نحمّل موديل الشخصية لو موجود
	if ch["model_path"] != "":
		var model := Content.load_model(ch["model_path"])
		if model != null:
			_preview_model = model
			_preview_car.set_custom_model(model, ch)
			_preview_car.set_weapon_heights(ch["weapons_y"])


func _make_button(text: String, font_size: int, color: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", Color(1, 1, 1))
	b.add_theme_color_override("font_pressed_color", Color(1, 1, 1))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))

	var normal := StyleBoxFlat.new()
	normal.bg_color = color
	normal.set_corner_radius_all(14)
	normal.set_content_margin_all(12)
	b.add_theme_stylebox_override("normal", normal)

	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = color.lightened(0.12)
	b.add_theme_stylebox_override("hover", hover)

	var pressed: StyleBoxFlat = normal.duplicate()
	pressed.bg_color = color.darkened(0.2)
	b.add_theme_stylebox_override("pressed", pressed)

	var disabled: StyleBoxFlat = normal.duplicate()
	disabled.bg_color = Color(0.2, 0.21, 0.24)
	b.add_theme_stylebox_override("disabled", disabled)

	return b
