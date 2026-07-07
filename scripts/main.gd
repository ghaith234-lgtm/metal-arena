extends Node3D

# ============================================================
#  المشهد الرئيسي - المرحلة 4
#  ساحة + أهداف + صناديق أسلحة عشوائية + HUD موسع
# ============================================================

const ARENA_SIZE := 120.0

const DUMMY_SPOTS = [
	Vector3(-12.0, 1.5, -14.0),
	Vector3(16.0, 1.5, 6.0),
	Vector3(-24.0, 1.5, 20.0),
	Vector3(8.0, 1.5, -26.0),
]

const DUMMY_COLORS = [
	Color(0.2, 0.5, 0.9),
	Color(0.2, 0.75, 0.35),
	Color(0.85, 0.65, 0.15),
	Color(0.6, 0.3, 0.8),
]

const PICKUP_KINDS = ["rocket", "homing", "mine", "shield", "repair", "rocket", "mine", "homing", "shield", "repair"]
const SPECIAL_NAMES = {"rocket": "قاذف", "homing": "متتبع", "mine": "لغم"}
const SPECIAL_CODES = {"rocket": "R", "homing": "H", "mine": "M"}

var car: ArcadeCar
var controls: TouchControls
var _cam: ChaseCamera
var _weather: Weather
var _nuke: NukeEvent
var _nuke_flash_rect: ColorRect
var _announce_label: Label
var _announce_time := 0.0
var _radar: Radar
var _lock_marker: Control
var _shield_label: Label
var _dummies: Array = []
var _speed_label: Label
var _kills_label: Label
var _ammo_label: Label
var _center_label: Label
var _drift_label: Label
var _hitmarker: Label
var _hp_fill: ColorRect
var _boost_fill: ColorRect
var _kills := 0
var _last_hp := 100.0
var _marker_time := 0.0
var _drift_time := 0.0


func _ready() -> void:
	_build_environment()
	_build_arena()
	_build_ui()
	_spawn_player()
	_spawn_dummies()
	_spawn_pickups()
	_spawn_camera()
	Fx.boom.connect(_on_boom)
	if _weather != null and car != null:
		_weather.set_follow(car)
	_setup_nuke_event()
	_refresh_ammo()


func _setup_nuke_event() -> void:
	_nuke = NukeEvent.new()
	_nuke.get_cars = _get_all_cars
	add_child(_nuke)
	_nuke.announce.connect(_on_nuke_announce)
	_nuke.nuke_flash.connect(_on_nuke_flash)


func _get_all_cars() -> Array:
	var list: Array = []
	if car != null and is_instance_valid(car):
		list.append(car)
	for d in _dummies:
		if is_instance_valid(d):
			list.append(d)
	return list


func _process(delta: float) -> void:
	if car != null and _speed_label != null:
		_speed_label.text = "%d km/h" % roundi(car.get_speed_kmh())
	if _marker_time > 0.0:
		_marker_time -= delta
		if _marker_time <= 0.0:
			_hitmarker.visible = false
	if _drift_time > 0.0:
		_drift_time -= delta
		_drift_label.modulate.a = clampf(_drift_time / 0.5, 0.0, 1.0)
		if _drift_time <= 0.0:
			_drift_label.visible = false
	_update_lock_marker()
	_update_nuke_hud(delta)
	# نحدّث هدف الرادار (النووي)
	if _radar != null and _nuke != null:
		_radar.objective = _nuke.get_objective()
	# عدّاد الدرع
	if car != null and car.shield_time > 0.0:
		_shield_label.visible = true
		_shield_label.text = "🛡 درع %.1f" % car.shield_time
	elif _shield_label.visible:
		_shield_label.visible = false


func _update_lock_marker() -> void:
	if car == null or _cam == null or _lock_marker == null:
		return
	var tgt = car.aim_target
	if tgt == null or not is_instance_valid(tgt) or not car.alive:
		_lock_marker.visible = false
		return
	var world := tgt.global_position + Vector3.UP * 0.4
	if _cam.is_position_behind(world):
		_lock_marker.visible = false
		return
	var screen := _cam.unproject_position(world)
	_lock_marker.position = screen - _lock_marker.size / 2.0
	_lock_marker.visible = true
	_lock_marker.queue_redraw()


