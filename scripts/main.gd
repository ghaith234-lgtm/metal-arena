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

const PICKUP_KINDS = ["rocket", "homing", "mine", "rocket", "mine", "homing"]
const SPECIAL_NAMES = {"rocket": "قاذف", "homing": "متتبع", "mine": "لغم"}
const SPECIAL_CODES = {"rocket": "R", "homing": "H", "mine": "M"}

var car: ArcadeCar
var controls: TouchControls
var _cam: ChaseCamera
var _speed_label: Label
var _kills_label: Label
var _ammo_label: Label
var _center_label: Label
var _drift_label: Label
var _hitmarker: Label
var _hp_fill: ColorRect
var _boost_fill: ColorRect
var _kills := 0
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
	_refresh_ammo()


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


# ---------- السماء والإضاءة ----------

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.2, 0.42, 0.75)
	sky_mat.sky_horizon_color = Color(0.7, 0.78, 0.88)
	sky_mat.ground_bottom_color = Color(0.15, 0.16, 0.18)
	sky_mat.ground_horizon_color = Color(0.5, 0.55, 0.6)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.6, 0.68, 0.78)
	env.fog_density = 0.006
	env.fog_sky_affect = 0.15
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	add_child(sun)


# ---------- الساحة ----------

func _build_arena() -> void:
	var half := ARENA_SIZE / 2.0

	_add_box(Vector3(0, -0.5, 0), Vector3(ARENA_SIZE, 1.0, ARENA_SIZE), Color(0.17, 0.18, 0.2))

	var wall_c := Color(0.75, 0.3, 0.12)
	_add_box(Vector3(0, 2.0, -half), Vector3(ARENA_SIZE + 4.0, 4.0, 2.0), wall_c)
	_add_box(Vector3(0, 2.0, half), Vector3(ARENA_SIZE + 4.0, 4.0, 2.0), wall_c)
	_add_box(Vector3(-half, 2.0, 0), Vector3(2.0, 4.0, ARENA_SIZE + 4.0), wall_c)
	_add_box(Vector3(half, 2.0, 0), Vector3(2.0, 4.0, ARENA_SIZE + 4.0), wall_c)

	var ramp_c := Color(0.85, 0.7, 0.2)
	_add_box(Vector3(18, 0.85, -12), Vector3(9.0, 0.5, 8.0), ramp_c, Vector3(-16.0, 0.0, 0.0))
	_add_box(Vector3(-20, 0.85, 15), Vector3(9.0, 0.5, 8.0), ramp_c, Vector3(-16.0, 180.0, 0.0))
	_add_box(Vector3(-5, 0.85, -30), Vector3(9.0, 0.5, 8.0), ramp_c, Vector3(-16.0, 90.0, 0.0))

	var pillar_c := Color(0.35, 0.4, 0.5)
	var spots := [
		Vector3(0, 1.5, 12),
		Vector3(10, 1.5, 28),
		Vector3(-14, 1.5, -8),
		Vector3(25, 1.5, 20),
		Vector3(-30, 1.5, -22),
		Vector3(30, 1.5, -30),
	]
	for s in spots:
		_add_box(s, Vector3(2.5, 3.0, 2.5), pillar_c)


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


func _spawn_dummies() -> void:
	for i in 4:
		var d := ArcadeCar.new()
		d.input_enabled = false
		d.body_color = DUMMY_COLORS[i]
		d.position = DUMMY_SPOTS[i]
		d.rotation.y = randf() * TAU
		add_child(d)
		d.died.connect(_on_dummy_died)


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


func _on_player_died(_attacker) -> void:
	_center_label.visible = true
	_cam.add_trauma(0.7)


func _on_player_respawned() -> void:
	_center_label.visible = false


func _on_dummy_died(attacker) -> void:
	if attacker == car:
		_kills += 1
		_kills_label.text = "KILLS: %d" % _kills


func _on_hit_landed() -> void:
	_hitmarker.visible = true
	_marker_time = 0.08


func _on_boom(pos: Vector3, strength: float) -> void:
	if car == null:
		return
	var d := car.global_position.distance_to(pos)
	var reach := 30.0 * strength
	_cam.add_trauma(clampf((0.85 - d / reach) * strength, 0.0, 1.4))


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
