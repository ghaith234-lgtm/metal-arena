extends Control

# ============================================================
#  القائمة الرئيسية + اختيار الشخصيات (ستايل ببجي)
#  START GAME -> بطاقة الشخصية + سيارتها تدور 3D -> المعركة
# ============================================================

var _title_page: Control
var _select_page: Control
var _portrait: TextureRect
var _portrait_fallback: Label
var _portrait_panel: Panel
var _name_label: Label
var _desc_label: Label
var _counter_label: Label
var _battle_btn: Button
var _stat_fills: Array = []
var _preview_car: ArcadeCar
var _index := 0


func _ready() -> void:
	_build_title_page()
	_build_select_page()
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

	var sub := Label.new()
	sub.text = "حرب سيارات — ساحة الموت"
	sub.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	sub.offset_top = 252
	sub.offset_bottom = 300
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 28)
	sub.add_theme_color_override("font_color", Color(0.7, 0.72, 0.78))
	_title_page.add_child(sub)

	var start := _make_button("START GAME", 42, Color(0.85, 0.16, 0.1))
	start.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	start.offset_left = -210
	start.offset_right = 210
	start.offset_top = 70
	start.offset_bottom = 165
	start.pressed.connect(_show_select)
	_title_page.add_child(start)

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
	_title_page.visible = true
	_select_page.visible = false


func _show_select() -> void:
	_title_page.visible = false
	_select_page.visible = true
	_refresh()


func _prev_character() -> void:
	_index = (_index - 1 + Global.CHARACTERS.size()) % Global.CHARACTERS.size()
	_refresh()


func _next_character() -> void:
	_index = (_index + 1) % Global.CHARACTERS.size()
	_refresh()


func _start_battle() -> void:
	Global.selected_character = _index
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _refresh() -> void:
	var ch: Dictionary = Global.CHARACTERS[_index]
	var locked: bool = ch["locked"]

	_name_label.text = ch["name"]
	_desc_label.text = ch["desc"]
	_counter_label.text = "%d / %d" % [_index + 1, Global.CHARACTERS.size()]

	if ch["portrait"] != "":
		_portrait.texture = load(ch["portrait"])
		_portrait.visible = true
		_portrait_fallback.visible = false
	else:
		_portrait.visible = false
		_portrait_fallback.visible = true
		_portrait_fallback.text = "؟" if locked else ch["name"].substr(0, 2)

	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0.11, 0.12, 0.16)
	frame.border_color = ch["color"]
	frame.set_border_width_all(4)
	frame.set_corner_radius_all(12)
	_portrait_panel.add_theme_stylebox_override("panel", frame)
	_name_label.add_theme_color_override("font_color", Color(1, 1, 1) if not locked else Color(0.55, 0.56, 0.6))

	var speed_r: float = clampf((ch["speed"] - 0.7) / 0.6, 0.05, 1.0)
	var hp_r: float = clampf((ch["health"] - 50.0) / 100.0, 0.05, 1.0)
	var dmg_r: float = clampf((ch["damage"] - 5.0) / 6.0, 0.05, 1.0)
	var ratios := [speed_r, hp_r, dmg_r]
	for i in 3:
		var fill: ColorRect = _stat_fills[i]
		var r: float = 0.0 if locked else ratios[i]
		fill.offset_right = fill.offset_left + 231.0 * r
		fill.color = ch["color"] if not locked else Color(0.3, 0.3, 0.33)

	_preview_car.set_body_color(ch["color"] if not locked else Color(0.16, 0.17, 0.2))

	_battle_btn.disabled = locked
	_battle_btn.text = "🔒 مقفلة" if locked else "⚔ ابدأ المعركة"


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