func _draw_lock_marker() -> void:
	var s := _lock_marker.size
	var c := Color(1.0, 0.3, 0.25)
	var L := 14.0
	# أربع زوايا بركِت
	var corners := [
		[Vector2(0, 0), Vector2(L, 0), Vector2(0, L)],
		[Vector2(s.x, 0), Vector2(s.x - L, 0), Vector2(s.x, L)],
		[Vector2(0, s.y), Vector2(L, s.y), Vector2(0, s.y - L)],
		[Vector2(s.x, s.y), Vector2(s.x - L, s.y), Vector2(s.x, s.y - L)],
	]
	for cr in corners:
		_lock_marker.draw_line(cr[0], cr[1], c, 3.0)
		_lock_marker.draw_line(cr[0], cr[2], c, 3.0)


# ---------- السماء والإضاءة ----------

func _build_environment() -> void:
	_weather = Weather.new()
	add_child(_weather)
	_weather.randomize_weather()      # وقت وطقس عشوائي كل جولة


# ---------- الساحة ----------

func _build_arena() -> void:
	var half := ARENA_SIZE / 2.0

	# أرضية حشائش
	_add_ground(Vector3(0, -0.5, 0), Vector3(ARENA_SIZE, 1.0, ARENA_SIZE), Color(0.28, 0.42, 0.2))

	# شبكة شوارع (رمادية) متقاطعة
	var road_c := Color(0.22, 0.22, 0.24)
	var line_c := Color(0.85, 0.8, 0.3)
	for x in [-36.0, 0.0, 36.0]:
		_add_ground(Vector3(x, 0.02, 0), Vector3(8.0, 0.06, ARENA_SIZE), road_c, true)
	for z in [-36.0, 0.0, 36.0]:
		_add_ground(Vector3(0, 0.02, z), Vector3(ARENA_SIZE, 0.06, 8.0), road_c, true)
	# خطوط منتصف الشارع
	for x in [-36.0, 0.0, 36.0]:
		for i in range(-5, 6):
			_add_ground(Vector3(x, 0.05, i * 10.0), Vector3(0.4, 0.02, 3.0), line_c)

	# جدران محيطة
	var wall_c := Color(0.4, 0.42, 0.48)
	_add_box(Vector3(0, 2.0, -half), Vector3(ARENA_SIZE + 4.0, 4.0, 2.0), wall_c)
	_add_box(Vector3(0, 2.0, half), Vector3(ARENA_SIZE + 4.0, 4.0, 2.0), wall_c)
	_add_box(Vector3(-half, 2.0, 0), Vector3(2.0, 4.0, ARENA_SIZE + 4.0), wall_c)
	_add_box(Vector3(half, 2.0, 0), Vector3(2.0, 4.0, ARENA_SIZE + 4.0), wall_c)

	# منحدرات للقفز
	var ramp_c := Color(0.7, 0.6, 0.25)
	_add_box(Vector3(18, 0.85, -18), Vector3(8.0, 0.5, 7.0), ramp_c, Vector3(-16.0, 0.0, 0.0))
	_add_box(Vector3(-18, 0.85, 18), Vector3(8.0, 0.5, 7.0), ramp_c, Vector3(-16.0, 180.0, 0.0))

	_spawn_destructibles()


