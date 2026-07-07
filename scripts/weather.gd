class_name Weather
extends Node3D

# ============================================================
#  نظام الطقس والوقت:
#  - دورة ليل/نهار تحرّك الشمس وتغير ألوان السماء والضباب
#  - مطر (جزيئات) + غيوم تعتم الجو
#  - يبدأ بوقت عشوائي وحالة طقس عشوائية كل جولة
# ============================================================

@export var day_length := 120.0        # ثواني دورة كاملة (نهار+ليل)
@export var rain_enabled := false
@export var time_of_day := 0.35        # 0=منتصف الليل، 0.25=شروق، 0.5=ظهر، 0.75=غروب

var _env: Environment
var _sky_mat: ProceduralSkyMaterial
var _sun: DirectionalLight3D
var _moon: DirectionalLight3D
var _rain: GPUParticles3D
var _follow: Node3D                     # الرادار/الكاميرا يتبعها المطر (اللاعب)

# ألوان المفاتيح على مدار اليوم (top, horizon, sun energy, ambient)
const SKY_KEYS = [
	# t,    top,                    horizon,                sun_e, amb
	[0.0,  Color(0.02,0.02,0.06),  Color(0.05,0.05,0.1),   0.0,  0.15],  # منتصف الليل
	[0.22, Color(0.15,0.12,0.2),   Color(0.5,0.35,0.3),    0.3,  0.35],  # قبيل الشروق
	[0.28, Color(0.35,0.45,0.7),   Color(0.9,0.6,0.4),     1.0,  0.7],   # شروق
	[0.5,  Color(0.25,0.5,0.85),   Color(0.7,0.8,0.9),     1.4,  1.0],   # ظهر
	[0.72, Color(0.4,0.4,0.7),     Color(0.95,0.55,0.3),   1.0,  0.7],   # غروب
	[0.78, Color(0.15,0.12,0.22),  Color(0.5,0.3,0.25),    0.3,  0.35],  # بعد الغروب
	[1.0,  Color(0.02,0.02,0.06),  Color(0.05,0.05,0.1),   0.0,  0.15],  # منتصف الليل
]


func _ready() -> void:
	_build_environment()
	_build_lights()
	_build_rain()
	_apply(time_of_day)


func set_follow(n: Node3D) -> void:
	_follow = n


func randomize_weather() -> void:
	time_of_day = randf()
	rain_enabled = randf() < 0.4          # 40% احتمال مطر
	_rain.emitting = rain_enabled
	_apply(time_of_day)


func _process(delta: float) -> void:
	time_of_day = fmod(time_of_day + delta / day_length, 1.0)
	_apply(time_of_day)
	# المطر يتبع اللاعب حتى يغطي كل مكان
	if _follow != null and is_instance_valid(_follow):
		global_position = _follow.global_position


func _apply(t: float) -> void:
	# استيفاء بين مفاتيح السماء
	var top := SKY_KEYS[0][1] as Color
	var hor := SKY_KEYS[0][2] as Color
	var sun_e := 0.0
	var amb := 0.15
	for i in range(SKY_KEYS.size() - 1):
		var a: Array = SKY_KEYS[i]
		var b: Array = SKY_KEYS[i + 1]
		var a_t: float = a[0]
		var b_t: float = b[0]
		if t >= a_t and t <= b_t:
			var k := inverse_lerp(a_t, b_t, t)
			top = (a[1] as Color).lerp(b[1] as Color, k)
			hor = (a[2] as Color).lerp(b[2] as Color, k)
			sun_e = lerpf(float(a[3]), float(b[3]), k)
			amb = lerpf(float(a[4]), float(b[4]), k)
			break

	# الغيوم/المطر تعتم الجو
	if rain_enabled:
		top = top.lerp(Color(0.25, 0.27, 0.3), 0.5)
		hor = hor.lerp(Color(0.4, 0.42, 0.45), 0.5)
		sun_e *= 0.5
		amb *= 0.7

	_sky_mat.sky_top_color = top
	_sky_mat.sky_horizon_color = hor
	_sky_mat.ground_horizon_color = hor.darkened(0.3)
	_env.ambient_light_energy = amb

	# زاوية الشمس: تدور مع الوقت (تطلع من الشرق تغيب بالغرب)
	var sun_ang := (t - 0.25) * 360.0    # 0.25 = شروق عند الأفق
	_sun.rotation_degrees = Vector3(-sun_ang, -35.0, 0.0)
	_sun.light_energy = sun_e * (0.6 if rain_enabled else 1.0)
	_sun.visible = sun_e > 0.02

	# القمر معاكس للشمس (يضيء بالليل)
	_moon.rotation_degrees = Vector3(-(sun_ang + 180.0), -35.0, 0.0)
	var moon_e: float = clampf(0.35 - sun_e, 0.0, 0.35)
	_moon.light_energy = moon_e
	_moon.visible = moon_e > 0.02

	# الضباب يتبع لون الأفق
	_env.fog_light_color = hor.lerp(Color(0.5, 0.5, 0.55), 0.3)
	_env.fog_density = 0.012 if rain_enabled else 0.005


func _build_environment() -> void:
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_sky_mat = ProceduralSkyMaterial.new()
	_sky_mat.sky_top_color = Color(0.25, 0.5, 0.85)
	_sky_mat.sky_horizon_color = Color(0.7, 0.8, 0.9)
	_sky_mat.ground_bottom_color = Color(0.12, 0.13, 0.15)
	_sky_mat.ground_horizon_color = Color(0.4, 0.45, 0.5)
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.ambient_light_energy = 1.0
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES     # ألوان سينمائية أقرب للواقع
	_env.tonemap_white = 1.1
	_env.fog_enabled = true
	_env.fog_light_color = Color(0.6, 0.68, 0.78)
	_env.fog_density = 0.005
	_env.fog_sky_affect = 0.2
	# توهج (مدعوم على الموبايل). SSAO يبقى مطفي لأنه غير مدعوم على Mobile renderer.
	_env.glow_enabled = true
	_env.glow_intensity = 0.2
	_env.glow_bloom = 0.1
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)


func _build_lights() -> void:
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	_sun.light_energy = 1.2
	_sun.light_color = Color(1.0, 0.97, 0.9)
	_sun.shadow_enabled = true
	add_child(_sun)

	_moon = DirectionalLight3D.new()
	_moon.rotation_degrees = Vector3(125.0, -35.0, 0.0)
	_moon.light_energy = 0.0
	_moon.light_color = Color(0.6, 0.7, 0.95)
	_moon.shadow_enabled = true
	add_child(_moon)


func _build_rain() -> void:
	_rain = GPUParticles3D.new()
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(40.0, 1.0, 40.0)
	mat.direction = Vector3(0.1, -1.0, 0.0)
	mat.spread = 3.0
	mat.initial_velocity_min = 28.0
	mat.initial_velocity_max = 34.0
	mat.gravity = Vector3(0.0, -20.0, 0.0)
	mat.scale_min = 0.6
	mat.scale_max = 1.0
	mat.color = Color(0.6, 0.7, 0.85, 0.5)
	_rain.process_material = mat

	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.025, 0.6, 0.025)     # قطرات مطر مستطيلة
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.albedo_color = Color(0.65, 0.72, 0.85, 0.55)
	mesh.material = mm
	_rain.draw_pass_1 = mesh

	_rain.amount = 800
	_rain.lifetime = 1.2
	_rain.preprocess = 1.0
	_rain.visibility_aabb = AABB(Vector3(-45, -5, -45), Vector3(90, 40, 90))
	_rain.position = Vector3(0, 22, 0)
	_rain.emitting = false
	add_child(_rain)
