extends Node3D

# ============================================================
#  المشهد الرئيسي: يبني الساحة والإضاءة والواجهة بالكود
#  (بدون أي أصول خارجية - كلشي primitives ملونة)
# ============================================================

const ARENA_SIZE := 120.0

var car: ArcadeCar
var controls: TouchControls
var _speed_label: Label


func _ready() -> void:
	_build_environment()
	_build_arena()
	_build_ui()
	_spawn_car()
	_spawn_camera()


func _process(_delta: float) -> void:
	if car != null and _speed_label != null:
		_speed_label.text = "%d km/h" % roundi(car.get_speed_kmh())


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

	# الأرضية
	_add_box(Vector3(0, -0.5, 0), Vector3(ARENA_SIZE, 1.0, ARENA_SIZE), Color(0.17, 0.18, 0.2))

	# الجدران المحيطة
	var wall_c := Color(0.75, 0.3, 0.12)
	_add_box(Vector3(0, 2.0, -half), Vector3(ARENA_SIZE + 4.0, 4.0, 2.0), wall_c)
	_add_box(Vector3(0, 2.0, half), Vector3(ARENA_SIZE + 4.0, 4.0, 2.0), wall_c)
	_add_box(Vector3(-half, 2.0, 0), Vector3(2.0, 4.0, ARENA_SIZE + 4.0), wall_c)
	_add_box(Vector3(half, 2.0, 0), Vector3(2.0, 4.0, ARENA_SIZE + 4.0), wall_c)

	# منحدرات (قفزات) بثلاث اتجاهات
	var ramp_c := Color(0.85, 0.7, 0.2)
	_add_box(Vector3(18, 0.85, -12), Vector3(9.0, 0.5, 8.0), ramp_c, Vector3(-16.0, 0.0, 0.0))
	_add_box(Vector3(-20, 0.85, 15), Vector3(9.0, 0.5, 8.0), ramp_c, Vector3(-16.0, 180.0, 0.0))
	_add_box(Vector3(-5, 0.85, -30), Vector3(9.0, 0.5, 8.0), ramp_c, Vector3(-16.0, 90.0, 0.0))

	# أعمدة للمناورة والاختباء
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


# ---------- السيارة والكاميرا ----------

func _spawn_car() -> void:
	car = ArcadeCar.new()
	car.controls = controls
	car.position = Vector3(0, 1.5, 30)
	add_child(car)


func _spawn_camera() -> void:
	var cam := ChaseCamera.new()
	cam.target = car
	add_child(cam)
	cam.make_current()