func _spawn_destructibles() -> void:
	# بنايات بمواقع الأحياء (بين الشوارع)
	var building_spots = [
		[Vector3(-18, 0, -18), Destructible.Kind.BUILDING_TALL],
		[Vector3(18, 0, 18), Destructible.Kind.BUILDING_TALL],
		[Vector3(-18, 0, 18), Destructible.Kind.BUILDING_SMALL],
		[Vector3(18, 0, -18), Destructible.Kind.BUILDING_SMALL],
		[Vector3(-52, 0, 0), Destructible.Kind.BUILDING_SMALL],
		[Vector3(52, 0, 0), Destructible.Kind.BUILDING_TALL],
		[Vector3(0, 0, -52), Destructible.Kind.BUILDING_SMALL],
		[Vector3(0, 0, 52), Destructible.Kind.BUILDING_TALL],
	]
	for spot in building_spots:
		_add_destructible(spot[0], spot[1])

	# أشجار (مواقع نظيفة بعيدة عن الشوارع والمباني والمنحدرات والأهداف)
	var tree_spots = [
		Vector3(-8, 0, -6), Vector3(-12, 0, 18), Vector3(-22, 0, 10), Vector3(42, 0, 26),
		Vector3(-18, 0, 44), Vector3(-48, 0, -20), Vector3(-6, 0, 30), Vector3(-28, 0, -16),
		Vector3(-50, 0, -6), Vector3(-28, 0, -28), Vector3(-16, 0, 28), Vector3(20, 0, 46),
		Vector3(-48, 0, 6), Vector3(-30, 0, 24),
	]
	for t in tree_spots:
		_add_destructible(t, Destructible.Kind.TREE)

	# براميل متفجرة (خطر ومتعة) - مواقع نظيفة
	var barrel_spots = [
		Vector3(22, 0, -10), Vector3(-44, 0, 16), Vector3(-16, 0, -24), Vector3(14, 0, 20),
		Vector3(-26, 0, -44), Vector3(12, 0, -20), Vector3(-50, 0, -44), Vector3(22, 0, -42),
	]
	for bpos in barrel_spots:
		_add_destructible(bpos, Destructible.Kind.BARREL)


func _add_destructible(pos: Vector3, kind: int) -> void:
	var d := Destructible.new()
	add_child(d)
	d.setup(kind)
	d.global_position = pos


func _add_ground(pos: Vector3, box_size: Vector3, color: Color, is_road := false) -> void:
	# أرضية بدون تصادم جانبي مؤثر (مسطحة)
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box_size
	col.shape = shape
	body.add_child(col)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box_size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	# الأسفلت يصير لامع ومبلول لما تمطر
	if is_road and _weather != null and _weather.rain_enabled:
		mat.roughness = 0.25
		mat.metallic = 0.4
	else:
		mat.roughness = 0.9 if is_road else 0.95
	bm.material = mat
	mi.mesh = bm
	body.add_child(mi)
	add_child(body)
	body.position = pos


func _add_box(pos: Vector3, box_size: Vector3, color: Color, rot: Vector3 = Vector3.ZERO) -> void:
	var body := StaticBody3D.new()

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box_size
	col.shape = shape
	body.add_child(col)

	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box_size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	bm.material = mat
	mi.mesh = bm
	body.add_child(mi)

	add_child(body)
	body.position = pos
	body.rotation_degrees = rot


# ---------- الواجهة ----------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	controls = TouchControls.new()
	layer.add_child(controls)

	_speed_label = Label.new()
	_speed_label.position = Vector2(26, 14)
	_speed_label.add_theme_font_size_override("font_size", 30)
	_speed_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	layer.add_child(_speed_label)

	var hp_bg := ColorRect.new()
	hp_bg.color = Color(0, 0, 0, 0.45)
	hp_bg.position = Vector2(26, 58)
	hp_bg.size = Vector2(244, 20)
	layer.add_child(hp_bg)

	_hp_fill = ColorRect.new()
	_hp_fill.color = Color(0.25, 0.85, 0.3)
	_hp_fill.position = Vector2(28, 60)
	_hp_fill.size = Vector2(240, 16)
	layer.add_child(_hp_fill)

	# شريط النيترو تحت شريط الصحة
	var boost_bg := ColorRect.new()
	boost_bg.color = Color(0, 0, 0, 0.45)
	boost_bg.position = Vector2(26, 82)
	boost_bg.size = Vector2(244, 12)
	layer.add_child(boost_bg)

	_boost_fill = ColorRect.new()
	_boost_fill.color = Color(0.3, 0.8, 1.0)
	_boost_fill.position = Vector2(28, 84)
	_boost_fill.size = Vector2(240, 8)
	layer.add_child(_boost_fill)

	_ammo_label = Label.new()
	_ammo_label.position = Vector2(26, 100)
	_ammo_label.add_theme_font_size_override("font_size", 20)
	_ammo_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	layer.add_child(_ammo_label)

	_kills_label = Label.new()
	_kills_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_kills_label.offset_left = -260
	_kills_label.offset_right = -26
	_kills_label.offset_top = 14
	_kills_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_kills_label.add_theme_font_size_override("font_size", 30)
	_kills_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	_kills_label.text = "KILLS: 0"
	layer.add_child(_kills_label)

	_center_label = Label.new()
	_center_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_center_label.offset_top = 170
	_center_label.offset_bottom = 240
	_center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_label.add_theme_font_size_override("font_size", 40)
	_center_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3))
	_center_label.text = "تدمرت! إحياء بعد لحظات..."
	_center_label.visible = false
	layer.add_child(_center_label)

	_drift_label = Label.new()
	_drift_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_drift_label.offset_top = 250
	_drift_label.offset_bottom = 300
	_drift_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_drift_label.add_theme_font_size_override("font_size", 30)
	_drift_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.1))
	_drift_label.visible = false
	layer.add_child(_drift_label)

	_hitmarker = Label.new()
	_hitmarker.set_anchors_and_offsets_preset(Control.PRESET_VCENTER_WIDE)
	_hitmarker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hitmarker.add_theme_font_size_override("font_size", 36)
	_hitmarker.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	_hitmarker.text = "+"
	_hitmarker.visible = false
	layer.add_child(_hitmarker)

	var menu_btn := Button.new()
	menu_btn.text = "⟵ القائمة"
	menu_btn.add_theme_font_size_override("font_size", 20)
	menu_btn.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	menu_btn.offset_left = -85
	menu_btn.offset_right = 85
	menu_btn.offset_top = 12
	menu_btn.offset_bottom = 56
	menu_btn.modulate = Color(1, 1, 1, 0.7)
	menu_btn.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/menu.tscn"))
	layer.add_child(menu_btn)

	# الرادار (خريطة الأعداء) فوق يمين تحت عداد القتل
	_radar = Radar.new()
	_radar.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_radar.offset_left = -210
	_radar.offset_top = 60
	_radar.offset_right = -20
	_radar.offset_bottom = 250
	layer.add_child(_radar)

	# علامة قفل الهدف (توجيه ذكي)
	_lock_marker = Control.new()
	_lock_marker.custom_minimum_size = Vector2(60, 60)
	_lock_marker.size = Vector2(60, 60)
	_lock_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lock_marker.visible = false
	_lock_marker.draw.connect(_draw_lock_marker)
	layer.add_child(_lock_marker)

	# مؤشر الدرع
	_shield_label = Label.new()
	_shield_label.position = Vector2(26, 124)
	_shield_label.add_theme_font_size_override("font_size", 22)
	_shield_label.add_theme_color_override("font_color", Color(0.3, 0.75, 1.0))
	_shield_label.visible = false
	layer.add_child(_shield_label)

	# رسالة إعلان حدث النووي (وسط أعلى)
	_announce_label = Label.new()
	_announce_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_announce_label.offset_top = 90
	_announce_label.offset_bottom = 140
	_announce_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_announce_label.add_theme_font_size_override("font_size", 34)
	_announce_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.1))
	_announce_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_announce_label.add_theme_constant_override("outline_size", 6)
	_announce_label.visible = false
	layer.add_child(_announce_label)

	# طبقة الوميض الأبيض (انفجار النووي)
	_nuke_flash_rect = ColorRect.new()
	_nuke_flash_rect.color = Color(1, 1, 1, 0)
	_nuke_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_nuke_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_nuke_flash_rect)


# ---------- السيارات والصناديق ----------

func _spawn_player() -> void:
	car = ArcadeCar.new()
	var ch: Dictionary = Global.CHARACTERS[Global.selected_character]
	car.body_color = ch["color"]
	car.max_health = ch["health"]
	car.gun_damage = ch["damage"]
	car.engine_power = 1500.0 * ch["speed"]
	car.max_speed = 28.0 * ch["speed"]
	car.controls = controls
	car.position = Vector3(0, 1.5, 30)
	add_child(car)
	car.health_changed.connect(_on_player_health)
	car.died.connect(_on_player_died)
	car.respawned.connect(_on_player_respawned)
	car.hit_landed.connect(_on_hit_landed)
	car.ammo_changed.connect(_refresh_ammo)
	car.drifted.connect(_on_drifted)
	car.boost_changed.connect(_on_boost_changed)
	car.mine_charging.connect(_on_mine_charging)
	car.shield_changed.connect(_on_shield_changed)
	car.critical_started.connect(_on_critical_started)
	car.critical_tick.connect(_on_critical_tick)
	car.critical_ended.connect(_on_critical_ended)


func _spawn_dummies() -> void:
	for i in 4:
		var d := ArcadeCar.new()
		d.body_color = DUMMY_COLORS[i]
		d.position = DUMMY_SPOTS[i]
		d.rotation.y = randf() * TAU
		if Global.game_mode == Global.Mode.AI:
			# عدو ذكي فعّال
			d.input_enabled = true
			d.ai_controlled = true
			# نعطيه ذخيرة ابتدائية حتى يستخدم الأسلحة
			d.ammo["rocket"] = 3
			d.ammo["homing"] = 2
		else:
			# هدف ثابت (وضع التجربة)
			d.input_enabled = false
		add_child(d)
		d.died.connect(_on_dummy_died)
		d.respawned.connect(_on_dummy_respawned.bind(d))
		_dummies.append(d)

		# نركّب دماغ الذكاء الاصطناعي
		if Global.game_mode == Global.Mode.AI:
			var brain := CarAI.new()
			brain.car = d
			brain.get_enemies = _get_ai_enemies
			d.add_child(brain)

	if _radar != null and car != null:
		_radar.setup(car, _dummies)


func _get_ai_enemies() -> Array:
	# أعداء الـ AI = اللاعب + باقي سيارات الـ AI (كلهم يتقاتلون)
	var list: Array = []
	if car != null and is_instance_valid(car):
		list.append(car)
	for d in _dummies:
		list.append(d)
	return list


func _on_dummy_respawned(d: Node) -> void:
	# نعيد ذخيرة الـ AI عند الإحياء
	if Global.game_mode == Global.Mode.AI and is_instance_valid(d):
		d.ammo["rocket"] = 3
		d.ammo["homing"] = 2


func _spawn_pickups() -> void:
	for kind in PICKUP_KINDS:
		var p := WeaponPickup.new()
		p.kind = kind
		add_child(p)
		p.global_position = Vector3(randf_range(-48.0, 48.0), 0.0, randf_range(-48.0, 48.0))


func _spawn_camera() -> void:
	_cam = ChaseCamera.new()
	_cam.target = car
	add_child(_cam)
	_cam.make_current()


# ---------- ربط الإشارات ----------

func _on_player_health(current: float, maximum: float) -> void:
	var r := clampf(current / maximum, 0.0, 1.0)
	_hp_fill.size.x = 240.0 * r
	_hp_fill.color = Color(0.9, 0.2, 0.15).lerp(Color(0.25, 0.85, 0.3), r)
	# اهتزاز عند نقص الصحة (تعرّضت لضرر)
	if current < _last_hp - 0.5:
		Fx.vibrate(40)
	_last_hp = current


func _on_player_died(_attacker) -> void:
	_center_label.visible = true
	_cam.add_trauma(0.7)
	Fx.vibrate(220)


func _on_player_respawned() -> void:
	_center_label.visible = false
	_last_hp = car.max_health if car != null else 100.0


func _on_dummy_died(attacker) -> void:
	if attacker == car:
		_kills += 1
		_kills_label.text = "KILLS: %d" % _kills


func _on_hit_landed() -> void:
	_hitmarker.visible = true
	_marker_time = 0.08
	Fx.vibrate(15)


func _on_boom(pos: Vector3, strength: float) -> void:
	if car == null:
		return
	var d := car.global_position.distance_to(pos)
	var reach := 30.0 * strength
	var intensity := clampf((0.85 - d / reach) * strength, 0.0, 1.4)
	_cam.add_trauma(intensity)
	# اهتزاز حسب قرب الانفجار
	if intensity > 0.1:
		Fx.vibrate(int(clampf(intensity * 120.0, 20.0, 200.0)))


func _on_drifted(duration: float) -> void:
	_drift_label.text = "تفحيط %.1f ثانية!" % duration
	_drift_label.visible = true
	_drift_label.modulate.a = 1.0
	_drift_time = 1.6


func _on_boost_changed(current: float, maximum: float) -> void:
	var r := clampf(current / maximum, 0.0, 1.0)
	_boost_fill.size.x = 240.0 * r
	_boost_fill.color = Color(0.9, 0.4, 0.2).lerp(Color(0.3, 0.8, 1.0), r)
	controls.set_boost_ratio(r)


func _on_shield_changed(active: bool, _time_left: float) -> void:
	_shield_label.visible = active


func _on_nuke_announce(text: String) -> void:
	_announce_label.text = text
	_announce_label.visible = true
	_announce_label.modulate.a = 1.0
	_announce_time = 3.5
	Fx.vibrate(60)


func _on_nuke_flash() -> void:
	_nuke_flash_rect.color = Color(1, 1, 1, 1)     # وميض أبيض كامل


func _update_nuke_hud(delta: float) -> void:
	# تلاشي الإعلان
	if _announce_time > 0.0:
		_announce_time -= delta
		if _announce_time < 0.6:
			_announce_label.modulate.a = clampf(_announce_time / 0.6, 0.0, 1.0)
		if _announce_time <= 0.0:
			_announce_label.visible = false
	# تلاشي وميض النووي
	if _nuke_flash_rect.color.a > 0.0:
		_nuke_flash_rect.color.a = maxf(_nuke_flash_rect.color.a - delta * 0.7, 0.0)
	# لو اللاعب يحمل النووي: عداد + زر إطلاق (إلا لو بالحالة الحرجة)
	if car != null and car.nuke_carrier and not car.critical:
		controls.set_show_detonate(true)
		_center_label.visible = true
		_center_label.modulate = Color(0.4, 1.0, 0.3)
		_center_label.text = "🚀 أطلق النووي! %.1f" % _nuke.get_carry_left()
	elif _nuke != null and _nuke.get_carrier() != null and _nuke.get_carrier() != car:
		# عدو يحمله - تحذير
		if not car.critical:
			_center_label.visible = true
			_center_label.modulate = Color(1.0, 0.5, 0.1)
			_center_label.text = "⚠ عدو يحمل النووي — دمّره!"
	elif not (car != null and car.critical):
		if _center_label.modulate.g > 0.5 or _center_label.text.begins_with("⚠ عدو") or _center_label.text.begins_with("🚀"):
			_center_label.visible = false


func _on_critical_started(_time_left: float) -> void:
	_center_label.visible = true
	_center_label.modulate = Color(1.0, 0.25, 0.15)
	controls.set_show_detonate(true)
	Fx.vibrate(150)


func _on_critical_tick(time_left: float) -> void:
	_center_label.visible = true
	_center_label.text = "⚠ خطر! فجّر سيارتك على العدو — %.1f" % time_left
	_center_label.modulate = Color(1.0, 0.25, 0.15)
	# نبض اهتزاز كل ثانية تقريباً
	if int(time_left * 2.0) != int((time_left + 0.05) * 2.0):
		Fx.vibrate(30)


func _on_critical_ended() -> void:
	controls.set_show_detonate(false)
	if car != null and car.alive:
		_center_label.visible = false
		_center_label.modulate = Color(1.0, 0.35, 0.3)


func _on_mine_charging(ratio: float) -> void:
	controls.set_mine_charge(ratio)
	if ratio > 0.0:
		_center_label.visible = true
		_center_label.text = "توحيد العبوات... %d%%" % roundi(ratio * 100.0)
		_center_label.modulate = Color(1.0, 0.55, 0.1)
	elif car != null and car.alive:
		_center_label.visible = false
		_center_label.modulate = Color(1.0, 0.35, 0.3)


func _refresh_ammo() -> void:
	if car == null:
		return
	var parts := []
	for k in ["rocket", "homing"]:
		var seg: String = "%s %d" % [SPECIAL_NAMES[k], car.ammo[k]]
		if k == car.special:
			seg = "« " + seg + " »"
		parts.append(seg)
	parts.append("%s %d" % [SPECIAL_NAMES["mine"], car.ammo["mine"]])
	_ammo_label.text = "  |  ".join(parts)
	controls.set_special_text("%s%d" % [SPECIAL_CODES[car.special], car.ammo[car.special]])
	controls.set_mine_text("لغم %d" % car.ammo["mine"])
