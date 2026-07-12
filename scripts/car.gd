class_name ArcadeCar
extends RigidBody3D

# ============================================================
#  سيارة أركيد قتالية - المرحلة 4
#  فيزياء + رشاش لا نهائي + أسلحة خاصة محدودة + أصوات + تفحيط
# ============================================================

signal died(attacker)
signal health_changed(current, maximum)
signal shield_changed(active, time_left)
signal critical_started(time_left)
signal critical_tick(time_left)
signal critical_ended
signal fired
signal hit_landed
signal respawned
signal ammo_changed
signal drifted(duration)
signal boost_changed(current, maximum)
signal mine_charging(count)
signal rocket_charging(count)

# ---------- التعليق ----------
@export var suspension_rest: float = 0.5
@export var wheel_radius: float = 0.3
@export var spring_strength: float = 480.0
@export var spring_damping: float = 90.0

# ---------- الدفع ----------
@export var engine_power: float = 1350.0
@export var max_speed: float = 26.0
@export var reverse_speed: float = 10.0
@export var brake_power: float = 2200.0
@export var extra_air_gravity: float = 13.0   # هبوط ثقيل واقعي

# ---------- التحكم ----------
@export var steer_strength: float = 4.5
@export var grip: float = 6.0
@export var drift_grip: float = 1.7
@export var air_steer: float = 0.8
@export var body_color: Color = Color(0.85, 0.16, 0.1)

# ---------- القتال ----------
@export var max_health: float = 250.0
@export var gun_damage: float = 5.0       # الرشاش: لا نهائي بس خفيف
@export var gun_rate: float = 8.0
@export var gun_range: float = 60.0
@export var aim_assist: bool = true            # توجيه ذكي للرشاش نحو أقرب عدو
@export var aim_assist_angle: float = 22.0     # نصف زاوية المخروط (درجات)
@export var aim_assist_strength: float = 0.75  # 0=بدون، 1=قفل كامل على الهدف
@export var respawn_delay: float = 4.0

# ---------- الحالة الحرجة (سيارة انتحارية) ----------
@export var critical_time: float = 5.0         # ثواني قبل الانفجار الذاتي
@export var critical_blast_damage: float = 60.0 # ضرر الانفجار النهائي
@export var critical_blast_radius: float = 8.0  # نصف قطر أكبر من العادي
@export var critical_launch: float = 16.0       # قوة قذف السيارات

# ---------- بوست الاصطدام (نيترو) ----------
@export var boost_max: float = 100.0
@export var boost_force: float = 2250.0        # قوة الدفع
@export var boost_drain: float = 45.0          # استهلاك بالثانية
@export var boost_regen: float = 12.0          # تعبئة بالثانية
@export var boost_ram_damage: float = 22.0     # ضرر الاصطدام وقت البوست
@export var mine_hold_time: float = 3.0        # ثواني الضغط لزرع عبوة عملاقة

var controls: Node = null
var input_enabled := true
var ai_controlled := false        # true = تتحكم بيها CarAI عبر الحقول أدناه
# حقول إدخال الذكاء الاصطناعي
var ai_steer := 0.0
var ai_throttle := 0.0
var ai_drift := false
var ai_fire := false
var ai_rocket := false
var ai_homing := false
var ai_mine := false
var ai_boost := false
var ai_detonate := false
var sounds_enabled := true
var alive := true
var health := 100.0
var shield_time := 0.0            # ثواني الدرع المتبقية
var critical := false             # الحالة الحرجة (على وشك الانفجار)
var critical_left := 0.0
var nuke_carrier := false         # تحمل السلاح النووي حالياً
var nuke_launch_pressed := false  # ضغطت زر إطلاق النووي
var _detonate_in := false
var _detonate_prev := false
var _last_attacker: Node = null
var _alarm_snd: AudioStreamPlayer3D
var _crit_label: Label3D
var _hp_bar: Sprite3D
var _hp_fill: Sprite3D
var _wheel_dust: GPUParticles3D = null
var _dmg_smoke: GPUParticles3D = null
var _dmg_sparks: GPUParticles3D = null
var _dmg_level := 0
var _head_mat: StandardMaterial3D
var _headlights: Array = []
var _headlights_on := false

# الأسلحة الخاصة (محدودة العدد)
var ammo := {"rocket": 0, "homing": 0, "mine": 0}

var wheel_anchors: Array = [
	Vector3(-0.62, -0.15, -0.85),
	Vector3(0.62, -0.15, -0.85),
	Vector3(-0.62, -0.15, 0.85),
	Vector3(0.62, -0.15, 0.85),
]

var _spawn_transform: Transform3D
var _grounded := false
var _drifting := false
var _braking := false
var _firing := false
var _rocket_in := false
var _rocket_prev := false
var _homing_in := false
var _homing_prev := false
var _rocket_cooldown := 0.0
var _homing_cooldown := 0.0
var _rocket_charge := 0        # عدد القذائف المخزنة (ضغط مستمر)
var _rocket_charge_t := 0.0
var _charge_orb: Node3D = null
var _charge_core_mat: StandardMaterial3D = null
var _charge_shell_mat: StandardMaterial3D = null
var _charge_spark_mat: StandardMaterial3D = null
var _charge_sparks: Array = []
var _charge_spark_t := 0.0
var _charge_light: OmniLight3D = null
var _charge_snd: AudioStreamPlayer3D = null
var _steer := 0.0
var _steer_smooth := 0.0
var _throttle := 0.0
var _flip_timer := 0.0
var _ram_cd := 0.0
var _in_water := 0
var _fire_cooldown := 0.0
var _flash_timer := 0.0
var _drift_time := 0.0
var aim_target: Node3D = null      # هدف الايم اسست (مخروط أمامي - للرشاش)
var lock_target: Node3D = null     # 🎯 أقرب عدو 360° (للإشارة الحمراء والمتتبع)
var _boost := 100.0
var _boosting := false
var _boost_in := false
var _mine_in := false
var _mine_prev := false
var _mine_hold := 0.0
var _mine_charge := 0
var _mine_fired_mega := false
var _boost_snd: AudioStreamPlayer3D
var _boost_flame_l: GPUParticles3D
var _boost_flame_r: GPUParticles3D
var _wheel_dist := [0.0, 0.0, 0.0, 0.0]
var _steer_pivots: Array = []
var _spin_nodes: Array = []
var _visual_root: Node3D
var _class_scale := 1.0
var _custom_model: Node3D = null
var _base_wheel_radius := 0.3
var _undercarriage: Node3D = null
var _uc_axle_f: Node3D = null
var _uc_axle_b: Node3D = null
var _uc_spine: Node3D = null
var _uc_diff: Node3D = null
var _uc_posts: Array = []
var _uc_half_w := 0.62
var _mg_tip: Node3D = null
var _mg_flash: MeshInstance3D = null
var _mg_flash_t := 0.0
var _rocket_tip: Node3D = null
var _homing_tip: Node3D = null
var _homing_pod: Node3D = null
var _homing_recoil := 0.0
var _mg_mount: Node3D = null
var _rk_mount: Node3D = null
var _hm_mount: Node3D = null
var _wy_gun := 0.36
var _wy_rocket := 1.12
var _wy_homing := 0.52
var _homing_mode_up := false
var _homing_tilt := 0.0
var _homing_hold_time := 0.0
var _mortar_cd := 0.0

const CHARGE_COLORS = [
	Color(1.0, 0.85, 0.2),    # 1: أصفر
	Color(1.0, 0.5, 0.1),     # 2: برتقالي
	Color(0.95, 0.2, 0.1),    # 3: أحمر
	Color(0.55, 0.15, 0.75),  # 4: بنفسجي
	Color(0.07, 0.06, 0.08),  # 5+: أسود
]
var _body_mat: StandardMaterial3D
var _tail_mat: StandardMaterial3D
var _muzzle: OmniLight3D
var _drift_smoke_l: GPUParticles3D
var _drift_smoke_r: GPUParticles3D
var _damage_smoke: GPUParticles3D
var _shield_mesh: MeshInstance3D
var _shield_mat: StandardMaterial3D
var _engine_snd: AudioStreamPlayer3D
var _engine_pitch := 0.65
var _body_roll := 0.0
var _body_pitch := 0.0
var _prev_speed := 0.0
var _drift_snd: AudioStreamPlayer3D
var _gun_snd: AudioStreamPlayer3D


func _ready() -> void:
	add_to_group("cars")
	_base_wheel_radius = wheel_radius
	mass = 60.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, -0.25, 0.0)
	angular_damp = 1.3   # يسمح بالشقلبات السينمائية
	linear_damp = 0.05
	can_sleep = false
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)
	var pm := PhysicsMaterial.new()
	pm.friction = 0.5
	pm.bounce = 0.2
	physics_material_override = pm
	health = max_health
	_boost = boost_max
	_build_body()
	_build_wheels()
	_build_weapon_mounts()
	_build_hp_bar()
	_build_damage_fx()
	_build_wheel_dust()
	_build_effects()
	_build_sounds()
	_spawn_transform = global_transform


func get_speed_kmh() -> float:
	return linear_velocity.length() * 3.6


func get_boost_ratio() -> float:
	return _boost / boost_max


func set_headlights(on: bool) -> void:
	if on == _headlights_on:
		return
	_headlights_on = on
	var energy := 3.5 if on else 0.0
	for spot in _headlights:
		spot.light_energy = energy
	# المصابيح الأمامية تصير أوضح بالليل
	if _head_mat != null:
		_head_mat.emission_energy_multiplier = 3.0 if on else 1.6


func set_body_color(c: Color) -> void:
	body_color = c
	if _body_mat != null:
		_body_mat.albedo_color = c


# يطبّق فئة السيارة (دبابة/وسط/سريعة) على الإحصائيات
func apply_class(stats: Dictionary) -> void:
	max_health = stats.get("max_health", max_health)
	health = max_health
	engine_power = stats.get("engine_power", engine_power)
	max_speed = stats.get("max_speed", max_speed)
	mass = stats.get("mass", mass)
	gun_damage = stats.get("gun_damage", gun_damage)
	boost_force = stats.get("boost_force", boost_force)
	steer_strength = stats.get("steer_strength", steer_strength)
	_class_scale = stats.get("body_scale", 1.0)


# يضبط مواقع وحجم عجلات اللعبة لتناسب أي جسم سيارة
# front_z/back_z: بعد العجلات عن المركز | half_w: نصف عرض المحور | y: ارتفاع التعليق | size: مضاعف حجم العجلة
func configure_wheels(front_z: float, back_z: float, half_w: float, y: float, size: float) -> void:
	size = clampf(size, 0.3, 4.0)
	wheel_anchors = [
		Vector3(-half_w, y, -front_z),
		Vector3(half_w, y, -front_z),
		Vector3(-half_w, y, back_z),
		Vector3(half_w, y, back_z),
	]
	wheel_radius = _base_wheel_radius * size
	for i in 4:
		var pivot: Node3D = _steer_pivots[i]
		if is_instance_valid(pivot):
			pivot.position = wheel_anchors[i]
		var spin: Node3D = _spin_nodes[i]
		if is_instance_valid(spin):
			spin.scale = Vector3.ONE * size
	_rebuild_undercarriage(front_z, back_z, half_w, y, size)


# شاصي رابط بين العجلات والجسم: محورين + عمود فقري + 4 قوائم تعليق
# يتولد تلقائياً بنفس أبعاد العجلات حتى ما تبين السيارة مفصولة عنها
func _rebuild_undercarriage(front_z: float, back_z: float, half_w: float, y: float, size: float) -> void:
	if _undercarriage != null and is_instance_valid(_undercarriage):
		_undercarriage.queue_free()
	_undercarriage = Node3D.new()
	add_child(_undercarriage)
	_uc_half_w = half_w
	_uc_posts.clear()

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.31, 0.35)
	mat.roughness = 0.55
	mat.metallic = 0.75

	# محورين سميكين يوصلون لداخل العجلات (يتبعون التعليق كل فريم)
	for fi in 2:
		var az: float = -front_z if fi == 0 else back_z
		var axle := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.085 * size
		cyl.bottom_radius = 0.085 * size
		cyl.height = half_w * 2.0 + 0.15 * size
		cyl.material = mat
		axle.mesh = cyl
		axle.rotation.z = PI / 2.0
		axle.position = Vector3(0.0, y, az)
		_undercarriage.add_child(axle)
		if fi == 0:
			_uc_axle_f = axle
		else:
			_uc_axle_b = axle

	# عمود فقري عريض يربط المحورين ببعض
	_uc_spine = MeshInstance3D.new()
	var sb := BoxMesh.new()
	sb.size = Vector3(0.3 * size, 0.16, front_z + back_z)
	sb.material = mat
	_uc_spine.mesh = sb
	_uc_spine.position = Vector3(0.0, y + 0.04, (back_z - front_z) * 0.5)
	_undercarriage.add_child(_uc_spine)

	# كرة الدفرنس الخلفية
	_uc_diff = MeshInstance3D.new()
	var ds := SphereMesh.new()
	ds.radius = 0.13 * size
	ds.height = 0.26 * size
	ds.material = mat
	_uc_diff.mesh = ds
	_uc_diff.position = Vector3(0.0, y, back_z)
	_undercarriage.add_child(_uc_diff)

	# 4 قوائم تعليق تتبع كل عجلة
	for anchor in wheel_anchors:
		var post := MeshInstance3D.new()
		var pb := BoxMesh.new()
		pb.size = Vector3(0.12 * size, 0.42, 0.12 * size)
		pb.material = mat
		post.mesh = pb
		post.position = Vector3(anchor.x * 0.88, y + 0.2, anchor.z)
		_undercarriage.add_child(post)
		_uc_posts.append(post)


# الشاصي ملتصق بالعجلات: يتبع حركة التعليق كل فريم
func _update_undercarriage() -> void:
	if _uc_axle_f == null or not is_instance_valid(_uc_axle_f):
		return
	var y0: float = _steer_pivots[0].position.y
	var y1: float = _steer_pivots[1].position.y
	var y2: float = _steer_pivots[2].position.y
	var y3: float = _steer_pivots[3].position.y
	var w2 := _uc_half_w * 2.0
	# المحور الأمامي يميل مع فرق ارتفاع العجلتين
	_uc_axle_f.position.y = (y0 + y1) * 0.5
	_uc_axle_f.rotation.z = PI / 2.0 - atan2(y1 - y0, w2)
	_uc_axle_b.position.y = (y2 + y3) * 0.5
	_uc_axle_b.rotation.z = PI / 2.0 - atan2(y3 - y2, w2)
	_uc_spine.position.y = (_uc_axle_f.position.y + _uc_axle_b.position.y) * 0.5 + 0.04
	_uc_diff.position.y = _uc_axle_b.position.y
	for i in 4:
		if i < _uc_posts.size() and is_instance_valid(_uc_posts[i]):
			_uc_posts[i].position.y = _steer_pivots[i].position.y + 0.2

func clear_custom_model() -> void:
	if _custom_model != null and is_instance_valid(_custom_model):
		_custom_model.queue_free()
	_custom_model = null
	if _visual_root != null:
		for child in _visual_root.get_children():
			if child is MeshInstance3D:
				child.visible = true
	for pivot in _steer_pivots:
		if is_instance_valid(pivot):
			pivot.visible = true
	configure_wheels(0.85, 0.85, 0.62, -0.15, 1.0)


# يركّب جسم سيارة (glb بدون عجلات - تحذفها ببلندر) فوق عجلات اللعبة.
# بدون أي دمج: عجلات اللعبة فقط، مواقعها تلقائية من أبعاد الجسم أو يدوية من JSON.
# opts من stats.json: scale, rotate_y, flip, lift, hide_game_wheels, wheels{front,back,width,height,size}
func set_custom_model(model: Node3D, opts: Dictionary = {}) -> void:
	if model == null or _visual_root == null:
		return
	var extra_scale: float = opts.get("scale", 1.0)
	var rot_y_deg: float = opts.get("rotate_y", 0.0)
	var lift: float = opts.get("lift", 0.0)
	var hide_game_wheels: bool = opts.get("hide_game_wheels", false)
	var wheel_opts: Dictionary = opts.get("wheels", {})

	# نخفي جسم السيارة المرسوم (نبقي الأضواء والدخان والعجلات)
	for child in _visual_root.get_children():
		if child is MeshInstance3D:
			child.visible = false

	var total_yaw := deg_to_rad(rot_y_deg)
	model.rotation = Vector3(0.0, total_yaw, 0.0)
	var rot := Basis(Vector3.UP, total_yaw)

	# القياس من طول الجسم (بعد الدوران)
	var aabb := _rotate_aabb(_merged_mesh_aabb(model), rot)
	var target_len := 3.0 * _class_scale * extra_scale
	var s := clampf(target_len / maxf(aabb.size.z, 0.05), 0.05, 20.0)
	model.scale = Vector3.ONE * s

	_custom_model = model
	_visual_root.add_child(model)

	if hide_game_wheels:
		for pivot in _steer_pivots:
			if is_instance_valid(pivot):
				pivot.visible = false
		if _undercarriage != null and is_instance_valid(_undercarriage):
			_undercarriage.visible = false
	else:
		# عجلات اللعبة تنضبط تلقائياً على أبعاد الجسم + تجاوز يدوي كامل من JSON
		var body_front: float = absf(aabb.position.z) * s
		var body_back: float = absf(aabb.position.z + aabb.size.z) * s
		var body_halfw: float = aabb.size.x * 0.5 * s
		# القيم اليدوية تتضاعف مع scale => "scale" يكبّر السيارة كاملة (جسم + عجلات + مسافات)
		var w_front: float = (float(wheel_opts["front"]) * extra_scale) if wheel_opts.has("front") else body_front * 0.62
		var w_back: float = (float(wheel_opts["back"]) * extra_scale) if wheel_opts.has("back") else body_back * 0.62
		var w_width: float = (float(wheel_opts["width"]) * extra_scale) if wheel_opts.has("width") else body_halfw * 0.86
		var w_height: float = wheel_opts.get("height", -0.15)
		var w_size: float = (float(wheel_opts["size"]) * extra_scale) if wheel_opts.has("size") else clampf(target_len / 3.0, 0.5, 2.5)
		configure_wheels(w_front, w_back, w_width, w_height, w_size)

	# موضع الجسم: توسيط أفقي + تحكم بالارتفاع عن العجلات بـ lift
	var target_bottom: float = (0.02 if not hide_game_wheels else -0.42) + lift
	var cx := aabb.position.x + aabb.size.x * 0.5
	var cz := aabb.position.z + aabb.size.z * 0.5
	model.position = Vector3(-cx * s, target_bottom - aabb.position.y * s, -cz * s)


func _merged_mesh_aabb(root: Node) -> AABB:
	var res: Array = [AABB(), false]
	_acc_mesh_aabb(root, root, Transform3D.IDENTITY, res)
	if not res[1]:
		return AABB(Vector3(-0.75, 0, -1.5), Vector3(1.5, 1.0, 3.0))
	return res[0]


func _acc_mesh_aabb(root: Node, node: Node, xf: Transform3D, res: Array) -> void:
	var t := xf
	if node != root and node is Node3D:
		t = xf * (node as Node3D).transform
	if node is MeshInstance3D:
		var box: AABB = t * (node as MeshInstance3D).get_aabb()
		if res[1]:
			res[0] = (res[0] as AABB).merge(box)
		else:
			res[0] = box
			res[1] = true
	for c in node.get_children():
		_acc_mesh_aabb(root, c, t, res)


func _rotate_aabb(aabb: AABB, b: Basis) -> AABB:
	var r := AABB(b * aabb.position, Vector3.ZERO)
	for i in 8:
		r = r.expand(b * aabb.get_endpoint(i))
	return r


func enter_water() -> void:
	_in_water += 1
	if _in_water == 1:
		Fx.sound(global_position, "hit", -6.0, 0.5)


func exit_water() -> void:
	_in_water = maxi(_in_water - 1, 0)


func give_ammo(kind: String, amount: int) -> void:
	ammo[kind] += amount
	ammo_changed.emit()


# ============================================================
#  الحلقة الفيزيائية
# ============================================================

func _physics_process(delta: float) -> void:
	if not alive:
		return
	_read_input()
	var wheels_on_ground := 0
	for i in 4:
		if _process_wheel(i):
			wheels_on_ground += 1
	_grounded = wheels_on_ground > 0
	# لو تحمل النووي: زر التفجير يصير زر إطلاق نووي
	nuke_launch_pressed = nuke_carrier and _detonate_in
	_apply_drive(delta)
	_apply_boost(delta)
	if critical:
		_update_critical(delta)
	else:
		_update_aim_target()
		_try_fire(delta)
		_handle_special(delta)
	_track_drift(delta)
	_update_visuals(delta)
	_update_shield(delta)
	_update_sounds(delta)
	_check_recovery(delta)


func _update_critical(delta: float) -> void:
	critical_left = maxf(critical_left - delta, 0.0)
	critical_tick.emit(critical_left)
	# رقم العدّاد العائم
	if _crit_label != null:
		_crit_label.text = "%.1f" % critical_left
	# وميض أحمر متسارع كل ما اقترب الانفجار
	var blink_speed := lerpf(6.0, 22.0, 1.0 - critical_left / critical_time)
	_body_mat.emission_enabled = sin(Time.get_ticks_msec() * 0.001 * blink_speed) > 0.0
	# زر التفجير اليدوي (للاعب) — ينفجر فوراً
	if _detonate_in and not _detonate_prev:
		_die(_last_attacker)
		return
	_detonate_prev = _detonate_in
	# انتهى الوقت => انفجار
	if critical_left <= 0.0:
		_die(_last_attacker)


func _read_input() -> void:
	if not input_enabled:
		_steer = 0.0
		_throttle = 0.0
		_drifting = false
		_braking = false
		_firing = false
		_rocket_in = false
		_homing_in = false
		_boost_in = false
		_mine_in = false
		return
	if ai_controlled:
		_steer = ai_steer
		_throttle = ai_throttle
		_drifting = ai_drift
		_braking = false
		_firing = ai_fire
		_rocket_in = ai_rocket
		_homing_in = ai_homing
		_boost_in = ai_boost
		_mine_in = ai_mine
		_detonate_in = ai_detonate
	elif controls != null:
		_steer = controls.get_steer()
		_throttle = controls.get_throttle()
		_drifting = controls.is_drifting()
		_braking = controls.is_braking()
		_firing = controls.is_firing()
		_rocket_in = controls.is_rocket_pressed()
		_homing_in = controls.is_homing_pressed()
		_boost_in = controls.is_boost_pressed()
		_mine_in = controls.is_mine_pressed()
		_detonate_in = controls.is_detonate_pressed()
	else:
		_steer = Input.get_axis("ui_left", "ui_right")
		_throttle = 0.0
		if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
			_throttle = 1.0
		elif Input.is_key_pressed(KEY_DOWN):
			_throttle = -1.0
		_drifting = Input.is_key_pressed(KEY_SPACE)
		_braking = Input.is_key_pressed(KEY_S)
		_firing = Input.is_key_pressed(KEY_F) or Input.is_key_pressed(KEY_ENTER)
		_rocket_in = Input.is_key_pressed(KEY_Q)      # قاذف
		_homing_in = Input.is_key_pressed(KEY_E)      # متتبع
		_boost_in = Input.is_key_pressed(KEY_SHIFT)
		_mine_in = Input.is_key_pressed(KEY_R)
		_detonate_in = Input.is_key_pressed(KEY_X)


func _process_wheel(i: int) -> bool:
	var b := global_transform.basis
	var up := b.y
	var anchor_local: Vector3 = wheel_anchors[i]
	var from := global_transform * anchor_local
	var ray_len := suspension_rest + wheel_radius
	var to := from - up * ray_len

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)

	if hit.is_empty():
		_wheel_dist[i] = ray_len
		return false

	var dist: float = from.distance_to(hit["position"])
	_wheel_dist[i] = dist

	var compression := clampf(1.0 - (dist - wheel_radius) / suspension_rest, 0.0, 1.0)
	var point_vel := _point_velocity(from)
	var spring_f := spring_strength * compression
	var damp_f := spring_damping * up.dot(point_vel)
	var force := up * (spring_f - damp_f)

	var side := b.x
	var lateral_vel := side.dot(point_vel)
	var current_grip := drift_grip if _drifting else grip
	force += -side * lateral_vel * current_grip * (mass / 4.0)

	apply_force(force, from - global_position)
	return true


func _point_velocity(world_point: Vector3) -> Vector3:
	return linear_velocity + angular_velocity.cross(world_point - global_position)


func _apply_drive(delta: float) -> void:
	if not input_enabled:
		return
	# تنعيم مدخل التوجيه (يمنع القفز والاهتزاز عند الضغط المتكرر)
	_steer_smooth = move_toward(_steer_smooth, _steer, delta * 6.0)
	var b := global_transform.basis
	var fwd := -b.z
	var speed := fwd.dot(linear_velocity)

	# 🌊 الماء يبطّئ ويثقل الحركة
	var water_drag := 1.0
	if _in_water > 0:
		water_drag = 0.45
		apply_central_force(-linear_velocity * mass * 1.6)

	if _grounded:
		# البريك الصريح له الأولوية
		if _braking:
			if speed > 1.0:
				apply_central_force(-fwd * brake_power)
			elif speed > -reverse_speed:
				apply_central_force(-fwd * engine_power * 0.55)
		elif _throttle > 0.05:
			# تسارع للأمام حسب مقدار دفع الجويستيك
			var ratio := clampf(speed / max_speed, 0.0, 1.0)
			apply_central_force(fwd * engine_power * _throttle * (1.0 - ratio * ratio) * water_drag)
		elif _throttle < -0.05:
			# رجوع للخلف
			if speed > 0.5:
				apply_central_force(-fwd * brake_power * 0.8)   # كبح أول
			elif speed > -reverse_speed:
				apply_central_force(fwd * engine_power * _throttle * 0.55)
		else:
			# ما أكو دفع => احتكاك يبطّئ السيارة تدريجياً (ما تنطلق بروحها)
			apply_central_force(-fwd * speed * 6.0)

		# انعطاف واقعي: تحكم مباشر ناعم بسرعة الدوران (بدل عزم يتأرجح)
		var speed_factor := clampf(absf(speed) / 7.0, 0.0, 1.0)
		var reverse_flip := 1.0 if speed >= -0.5 else -1.0
		var drift_mult := 1.35 if _drifting else 1.0
		var target_yaw := -_steer_smooth * steer_strength * 0.55 * drift_mult * speed_factor * reverse_flip
		angular_velocity.y = lerpf(angular_velocity.y, target_yaw, clampf(delta * 9.0, 0.0, 1.0))
		apply_central_force(-b.y * absf(speed) * 9.0)   # داونفورس يثبت السيارة
	else:
		var air_yaw := -_steer_smooth * air_steer * 0.45
		angular_velocity.y = lerpf(angular_velocity.y, air_yaw, clampf(delta * 4.0, 0.0, 1.0))
		apply_central_force(Vector3.DOWN * extra_air_gravity * mass)


# ============================================================
#  بوست الاصطدام (نيترو)
# ============================================================

func _apply_boost(delta: float) -> void:
	var b := global_transform.basis
	var want := _boost_in and _boost > 1.0 and input_enabled
	_boosting = want
	if want:
		var bdir := -global_transform.basis.z
		bdir.y = 0.0
		if bdir.length() > 0.01:
			bdir = bdir.normalized()
		# ⚖️ النيترو محدود بسقف سرعة (ما يتجاوز 1.35× السرعة القصوى)
		var cur_speed := Vector2(linear_velocity.x, linear_velocity.z).length()
		var boost_cap := max_speed * 1.35
		if cur_speed < boost_cap:
			var fade := clampf(1.0 - cur_speed / boost_cap, 0.15, 1.0)
			apply_central_force(bdir * boost_force * fade)
		apply_central_force(Vector3.DOWN * mass * 16.0)   # التوربو يلصقك بالأرض
		_boost = maxf(_boost - boost_drain * delta, 0.0)
	else:
		_boost = minf(_boost + boost_regen * delta, boost_max)
	boost_changed.emit(_boost, boost_max)

	_boost_flame_l.emitting = _boosting
	_boost_flame_r.emitting = _boosting
	if _boost_snd != null:
		if _boosting and not _boost_snd.playing:
			_boost_snd.play()
		elif not _boosting and _boost_snd.playing:
			_boost_snd.stop()


# ============================================================
#  الرشاش (لا نهائي - خفيف)
# ============================================================

func _update_aim_target() -> void:
	if not aim_assist or not input_enabled:
		aim_target = null
		return
	var from: Vector3 = _mg_tip.global_position if (_mg_tip != null and is_instance_valid(_mg_tip)) else global_transform * Vector3(0.0, 0.25, -1.25)
	aim_target = _find_aim_target(from, -global_transform.basis.z)


func _try_fire(delta: float) -> void:
	_fire_cooldown -= delta
	if not _firing or _fire_cooldown > 0.0:
		return
	_fire_cooldown = 1.0 / gun_rate

	var b := global_transform.basis
	var space := get_world_3d().direct_space_state
	# 🧱 نقطة آمنة داخل جسم السيارة (مو فوهة السبطانة البارزة)
	var safe: Vector3 = global_transform * Vector3(0.0, 0.35, -0.5)
	var muzzle: Vector3 = _mg_tip.global_position if (_mg_tip != null and is_instance_valid(_mg_tip)) else global_transform * Vector3(0.0, 0.25, -1.25)

	# فحص حارس: هل السبطانة داخل جدار أو عابرته؟ (يمنع الرصاص يطلع من الجهة الثانية)
	var guard := PhysicsRayQueryParameters3D.create(safe, muzzle)
	guard.exclude = [get_rid()]
	var gh := space.intersect_ray(guard)
	var blocked := not gh.is_empty()
	var from: Vector3 = gh["position"] if blocked else muzzle

	var base_dir := -b.z

	# توجيه ذكي: نميل الاتجاه نحو الهدف المقفول (يتحدث كل إطار)
	if aim_assist and input_enabled and aim_target != null and is_instance_valid(aim_target):
		var to_target := (aim_target.global_position + Vector3.UP * 0.3 - from).normalized()
		base_dir = base_dir.slerp(to_target, aim_assist_strength).normalized()

	var dir := (base_dir + b.x * randf_range(-0.012, 0.012) + b.y * randf_range(-0.008, 0.008)).normalized()

	# ملاصق لجدار: الرصاصة تصطدم بالجدار فوراً (ما تعبره)
	if blocked:
		_spawn_spark(from)
		Fx.sound(from, "hit", -8.0, 1.0)
		var wall = gh["collider"]
		if wall is ArcadeCar or wall is Destructible or wall is NukeCrate:
			wall.take_damage(gun_damage, self)
			hit_landed.emit()
		_spawn_tracer(safe, from)
		_muzzle.light_energy = 3.0
		if _mg_flash != null and is_instance_valid(_mg_flash):
			_mg_flash.visible = true
			_mg_flash.rotation.z = randf() * TAU
		_mg_flash_t = 0.06
		return

	var to := from + dir * gun_range

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)

	var end := to
	if not hit.is_empty():
		end = hit["position"]
		_spawn_spark(end)
		Fx.sound(end, "hit", -8.0, 1.0)
		var col = hit["collider"]
		if col is ArcadeCar:
			col.take_damage(gun_damage, self)
			hit_landed.emit()
		elif col is Destructible or col is NukeCrate:
			col.take_damage(gun_damage, self)
			hit_landed.emit()

	_spawn_tracer(from, end)
	_muzzle.light_energy = 3.0
	# جدحة نار من السبطانة
	if _mg_flash != null and is_instance_valid(_mg_flash):
		_mg_flash.visible = true
		_mg_flash.rotation.z = randf() * TAU
		_mg_flash.scale = Vector3.ONE * randf_range(0.8, 1.3) * Vector3(1.0, 1.0, 1.7)
	_mg_flash_t = 0.06
	apply_central_force(b.z * 90.0)
	if _gun_snd != null:
		_gun_snd.pitch_scale = randf_range(0.92, 1.12)
		_gun_snd.play()
	fired.emit()


func _find_aim_target(from: Vector3, aim_dir: Vector3) -> Node3D:
	# أقرب عدو حي داخل مخروط أمام السيارة وبمرمى واضح
	var cos_limit := cos(deg_to_rad(aim_assist_angle))
	var best: Node3D = null
	var best_score := -1.0
	for c in get_tree().get_nodes_in_group("cars"):
		if c == self or not c.alive:
			continue
		var to: Vector3 = c.global_position + Vector3.UP * 0.3 - from
		var d := to.length()
		if d > gun_range or d < 0.5:
			continue
		var dir_to := to / d
		var dot := aim_dir.dot(dir_to)
		if dot < cos_limit:
			continue
		# نتأكد ما أكو جدار/بناية يحجب الهدف
		var q := PhysicsRayQueryParameters3D.create(from, c.global_position + Vector3.UP * 0.3)
		q.exclude = [get_rid()]
		var h := get_world_3d().direct_space_state.intersect_ray(q)
		if not h.is_empty() and h["collider"] != c:
			continue
		# نفضّل الأقرب لمركز التصويب ثم الأقرب مسافة
		var score := dot - d / gun_range * 0.3
		if score > best_score:
			best_score = score
			best = c
	return best


# ============================================================
#  الأسلحة الخاصة (محدودة)
# ============================================================

func _handle_special(delta: float) -> void:
	_rocket_cooldown -= delta
	_homing_cooldown -= delta
	# القاذف: اضغط باستمرار للتخزين (+1 قذيفة كل نصف ثانية)، ارفع إصبعك للإطلاق
	if _rocket_in:
		if not _rocket_prev:
			_rocket_charge = 0
			_rocket_charge_t = 0.0
			if _rocket_cooldown <= 0.0 and ammo["rocket"] > 0:
				_rocket_charge = 1
				rocket_charging.emit(_rocket_charge)
				_create_charge_orb()
			elif ammo["rocket"] <= 0:
				Fx.sound(global_position, "beep", -12.0, 0.6)
		elif _rocket_charge > 0:
			_rocket_charge_t += delta
			if _rocket_charge_t >= 0.5 and _rocket_charge < ammo["rocket"]:
				_rocket_charge_t = 0.0
				_rocket_charge += 1
				rocket_charging.emit(_rocket_charge)
				Fx.sound(global_position, "beep", -8.0, 1.0 + _rocket_charge * 0.15)
		_update_charge_orb(delta)
	else:
		if _rocket_prev and _rocket_charge > 0:
			_fire_rocket(_rocket_charge)
		_free_charge_orb()
		_rocket_charge = 0
		_rocket_charge_t = 0.0
		if _rocket_prev:
			rocket_charging.emit(0)
	_rocket_prev = _rocket_in
	# المتتبع: نقرة = صاروخ متتبع | استمرار = السبطانة تتحول لفوق => وضع الهاون
	_mortar_cd -= delta
	if _homing_in:
		_homing_hold_time += delta
		if _homing_hold_time >= 0.35 and not _homing_mode_up:
			_homing_mode_up = true
			Fx.sound(global_position, "transform", -3.0, 1.0)
		if _homing_mode_up and _homing_tilt >= 0.9 and _mortar_cd <= 0.0:
			_fire_mortar_nearest()
	else:
		if _homing_prev:
			if _homing_hold_time < 0.35 and _homing_cooldown <= 0.0:
				_fire_homing()
			if _homing_mode_up:
				Fx.sound(global_position, "transform", -6.0, 0.75)
		_homing_mode_up = false
		_homing_hold_time = 0.0
	_homing_prev = _homing_in
	# زر العبوات المنفصل: ضغطة = وحدة، ضغط مستمر 3 ثواني = عبوة عملاقة
	_handle_mine_button(delta)

	# 💥 زر التفجير: بالحالة الحرجة يفجر السيارة | غير هيچ يفجر الألغام البريموت
	if _detonate_in and not _detonate_prev and not critical:
		detonate_remote_mines()
	_detonate_prev = _detonate_in


func _handle_mine_button(delta: float) -> void:
	# 💣 عداد تجميع: كل نصف ثانية تنضاف عبوة (مثل القاذف)
	if _mine_in:
		if not _mine_prev:
			_mine_charge = 0
			_mine_hold = 0.0
			if ammo["mine"] > 0:
				_mine_charge = 1
				mine_charging.emit(_mine_charge)
			else:
				Fx.sound(global_position, "beep", -12.0, 0.6)
		elif _mine_charge > 0:
			_mine_hold += delta
			if _mine_hold >= 0.5 and _mine_charge < ammo["mine"]:
				_mine_hold = 0.0
				_mine_charge += 1
				mine_charging.emit(_mine_charge)
				Fx.sound(global_position, "beep", -9.0, 0.85 + _mine_charge * 0.12)
	else:
		if _mine_prev and _mine_charge > 0:
			if _mine_charge == 1:
				_plant_single_mine()          # ضغطة سريعة = عبوة عادية
			else:
				_plant_mega_mine(_mine_charge)  # مجمعة بقوة العدد
			mine_charging.emit(0)
		_mine_charge = 0
		_mine_hold = 0.0
	_mine_prev = _mine_in


# ---------- كرة الشحن (أسلوب دراغون بول) ⚡ ----------

func _create_charge_orb() -> void:
	if _charge_orb != null:
		return
	_charge_orb = Node3D.new()
	_charge_orb.position = Vector3(0.0, _wy_rocket + 0.25, -0.7)   # فوق القاذف
	add_child(_charge_orb)

	# نواة بيضاء ساطعة
	var core := MeshInstance3D.new()
	var cm := SphereMesh.new()
	cm.radius = 0.16
	cm.height = 0.32
	_charge_core_mat = StandardMaterial3D.new()
	_charge_core_mat.albedo_color = Color(1.0, 1.0, 1.0)
	_charge_core_mat.emission_enabled = true
	_charge_core_mat.emission = Color(0.8, 0.95, 1.0)
	_charge_core_mat.emission_energy_multiplier = 3.0
	_charge_core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.material = _charge_core_mat
	core.mesh = cm
	_charge_orb.add_child(core)

	# غلاف أزرق شفاف (هالة الطاقة)
	var shell := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.27
	sm.height = 0.54
	var shell_mat := StandardMaterial3D.new()
	_charge_shell_mat = shell_mat
	shell_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shell_mat.albedo_color = Color(0.35, 0.7, 1.0, 0.35)
	shell_mat.emission_enabled = true
	shell_mat.emission = Color(0.3, 0.65, 1.0)
	shell_mat.emission_energy_multiplier = 1.2
	shell_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.material = shell_mat
	shell.mesh = sm
	_charge_orb.add_child(shell)

	# شرارات كهرباء (قضبان رفيعة تومض وتتوزع عشوائياً)
	var spark_mat := StandardMaterial3D.new()
	_charge_spark_mat = spark_mat
	spark_mat.albedo_color = Color(0.85, 0.95, 1.0)
	spark_mat.emission_enabled = true
	spark_mat.emission = Color(0.7, 0.9, 1.0)
	spark_mat.emission_energy_multiplier = 2.5
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_charge_sparks.clear()
	for i in 8:
		var spark := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.02, 0.02, 0.4)
		bm.material = spark_mat
		spark.mesh = bm
		_charge_orb.add_child(spark)
		_charge_sparks.append(spark)

	_charge_light = OmniLight3D.new()
	_charge_light.light_color = Color(0.45, 0.75, 1.0)
	_charge_light.light_energy = 2.0
	_charge_light.omni_range = 6.0
	_charge_orb.add_child(_charge_light)

	_charge_orb.scale = Vector3.ONE * 0.25
	if _charge_snd != null:
		_charge_snd.pitch_scale = 1.0
		_charge_snd.play()


func _update_charge_orb(delta: float) -> void:
	if _charge_orb == null:
		return
	# حجم ثابت (بس نبض خفيف) - التقدم يبينه اللون
	var pulse := 1.0 + 0.06 * sin(Time.get_ticks_msec() * 0.02)
	_charge_orb.scale = Vector3.ONE * 0.85 * pulse
	if _charge_core_mat != null:
		_charge_core_mat.emission_energy_multiplier = 2.5 + _rocket_charge + sin(Time.get_ticks_msec() * 0.03) * 0.8
	# وميض الكهرباء: كل شوي نعيد توزيع الشرارات عشوائياً
	_charge_spark_t -= delta
	if _charge_spark_t <= 0.0:
		_charge_spark_t = 0.045
		for spark in _charge_sparks:
			spark.visible = randf() < 0.7
			var dir := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
			spark.position = dir * randf_range(0.18, 0.32)
			spark.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		if _charge_light != null:
			_charge_light.light_energy = 1.6 + randf() * 1.4 + _rocket_charge * 0.4
	# تدرج اللون: أصفر => برتقالي => أحمر => بنفسجي => أسود
	var cc: Color = CHARGE_COLORS[clampi(_rocket_charge - 1, 0, CHARGE_COLORS.size() - 1)]
	if _charge_shell_mat != null:
		_charge_shell_mat.albedo_color = Color(cc.r, cc.g, cc.b, 0.38)
		_charge_shell_mat.emission = cc
	if _charge_spark_mat != null:
		_charge_spark_mat.emission = cc.lerp(Color(1, 1, 1), 0.35)
	if _charge_light != null:
		_charge_light.light_color = cc.lerp(Color(1, 1, 1), 0.3)
	if _charge_snd != null:
		_charge_snd.pitch_scale = 1.0 + _rocket_charge * 0.13


func _free_charge_orb() -> void:
	if _charge_orb != null and is_instance_valid(_charge_orb):
		_charge_orb.queue_free()
	_charge_orb = null
	_charge_core_mat = null
	_charge_shell_mat = null
	_charge_spark_mat = null
	_charge_light = null
	_charge_sparks.clear()
	if _charge_snd != null:
		_charge_snd.stop()


# منصات الأسلحة المرئية: سبطانة رشاش أمام + قاذف فوق + متتبع يمين
# كل سلاح داخل عقدة أم - ارتفاعها يُضبط من weapons.json
# شريط دم فوق السيارة (يواجه الكاميرا دائماً)
# 🔥 أضرار مرئية: كل ما نقص الدم، السيارة تتضرر أكثر
func _build_damage_fx() -> void:
	# دخان من المحرك (يبدأ تحت 60%)
	_dmg_smoke = GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.35
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 25.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 2.0
	pm.gravity = Vector3(0, 0.6, 0)
	pm.scale_min = 0.35
	pm.scale_max = 0.9
	pm.color = Color(0.25, 0.24, 0.23, 0.55)
	_dmg_smoke.process_material = pm
	var sm := SphereMesh.new()
	sm.radius = 0.35
	sm.height = 0.7
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.albedo_color = Color(0.22, 0.21, 0.2, 0.5)
	sm.material = smat
	_dmg_smoke.draw_pass_1 = sm
	_dmg_smoke.amount = 14
	_dmg_smoke.lifetime = 1.4
	_dmg_smoke.emitting = false
	_dmg_smoke.position = Vector3(0.0, 0.55, -1.0)
	add_child(_dmg_smoke)

	# شرر كهربائي (يبدأ تحت 30%)
	_dmg_sparks = GPUParticles3D.new()
	var sp := ParticleProcessMaterial.new()
	sp.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	sp.emission_sphere_radius = 0.5
	sp.direction = Vector3(0, 1, 0)
	sp.spread = 65.0
	sp.initial_velocity_min = 2.5
	sp.initial_velocity_max = 5.5
	sp.gravity = Vector3(0, -9.0, 0)
	sp.scale_min = 0.05
	sp.scale_max = 0.14
	sp.color = Color(1.0, 0.75, 0.3)
	_dmg_sparks.process_material = sp
	var spm := BoxMesh.new()
	spm.size = Vector3(0.05, 0.05, 0.18)
	var spmat := StandardMaterial3D.new()
	spmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spmat.albedo_color = Color(1.0, 0.8, 0.35)
	spmat.emission_enabled = true
	spmat.emission = Color(1.0, 0.6, 0.2)
	spmat.emission_energy_multiplier = 3.0
	spm.material = spmat
	_dmg_sparks.draw_pass_1 = spm
	_dmg_sparks.amount = 10
	_dmg_sparks.lifetime = 0.6
	_dmg_sparks.emitting = false
	_dmg_sparks.position = Vector3(0.0, 0.5, -0.9)
	add_child(_dmg_sparks)


func _update_damage_fx() -> void:
	if _dmg_smoke == null or not is_instance_valid(_dmg_smoke):
		return
	var ratio := clampf(health / maxf(max_health, 1.0), 0.0, 1.0)
	var lvl := 0
	if ratio < 0.3:
		lvl = 3
	elif ratio < 0.6:
		lvl = 2
	elif ratio < 0.85:
		lvl = 1
	if lvl == _dmg_level:
		return
	_dmg_level = lvl
	_dmg_smoke.emitting = lvl >= 1 and alive
	_dmg_sparks.emitting = lvl >= 3 and alive
	# دخان أكثف مع الضرر + لون أغمق
	if lvl >= 1:
		_dmg_smoke.amount = 8 + lvl * 8
		var pm2: ParticleProcessMaterial = _dmg_smoke.process_material
		pm2.color = Color(0.3, 0.28, 0.26, 0.4) if lvl == 1 else (Color(0.2, 0.19, 0.18, 0.6) if lvl == 2 else Color(0.1, 0.09, 0.09, 0.75))
	# جسم السيارة يغمق مع الضرر (احتراق)
	if _body_mat != null:
		_body_mat.albedo_color = body_color.darkened(lvl * 0.16)


# 🎬 غبار من العجلات (يعطي إحساس بالوزن والسرعة)
func _build_wheel_dust() -> void:
	_wheel_dust = GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.9, 0.05, 0.3)
	pm.direction = Vector3(0, 0.4, 1)
	pm.spread = 35.0
	pm.initial_velocity_min = 1.5
	pm.initial_velocity_max = 4.0
	pm.gravity = Vector3(0, 1.2, 0)
	pm.scale_min = 0.25
	pm.scale_max = 0.7
	pm.damping_min = 2.0
	pm.damping_max = 4.0
	pm.color = Color(0.62, 0.56, 0.45, 0.35)
	_wheel_dust.process_material = pm
	var sm := SphereMesh.new()
	sm.radius = 0.3
	sm.height = 0.6
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.albedo_color = Color(0.6, 0.55, 0.44, 0.3)
	sm.material = smat
	_wheel_dust.draw_pass_1 = sm
	_wheel_dust.amount = 24
	_wheel_dust.lifetime = 0.9
	_wheel_dust.emitting = false
	_wheel_dust.position = Vector3(0.0, -0.25, 1.3)
	add_child(_wheel_dust)


func _update_wheel_dust() -> void:
	if _wheel_dust == null or not is_instance_valid(_wheel_dust):
		return
	var spd := linear_velocity.length()
	# غبار لما تسرع أو تدرفت
	_wheel_dust.emitting = _grounded and alive and (spd > 8.0 or _drifting)
	if _wheel_dust.emitting:
		var pm2: ParticleProcessMaterial = _wheel_dust.process_material
		pm2.initial_velocity_max = 2.5 + spd * 0.15
		_wheel_dust.amount = 16 if not _drifting else 34


func _build_hp_bar() -> void:
	# خلفية سوداء
	_hp_bar = Sprite3D.new()
	var bg := ImageTexture.create_from_image(Image.create(64, 8, false, Image.FORMAT_RGBA8))
	var img := Image.create(64, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.05, 0.05, 0.07, 0.85))
	_hp_bar.texture = ImageTexture.create_from_image(img)
	_hp_bar.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hp_bar.no_depth_test = false
	_hp_bar.pixel_size = 0.022
	_hp_bar.position = Vector3(0.0, 1.75, 0.0)
	add_child(_hp_bar)

	# التعبئة (خضراء => حمراء)
	_hp_fill = Sprite3D.new()
	var img2 := Image.create(64, 8, false, Image.FORMAT_RGBA8)
	img2.fill(Color(1, 1, 1, 1))
	_hp_fill.texture = ImageTexture.create_from_image(img2)
	_hp_fill.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hp_fill.pixel_size = 0.022
	_hp_fill.position = Vector3(0.0, 1.75, 0.01)
	_hp_fill.modulate = Color(0.25, 0.9, 0.3)
	add_child(_hp_fill)


func _update_hp_bar() -> void:
	if _hp_fill == null or not is_instance_valid(_hp_fill):
		return
	var ratio := clampf(health / maxf(max_health, 1.0), 0.0, 1.0)
	# نضيّق العرض من اليسار (نصغّر السكيل ونزيح)
	_hp_fill.scale.x = maxf(ratio, 0.001)
	var full_w := 64.0 * 0.022
	_hp_fill.position.x = -(full_w * 0.5) * (1.0 - ratio)
	# اللون: أخضر => أصفر => أحمر
	var col := Color(0.9, 0.15, 0.1).lerp(Color(0.95, 0.8, 0.15), clampf(ratio * 2.0, 0.0, 1.0))
	if ratio > 0.5:
		col = Color(0.95, 0.8, 0.15).lerp(Color(0.25, 0.9, 0.3), (ratio - 0.5) * 2.0)
	_hp_fill.modulate = col
	var vis := alive and not critical
	_hp_bar.visible = vis
	_hp_fill.visible = vis


func _build_weapon_mounts() -> void:
	var gun_mat := StandardMaterial3D.new()
	gun_mat.albedo_color = Color(0.16, 0.17, 0.2)
	gun_mat.roughness = 0.45
	gun_mat.metallic = 0.85

	# --- سبطانة الرشاش (أمام) ---
	_mg_mount = Node3D.new()
	_mg_mount.position = Vector3(0.0, _wy_gun, 0.0)
	add_child(_mg_mount)
	var mg_house := MeshInstance3D.new()
	var hb := BoxMesh.new()
	hb.size = Vector3(0.18, 0.13, 0.3)
	hb.material = gun_mat
	mg_house.mesh = hb
	mg_house.position = Vector3(0.0, -0.02, -1.32)
	_mg_mount.add_child(mg_house)
	var mg_tube := MeshInstance3D.new()
	var tc := CylinderMesh.new()
	tc.top_radius = 0.045
	tc.bottom_radius = 0.045
	tc.height = 0.55
	tc.material = gun_mat
	mg_tube.mesh = tc
	mg_tube.rotation.x = PI / 2.0
	mg_tube.position = Vector3(0.0, 0.0, -1.62)
	_mg_mount.add_child(mg_tube)
	_mg_tip = Node3D.new()
	_mg_tip.position = Vector3(0.0, 0.0, -1.92)
	_mg_mount.add_child(_mg_tip)
	# جدحة النار (تظهر لحظة الإطلاق)
	_mg_flash = MeshInstance3D.new()
	var fs := SphereMesh.new()
	fs.radius = 0.1
	fs.height = 0.2
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(1.0, 0.75, 0.25)
	fmat.emission_enabled = true
	fmat.emission = Color(1.0, 0.6, 0.15)
	fmat.emission_energy_multiplier = 4.0
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fs.material = fmat
	_mg_flash.mesh = fs
	_mg_flash.scale = Vector3(1.0, 1.0, 1.7)
	_mg_flash.visible = false
	_mg_tip.add_child(_mg_flash)

	# --- القاذف (فوق السطح) ---
	_rk_mount = Node3D.new()
	_rk_mount.position = Vector3(0.0, _wy_rocket, 0.0)
	add_child(_rk_mount)
	var rk_base := MeshInstance3D.new()
	var rb := BoxMesh.new()
	rb.size = Vector3(0.34, 0.16, 0.55)
	rb.material = gun_mat
	rk_base.mesh = rb
	rk_base.position = Vector3(0.0, -0.1, -0.25)
	_rk_mount.add_child(rk_base)
	var rk_tube := MeshInstance3D.new()
	var rc := CylinderMesh.new()
	rc.top_radius = 0.09
	rc.bottom_radius = 0.1
	rc.height = 0.6
	rc.material = gun_mat
	rk_tube.mesh = rc
	rk_tube.rotation.x = PI / 2.0
	rk_tube.position = Vector3(0.0, 0.0, -0.55)
	_rk_mount.add_child(rk_tube)
	_rocket_tip = Node3D.new()
	_rocket_tip.position = Vector3(0.0, 0.0, -0.9)
	_rk_mount.add_child(_rocket_tip)

	# --- المتتبع (يمين السيارة) ---
	_hm_mount = Node3D.new()
	_hm_mount.position = Vector3(0.56, _wy_homing, 0.0)
	add_child(_hm_mount)
	var hm_base := MeshInstance3D.new()
	var hbb := BoxMesh.new()
	hbb.size = Vector3(0.15, 0.15, 0.5)
	hbb.material = gun_mat
	hm_base.mesh = hbb
	hm_base.position = Vector3(0.0, -0.02, -0.8)
	_hm_mount.add_child(hm_base)
	_homing_pod = MeshInstance3D.new()
	var hc := CylinderMesh.new()
	hc.top_radius = 0.055
	hc.bottom_radius = 0.055
	hc.height = 0.38
	hc.material = gun_mat
	_homing_pod.mesh = hc
	_homing_pod.rotation.x = PI / 2.0
	_homing_pod.position = Vector3(0.0, 0.0, -1.1)
	_hm_mount.add_child(_homing_pod)
	_homing_tip = Node3D.new()
	_homing_tip.position = Vector3(0.0, 0.0, -1.32)
	_hm_mount.add_child(_homing_tip)


# يضبط ارتفاعات الأسلحة من weapons.json (صعود/نزول فقط)
func set_weapon_heights(w: Dictionary) -> void:
	_wy_gun = float(w.get("gun", _wy_gun))
	_wy_rocket = float(w.get("rocket", _wy_rocket))
	_wy_homing = float(w.get("homing", _wy_homing))
	if _mg_mount != null and is_instance_valid(_mg_mount):
		_mg_mount.position.y = _wy_gun
	if _rk_mount != null and is_instance_valid(_rk_mount):
		_rk_mount.position.y = _wy_rocket
	if _hm_mount != null and is_instance_valid(_hm_mount):
		_hm_mount.position.y = _wy_homing


# وضع الهاون: السبطانة متحولة لفوق => يضرب أقرب عدو بالخريطة (يستهلك 3 صواريخ)
func _fire_mortar_nearest() -> void:
	if ammo["homing"] < 3:
		Fx.sound(global_position, "beep", -12.0, 0.6)
		_mortar_cd = 0.8
		return
	var nearest: Node3D = null
	var best := 99999.0
	for c in get_tree().get_nodes_in_group("cars"):
		if c == self or not c.get("alive"):
			continue
		var d: float = global_position.distance_to(c.global_position)
		if d < best:
			best = d
			nearest = c
	if nearest == null:
		return
	ammo["homing"] -= 3
	ammo_changed.emit()
	_mortar_cd = 2.4
	_homing_recoil = 1.0

	# 🎯 إطلاق حقيقي من السيارة: قوس عالي محسوب على بعد الهدف
	var start: Vector3 = (_homing_tip.global_position + Vector3.UP * 0.2) if (_homing_tip != null and is_instance_valid(_homing_tip)) else (global_position + Vector3.UP * 1.0)
	var g := 26.0
	var to0: Vector3 = nearest.global_position - start
	var d0 := Vector2(to0.x, to0.z).length()
	# أبعد هدف = زمن طيران أطول = قوس أعلى
	var flight_t := clampf(0.9 + d0 * 0.05, 1.2, 3.0)
	# نتوقع مكان الهدف بعد زمن الطيران
	var aim: Vector3 = nearest.global_position + nearest.linear_velocity * flight_t * 0.8
	var to: Vector3 = aim - start
	var hdist := Vector2(to.x, to.z).length()
	var hdir := Vector3(to.x, 0.0, to.z)
	hdir = hdir.normalized() if hdir.length() > 0.05 else -global_transform.basis.z

	var m := Projectile.new()
	m.owner_car = self
	m.ballistic = true
	m.direction = hdir
	m.speed = hdist / flight_t
	# معادلة القذيفة: يوصل ارتفاع الهدف بنهاية زمن الطيران
	m.vspeed = (aim.y + 0.4 - start.y + 0.5 * g * flight_t * flight_t) / flight_t
	m.damage = 60.0
	m.blast_radius = 6.0
	m.visual_scale = 1.5
	m.tint = Color(0.16, 0.16, 0.22)
	m.life = flight_t + 2.0
	get_parent().add_child(m)
	m.global_position = start

	# 💢 ارتداد الهاون على السيارة: دفعة للخلف + ضغطة للأسفل
	apply_central_impulse(-hdir * mass * 2.4 + Vector3.DOWN * mass * 1.0)
	Fx.sound(global_position, "rocket", 1.0, 0.7)
	Fx.vibrate(60)


func _fire_rocket(charge: int) -> void:
	charge = clampi(charge, 1, ammo["rocket"])
	if charge <= 0:
		return
	_rocket_cooldown = 0.5 + charge * 0.1
	_launch_projectile(false, charge)
	ammo["rocket"] -= charge
	ammo_changed.emit()


func _fire_homing() -> void:
	if ammo["homing"] <= 0:
		if not _homing_prev:
			Fx.sound(global_position, "beep", -12.0, 0.6)
		return
	_homing_cooldown = 0.6
	_homing_recoil = 1.0
	_launch_projectile(true)
	ammo["homing"] -= 1
	ammo_changed.emit()


func _launch_projectile(homing: bool, charge: int = 1) -> void:
	var p := Projectile.new()
	p.owner_car = self
	var dir := -global_transform.basis.z
	if homing:
		p.speed = 44.0                    # أسرع بكثير
		p.damage = 30.0
		p.blast_radius = 3.8
		p.turn_rate = 3.4                 # يلف أسرع (يلحق الأهداف)
		p.target = lock_target if (lock_target != null and is_instance_valid(lock_target)) else _find_target()
		p.is_homing = true
		p.no_proximity = true             # ما ينفجر بالتقارب - لازم يصطدم
		p.tint = Color(0.25, 0.55, 1.0)   # أزرق
	else:
		# القاذف: القوة حسب الشحن، الحجم ثابت، واللون يتدرج أصفر=>أسود
		p.speed = 42.0
		p.damage = 35.0 * charge
		p.blast_radius = 4.2 + (charge - 1) * 1.6
		p.visual_scale = 1.0
		p.tint = CHARGE_COLORS[clampi(charge - 1, 0, CHARGE_COLORS.size() - 1)]
	p.direction = dir
	get_parent().add_child(p)
	# 🧱 نتأكد القذيفة ما تنولد داخل جدار (لو ملاصقين، تنولد بمكان آمن)
	var safe: Vector3 = global_transform * Vector3(0.0, 0.6, -0.4)
	var tip: Vector3
	if homing:
		tip = _homing_tip.global_position if (_homing_tip != null and is_instance_valid(_homing_tip)) else global_transform * Vector3(0.56, 0.52, -1.3)
	else:
		tip = _rocket_tip.global_position if (_rocket_tip != null and is_instance_valid(_rocket_tip)) else global_transform * Vector3(0.0, 1.1, -0.9)
	var gq := PhysicsRayQueryParameters3D.create(safe, tip)
	gq.exclude = [get_rid()]
	var gh := get_world_3d().direct_space_state.intersect_ray(gq)
	p.global_position = (safe if not gh.is_empty() else tip)
	Fx.sound(global_position, "rocket", 0.0 + charge, clampf(1.0 - (charge - 1) * 0.1, 0.6, 1.0))


func _find_target() -> Node3D:
	# 🎯 أقرب عدو بأي اتجاه (360°) ومهما بعد - حتى لو وراك
	var best: Node3D = null
	var best_d := 1e9
	for c in get_tree().get_nodes_in_group("cars"):
		if c == self or not c.alive:
			continue
		var to: Vector3 = c.global_position - global_position
		var d := to.length()
		if d < 0.1:
			continue
		if d < best_d:
			best_d = d
			best = c
	return best


func _plant_single_mine() -> void:
	if ammo["mine"] <= 0:
		Fx.sound(global_position, "beep", -12.0, 0.6)
		return
	ammo["mine"] -= 1
	_spawn_mine(1.0, 30.0, 4.2, 12.0, 1.0)
	Fx.sound(global_position, "beep", -6.0, 0.75)
	ammo_changed.emit()


# 💥 تفجير الألغام البريموت (كلها) عن بعد
func detonate_remote_mines() -> void:
	var mines := get_tree().get_nodes_in_group("remote_mines")
	var mine_count := 0
	for m in mines:
		if not is_instance_valid(m):
			continue
		if m.owner_car != self:
			continue
		m.remote_detonate()
		mine_count += 1
	if mine_count == 0:
		Fx.sound(global_position, "beep", -14.0, 0.7)


# عدد ألغامي المزروعة (للواجهة)
func my_remote_mines() -> Array:
	var out: Array = []
	for m in get_tree().get_nodes_in_group("remote_mines"):
		if is_instance_valid(m) and m.owner_car == self:
			out.append(m)
	return out


func _plant_mega_mine(count: int) -> void:
	# عبوة مجمعة: قوتها حسب عدد العبوات المشحونة
	count = clampi(count, 2, ammo["mine"])
	if count < 2:
		return
	ammo["mine"] -= count
	_spawn_mine(1.6 + minf(count, 8) * 0.16, 30.0 + count * 18.0, 4.2 + count * 1.3, 12.0 + count * 3.0, 1.6 + count * 0.35)
	Fx.sound(global_position, "beep", 0.0, 0.4)
	ammo_changed.emit()


func _spawn_mine(size_mult: float, dmg: float, radius: float, launch: float, quake: float) -> void:
	var m := Mine.new()
	m.owner_car = self
	m.size_mult = size_mult
	m.damage = dmg
	m.blast_radius = radius
	m.launch_dv = launch
	m.quake_strength = quake
	get_parent().add_child(m)
	m.global_position = global_transform * Vector3(0.0, -0.4, 2.0 + size_mult * 0.5)
	m.global_position.y = maxf(m.global_position.y, 0.05)


# ============================================================
#  الدم والموت والإحياء
# ============================================================

func take_damage(amount: float, attacker: Node = null) -> void:
	if not alive or critical:
		return
	# الدرع يمتص الضرر بالكامل وهو فعّال
	if shield_time > 0.0:
		Fx.sound(global_position, "hit", -4.0, 1.8)
		return
	health = maxf(health - amount, 0.0)
	_flash_timer = 0.12
	health_changed.emit(health, max_health)
	if health <= 0.0:
		_enter_critical(attacker)


func _enter_critical(attacker: Node) -> void:
	_free_charge_orb()
	_rocket_charge = 0
	critical = true
	critical_left = critical_time
	_last_attacker = attacker
	critical_started.emit(critical_left)
	# دخان كثيف ونار
	_damage_smoke.emitting = true
	# رقم عدّاد عائم فوق السيارة (يبين لكل السيارات)
	if _crit_label == null:
		_crit_label = Label3D.new()
		_crit_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_crit_label.font_size = 120
		_crit_label.outline_size = 20
		_crit_label.modulate = Color(1.0, 0.2, 0.1)
		_crit_label.position.y = 1.8
		_crit_label.no_depth_test = true
		add_child(_crit_label)
	_crit_label.visible = true
	if _alarm_snd != null:
		_alarm_snd.play()
	Fx.sound(global_position, "beep", 0.0, 1.0)


func add_shield(seconds: float) -> void:
	shield_time = maxf(shield_time, seconds)
	shield_changed.emit(true, shield_time)


func repair(fraction: float) -> void:
	# تصليح بنسبة من الصحة القصوى
	health = minf(health + max_health * fraction, max_health)
	health_changed.emit(health, max_health)
	Fx.sound(global_position, "pickup", 0.0, 1.4)


func _die(attacker: Node) -> void:
	alive = false
	critical = false
	critical_ended.emit()
	died.emit(attacker)
	if _crit_label != null:
		_crit_label.visible = false
	# 💥 انفجار الموت: القتلات منه تُحسب لهذي السيارة (الانتحاري) مو لقاتلها
	Fx.explosion(global_position, critical_blast_damage, critical_blast_radius, critical_launch, self, 1.8)
	visible = false
	freeze = true
	collision_layer = 0
	collision_mask = 0
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_drift_smoke_l.emitting = false
	_drift_smoke_r.emitting = false
	_damage_smoke.emitting = false
	_boost_flame_l.emitting = false
	_boost_flame_r.emitting = false
	_body_mat.emission_enabled = false
	if _engine_snd != null:
		_engine_snd.stop()
	if _drift_snd != null:
		_drift_snd.stop()
	if _boost_snd != null:
		_boost_snd.stop()
	if _alarm_snd != null:
		_alarm_snd.stop()
	await get_tree().create_timer(respawn_delay).timeout
	_respawn()


func _respawn() -> void:
	global_transform = _spawn_transform
	health = max_health
	health_changed.emit(health, max_health)
	visible = true
	collision_layer = 1
	collision_mask = 1
	freeze = false
	alive = true
	critical = false
	critical_left = 0.0
	_detonate_prev = false
	_flip_timer = 0.0
	_boost = boost_max
	boost_changed.emit(_boost, boost_max)
	if _engine_snd != null:
		_engine_snd.play()
	respawned.emit()


func _on_body_entered(body: Node) -> void:
	if not alive:
		return
	# نحسب مدى الاصطدام "المواجه" باستخدام عمودي السطح من حالة الفيزياء
	var state := PhysicsServer3D.body_get_direct_state(get_rid())
	var impact := 0.0
	var contact := global_position - global_transform.basis.z * 1.2
	if state != null:
		for i in state.get_contact_count():
			if state.get_contact_collider(i) != body.get_rid():
				continue
			var normal: Vector3 = state.get_contact_local_normal(i)
			# مقدار السرعة المعاكسة للسطح = شدة الصدمة الحقيقية
			var closing := -linear_velocity.dot(normal)
			if closing > impact:
				impact = closing
				contact = state.get_contact_local_position(i)
	else:
		# احتياط: لو ما توفرت حالة التلامس
		var hv := linear_velocity
		hv.y = 0.0
		impact = hv.length()

	# 💥 مداعمات نيد فور سبيد: دفع قوي + برمة سينمائية + ضرر متبادل
	if body is ArcadeCar:
		if impact >= 4.0 and _ram_cd <= 0.0:
			_ram_cd = 0.35
			var push: Vector3 = body.global_position - global_position
			push.y = 0.0
			push = push.normalized() if push.length() > 0.01 else -global_transform.basis.z
			var power := clampf(impact * 13.0, 50.0, 300.0)
			if _boosting:
				power *= 1.5
			body.apply_central_impulse(push * power + Vector3.UP * power * 0.22)
			body.apply_torque_impulse(Vector3(randf_range(-0.8, 0.8), randf_range(-0.5, 0.5), randf_range(-0.8, 0.8)) * power * 0.6)
			apply_central_impulse(-push * power * 0.3)
			var dmg := clampf(impact * 1.8, 5.0, 34.0)
			if _boosting:
				dmg += boost_ram_damage
			body.take_damage(dmg, self)
			take_damage(clampf(impact * 0.5, 2.0, 12.0), body)
			_spawn_impact(contact)
			Fx.sound(contact, "hit", 2.0, 0.55)
			Fx.vibrate(45)
	elif body is Destructible:
		# البرميل ينفجر بالاصطدام؛ باقي الأجسام تنكسر لو الصدمة قوية
		var hv := linear_velocity
		hv.y = 0.0
		var v := hv.length()
		if body.kind == Destructible.Kind.BARREL and v >= 5.0:
			body.take_damage(100.0, self)         # يفجّره فوراً
		elif v >= 12.0:
			body.take_damage((v - 8.0) * 3.0, self)

	# ضرر على نفسك فقط من الصدمات المواجهة القوية (جدار/سيارة)
	# الصعود على منحدر أو ملامسة الأرض عموديها للأعلى => closing صغير => لا ضرر
	# البراميل ما تضررك بالاصطدام (تنفجر بس، وانفجارها يضررك لو قريب)
	var self_threshold := 16.0
	var is_barrel: bool = body is Destructible and body.kind == Destructible.Kind.BARREL
	if impact > self_threshold and not is_barrel:
		take_damage((impact - self_threshold) * (0.7 if _boosting else 1.1), self)
		if not (body is ArcadeCar):
			_spawn_impact(contact)


func _spawn_impact(pos: Vector3) -> void:
	var p := _make_particles(Vector3.ZERO, Color(1.0, 0.95, 0.6), 14, 0.3, 3.0, 9.0, 0.08)
	remove_child(p)
	get_parent().add_child(p)
	p.global_position = pos
	var pm: ParticleProcessMaterial = p.process_material
	pm.spread = 180.0
	pm.gravity = Vector3(0.0, -6.0, 0.0)
	p.one_shot = true
	p.explosiveness = 1.0
	p.emitting = true
	await get_tree().create_timer(0.5).timeout
	p.queue_free()


# ============================================================
#  التفحيط
# ============================================================

func _track_drift(delta: float) -> void:
	var active := _drifting and _grounded and linear_velocity.length() > 6.0
	if active:
		_drift_time += delta
	else:
		if _drift_time > 1.2:
			drifted.emit(_drift_time)
		_drift_time = 0.0


# ============================================================
#  المؤثرات البصرية والصوتية
# ============================================================

func _update_visuals(delta: float) -> void:
	var fwd_speed := -global_transform.basis.z.dot(linear_velocity)
	var blend := clampf(delta * 20.0, 0.0, 1.0)
	for i in 4:
		var pivot: Node3D = _steer_pivots[i]
		var anchor: Vector3 = wheel_anchors[i]
		var target_y: float = anchor.y - (_wheel_dist[i] - wheel_radius)
		if freeze:
			# سيارة معاينة (مجمّدة): وضعية "واقفة" بدل تعليق مرخي بالكامل
			target_y = anchor.y - suspension_rest * 0.2
		pivot.position.y = lerpf(pivot.position.y, target_y, blend)
		if i < 2:
			pivot.rotation.y = -_steer_smooth * 0.45
		var spin: Node3D = _spin_nodes[i]
		spin.rotate_x(-fwd_speed / maxf(wheel_radius, 0.05) * delta)

	# الشاصي ملتصق بالعجلات دائماً
	_update_undercarriage()
	_update_hp_bar()
	lock_target = _find_target()   # أقرب عدو بأي اتجاه
	_update_damage_fx()
	_update_wheel_dust()
	# إطفاء جدحة الرشاش
	if _mg_flash_t > 0.0:
		_mg_flash_t -= delta
		if _mg_flash_t <= 0.0 and _mg_flash != null and is_instance_valid(_mg_flash):
			_mg_flash.visible = false
	# حركة سلاح المتتبع: تحول لفوق (هاون) + ارتداد + اهتزاز
	if _homing_pod != null and is_instance_valid(_homing_pod):
		_homing_recoil = maxf(_homing_recoil - delta * 5.0, 0.0)
		_homing_pod.position.z = -1.1 + _homing_recoil * 0.2
		var tilt_target := 1.0 if _homing_mode_up else 0.0
		_homing_tilt = move_toward(_homing_tilt, tilt_target, delta * 3.5)
		_homing_pod.rotation.x = (PI / 2.0) * (1.0 - _homing_tilt)
		if _homing_in and not _homing_mode_up:
			_homing_pod.rotation.y = sin(Time.get_ticks_msec() * 0.025) * 0.1
		else:
			_homing_pod.rotation.y = lerpf(_homing_pod.rotation.y, 0.0, blend)

	# 🎬 إحساس الوزن: البدن يميل مع القوى (زي السيارات الحقيقية)
	var spd_v := linear_velocity.length()
	var lat_g := angular_velocity.y * clampf(spd_v / 12.0, 0.0, 1.0)      # قوة جانبية
	var lon_g := fwd_speed - _prev_speed                                    # تسارع/كبح
	_prev_speed = fwd_speed

	# ميلان جانبي (body roll) - البدن يميل عكس المنعطف
	var roll_t: float = clampf(lat_g * 0.055, -0.09, 0.09)
	_body_roll = lerpf(_body_roll, roll_t, clampf(delta * 6.0, 0.0, 1.0))

	# انحناء أمامي/خلفي (squat & dive) - يغطس بالكبح، يرتفع بالتسارع
	var pitch_t: float = clampf(-lon_g * 0.6, -0.06, 0.06)
	_body_pitch = lerpf(_body_pitch, pitch_t, clampf(delta * 7.0, 0.0, 1.0))

	_visual_root.rotation.z = _body_roll
	_visual_root.rotation.x = _body_pitch
	_muzzle.light_energy = lerpf(_muzzle.light_energy, 0.0, clampf(delta * 18.0, 0.0, 1.0))

	# وميض الإصابة (يُتجاهل بالحالة الحرجة لأن لها وميضها الخاص)
	if not critical:
		if _flash_timer > 0.0:
			_flash_timer -= delta
			_body_mat.emission_enabled = true
		else:
			_body_mat.emission_enabled = false

	# ضوء البريك الخلفي
	_tail_mat.emission_energy_multiplier = 2.4 if _braking else 0.35

	var drift_active := _drifting and _grounded and linear_velocity.length() > 6.0
	_drift_smoke_l.emitting = drift_active
	_drift_smoke_r.emitting = drift_active
	_damage_smoke.emitting = health < 40.0


func _update_shield(delta: float) -> void:
	if shield_time > 0.0:
		shield_time = maxf(shield_time - delta, 0.0)
		_shield_mesh.visible = true
		# نبض + وميض قرب النهاية
		var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.008) * 0.05
		_shield_mesh.scale = Vector3(pulse, pulse, pulse)
		var a := 0.22
		if shield_time < 1.5:
			a = 0.22 * (0.4 + 0.6 * (sin(Time.get_ticks_msec() * 0.02) * 0.5 + 0.5))
		_shield_mat.albedo_color.a = a
		if shield_time <= 0.0:
			shield_changed.emit(false, 0.0)
	else:
		if _shield_mesh.visible:
			_shield_mesh.visible = false


func _update_sounds(delta: float) -> void:
	if _engine_snd == null:
		return
	# 🚗 محاكاة RPM حقيقية مع علبة تروس (6 سرعات)
	var spd := linear_velocity.length()
	var ratio := clampf(spd / max_speed, 0.0, 1.0)

	# تحديد الترس الحالي (كل ترس له مدى سرعة)
	var gear := 0
	var gear_ratios := [0.18, 0.34, 0.50, 0.67, 0.83, 1.0]
	for g in gear_ratios.size():
		if ratio <= gear_ratios[g]:
			gear = g
			break
		gear = gear_ratios.size() - 1

	# RPM داخل الترس: يصعد من 0 لـ1 ثم يرجع ينزل عند التبديل (صوت واقعي!)
	var g_lo: float = 0.0 if gear == 0 else gear_ratios[gear - 1]
	var g_hi: float = gear_ratios[gear]
	var rpm := clampf(inverse_lerp(g_lo, g_hi, ratio), 0.0, 1.0)

	# الحمل: دعس البنزين يرفع الصوت والنغمة
	var load := absf(_throttle)
	if _boosting:
		load = 1.3

	# نغمة المحرك: RPM + دفعة الحمل + ارتفاع بسيط مع الترس
	var target_pitch: float = 0.7 + rpm * 0.5 + gear * 0.04 + load * 0.08
	# تنعيم (ما تقفز فجأة)
	_engine_pitch = lerpf(_engine_pitch, target_pitch, clampf(delta * 9.0, 0.0, 1.0))
	_engine_snd.pitch_scale = _engine_pitch

	if not input_enabled:
		_engine_snd.volume_db = -26.0
		_engine_snd.pitch_scale = 0.6
	elif ai_controlled:
		_engine_snd.volume_db = -30.0 + ratio * 6.0 + load * 2.0
	else:
		_engine_snd.volume_db = -22.0 + ratio * 6.0 + load * 3.0

	var drift_active := _drifting and _grounded and linear_velocity.length() > 6.0
	if drift_active and not _drift_snd.playing:
		_drift_snd.play()
	elif not drift_active and _drift_snd.playing:
		_drift_snd.stop()
	_drift_snd.pitch_scale = 0.9 + ratio * 0.35


func _check_recovery(delta: float) -> void:
	_ram_cd -= delta
	var upright := global_transform.basis.y.dot(Vector3.UP)
	if upright < 0.2 and linear_velocity.length() < 2.5:
		_flip_timer += delta
		if _flip_timer > 2.5:
			_recover()
	else:
		_flip_timer = 0.0
	if global_position.y < -15.0:
		global_transform = _spawn_transform
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		# لو كانت بالحالة الحرجة وطاحت من الخريطة => نلغي المؤقت (بداية نظيفة)
		if critical:
			_clear_critical()
			health = max_health
			health_changed.emit(health, max_health)


func _clear_critical() -> void:
	critical = false
	critical_left = 0.0
	_detonate_prev = false
	_damage_smoke.emitting = false
	_body_mat.emission_enabled = false
	if _crit_label != null:
		_crit_label.visible = false
	if _alarm_snd != null:
		_alarm_snd.stop()
	critical_ended.emit()


func _recover() -> void:
	_flip_timer = 0.0
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.05:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	var pos := global_position + Vector3.UP * 1.5
	look_at_from_position(pos, pos + fwd, Vector3.UP)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	var seg := to - from
	var seg_len := seg.length()
	if seg_len < 0.5:
		return
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.05, 0.05, seg_len)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.85, 0.3)
	box.material = mat
	m.mesh = box
	get_parent().add_child(m)
	var up_ref := Vector3.UP if absf(seg.normalized().y) < 0.95 else Vector3.RIGHT
	m.look_at_from_position(from + seg * 0.5, to, up_ref)
	await get_tree().create_timer(0.05).timeout
	m.queue_free()


func _spawn_spark(pos: Vector3) -> void:
	var p := _make_particles(Vector3.ZERO, Color(1.0, 0.9, 0.4), 10, 0.35, 3.0, 7.0, 0.06)
	remove_child(p)
	get_parent().add_child(p)
	p.global_position = pos
	var pm: ParticleProcessMaterial = p.process_material
	pm.spread = 180.0
	pm.gravity = Vector3(0.0, -9.0, 0.0)
	p.one_shot = true
	p.explosiveness = 1.0
	p.emitting = true
	await get_tree().create_timer(0.6).timeout
	p.queue_free()


func _make_particles(pos: Vector3, color: Color, amount: int, life: float, vel_min: float, vel_max: float, size: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0.0, 1.0, 0.0)
	mat.spread = 25.0
	mat.initial_velocity_min = vel_min
	mat.initial_velocity_max = vel_max
	mat.gravity = Vector3(0.0, 0.6, 0.0)
	mat.scale_min = 0.6
	mat.scale_max = 1.4
	mat.color = color
	p.process_material = mat
	var mesh := SphereMesh.new()
	mesh.radius = size
	mesh.height = size * 2.0
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.albedo_color = color
	mesh.material = mm
	p.draw_pass_1 = mesh
	p.amount = amount
	p.lifetime = life
	p.emitting = false
	p.position = pos
	add_child(p)
	return p


# ============================================================
#  بناء الشكل بالكود
# ============================================================

func _build_body() -> void:
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.5, 1.1, 2.4)   # أعرض وأعلى ليغطي كامل السيارة (بما فيها الكابينة)
	col.shape = shape
	col.position.y = 0.35                  # نرفعه ليغطي من الأرض للسقف
	add_child(col)

	_visual_root = Node3D.new()
	add_child(_visual_root)

	# الهيكل السفلي العريض (chassis)
	var chassis := MeshInstance3D.new()
	var chm := BoxMesh.new()
	chm.size = Vector3(1.35, 0.28, 2.25)
	var chassis_mat := _mat(Color(0.11, 0.11, 0.13))
	chassis_mat.metallic = 0.5
	chassis_mat.roughness = 0.4
	chm.material = chassis_mat
	chassis.mesh = chm
	chassis.position = Vector3(0.0, -0.12, 0.0)
	_visual_root.add_child(chassis)

	# جسم رئيسي ملوّن أعرض بالوسط ومدبب للأمام والخلف
	_body_mat = _mat(body_color)
	_body_mat.emission = Color(1.0, 0.35, 0.25)
	_body_mat.metallic = 0.35
	_body_mat.roughness = 0.35

	var mid := MeshInstance3D.new()
	var midm := BoxMesh.new()
	midm.size = Vector3(1.28, 0.34, 1.5)
	midm.material = _body_mat
	mid.mesh = midm
	mid.position = Vector3(0.0, 0.12, 0.0)
	_visual_root.add_child(mid)

	# مقدمة مدببة (prism) - الرأس للأمام
	var front := MeshInstance3D.new()
	var frontm := PrismMesh.new()
	frontm.size = Vector3(1.28, 0.85, 0.34)   # X=عرض، Y=طول المثلث، Z=سماكة
	frontm.material = _body_mat
	front.mesh = frontm
	front.rotation.x = -PI / 2.0               # ننيّم المثلث حتى رأسه للأمام (-Z)
	front.position = Vector3(0.0, 0.12, -1.15)
	_visual_root.add_child(front)

	# غطاء المحرك المنحدر
	var hood := MeshInstance3D.new()
	var hoodm := BoxMesh.new()
	hoodm.size = Vector3(1.1, 0.12, 0.7)
	hoodm.material = _body_mat
	hood.mesh = hoodm
	hood.position = Vector3(0.0, 0.28, -0.55)
	hood.rotation.x = -0.12
	_visual_root.add_child(hood)

	# الكابينة المنحدرة (windshield + roof)
	var glass_mat := _mat(Color(0.15, 0.22, 0.3))
	glass_mat.metallic = 0.7
	glass_mat.roughness = 0.08

	var windshield := MeshInstance3D.new()
	var wsm := BoxMesh.new()
	wsm.size = Vector3(0.95, 0.4, 0.5)
	wsm.material = glass_mat
	windshield.mesh = wsm
	windshield.position = Vector3(0.0, 0.42, -0.15)
	windshield.rotation.x = 0.42
	_visual_root.add_child(windshield)

	var roof := MeshInstance3D.new()
	var roofm := BoxMesh.new()
	roofm.size = Vector3(0.92, 0.32, 0.75)
	var roof_mat := _mat(body_color.darkened(0.15))
	roof_mat.metallic = 0.35
	roofm.material = roof_mat
	roof.mesh = roofm
	roof.position = Vector3(0.0, 0.5, 0.3)
	_visual_root.add_child(roof)

	# قوس حماية (roll bar) خلف الكابينة
	var bar_mat := _mat(Color(0.2, 0.2, 0.23))
	bar_mat.metallic = 0.8
	bar_mat.roughness = 0.3
	var rollbar := MeshInstance3D.new()
	var rbm := CylinderMesh.new()
	rbm.top_radius = 0.05
	rbm.bottom_radius = 0.05
	rbm.height = 0.9
	rbm.material = bar_mat
	rollbar.mesh = rbm
	rollbar.rotation.z = PI / 2.0
	rollbar.position = Vector3(0.0, 0.6, 0.62)
	_visual_root.add_child(rollbar)

	# تنانير جانبية (side skirts)
	var skirt_mat := _mat(Color(0.09, 0.09, 0.11))
	for sx in [-0.68, 0.68]:
		var skirt := MeshInstance3D.new()
		var skm := BoxMesh.new()
		skm.size = Vector3(0.08, 0.16, 1.7)
		skm.material = skirt_mat
		skirt.mesh = skm
		skirt.position = Vector3(sx, -0.05, 0.0)
		_visual_root.add_child(skirt)

	# أقواس العجلات (fenders)
	var fender_mat := _mat(body_color.darkened(0.25))
	for zpos in [-0.85, 0.85]:
		for sx in [-0.7, 0.7]:
			var fender := MeshInstance3D.new()
			var fm := BoxMesh.new()
			fm.size = Vector3(0.12, 0.2, 0.7)
			fm.material = fender_mat
			fender.mesh = fm
			fender.position = Vector3(sx, 0.05, zpos)
			_visual_root.add_child(fender)

	# رشاش فوق الكابينة
	var gun_mat := _mat(Color(0.15, 0.16, 0.2))
	gun_mat.metallic = 0.7
	gun_mat.roughness = 0.3
	var gun_base := MeshInstance3D.new()
	var gbm := BoxMesh.new()
	gbm.size = Vector3(0.2, 0.12, 0.2)
	gbm.material = gun_mat
	gun_base.mesh = gbm
	gun_base.position = Vector3(0.0, 0.68, -0.1)
	_visual_root.add_child(gun_base)

	var gun := MeshInstance3D.new()
	var gm := CylinderMesh.new()
	gm.top_radius = 0.05
	gm.bottom_radius = 0.06
	gm.height = 0.85
	gm.material = gun_mat
	gun.mesh = gm
	gun.rotation.x = PI / 2.0
	gun.position = Vector3(0.0, 0.68, -0.6)
	_visual_root.add_child(gun)

	# صادم أمامي معدني
	var bumper := MeshInstance3D.new()
	var bump := BoxMesh.new()
	bump.size = Vector3(1.3, 0.16, 0.2)
	bump.material = bar_mat
	bumper.mesh = bump
	bumper.position = Vector3(0.0, -0.05, -1.28)
	_visual_root.add_child(bumper)

	# قضبان الصادم
	for sx in [-0.4, 0.4]:
		var guard := MeshInstance3D.new()
		var gdm := BoxMesh.new()
		gdm.size = Vector3(0.08, 0.35, 0.1)
		gdm.material = bar_mat
		guard.mesh = gdm
		guard.position = Vector3(sx, 0.05, -1.3)
		_visual_root.add_child(guard)

	# جناح خلفي (سبويلر) على حاملين
	var wing_mat := _mat(Color(0.13, 0.14, 0.17))
	wing_mat.metallic = 0.4
	for sx in [-0.45, 0.45]:
		var post := MeshInstance3D.new()
		var pmesh := BoxMesh.new()
		pmesh.size = Vector3(0.07, 0.28, 0.08)
		pmesh.material = wing_mat
		post.mesh = pmesh
		post.position = Vector3(sx, 0.42, 1.02)
		_visual_root.add_child(post)
	var wing := MeshInstance3D.new()
	var wmesh := BoxMesh.new()
	wmesh.size = Vector3(1.3, 0.06, 0.35)
	wmesh.material = wing_mat
	wing.mesh = wmesh
	wing.position = Vector3(0.0, 0.57, 1.04)
	wing.rotation.x = -0.15
	_visual_root.add_child(wing)

	# عوادم مزدوجة
	var ex_mat := _mat(Color(0.4, 0.41, 0.45))
	ex_mat.metallic = 0.9
	ex_mat.roughness = 0.2
	for sx in [-0.4, -0.25, 0.25, 0.4]:
		var ex := MeshInstance3D.new()
		var emesh := CylinderMesh.new()
		emesh.top_radius = 0.05
		emesh.bottom_radius = 0.05
		emesh.height = 0.25
		emesh.material = ex_mat
		ex.mesh = emesh
		ex.rotation.x = PI / 2.0
		ex.position = Vector3(sx, -0.08, 1.18)
		_visual_root.add_child(ex)

	# مصابيح أمامية مضيئة
	_head_mat = _mat(Color(1.0, 0.95, 0.7))
	_head_mat.emission_enabled = true
	_head_mat.emission = Color(1.0, 0.9, 0.55)
	_head_mat.emission_energy_multiplier = 1.6
	for sx in [-0.45, 0.45]:
		var hl := MeshInstance3D.new()
		var hmesh := BoxMesh.new()
		hmesh.size = Vector3(0.24, 0.12, 0.05)
		hmesh.material = _head_mat
		hl.mesh = hmesh
		hl.position = Vector3(sx, 0.12, -1.36)
		_visual_root.add_child(hl)

	# كشاف واحد مركزي (بدل اثنين) - أخف على الموبايل، مطفي بالنهار
	var spot := SpotLight3D.new()
	spot.position = Vector3(0.0, 0.15, -1.4)
	spot.rotation_degrees = Vector3(-8.0, 0.0, 0.0)   # الكشاف يضوي على -Z محلياً = مقدمة السيارة
	spot.light_color = Color(1.0, 0.95, 0.8)
	spot.light_energy = 0.0                              # مطفي افتراضياً
	spot.spot_range = 22.0
	spot.spot_angle = 38.0
	spot.spot_attenuation = 1.2
	spot.shadow_enabled = false
	_visual_root.add_child(spot)
	_headlights.append(spot)

	# مصابيح خلفية (تشتد مع البريك)
	_tail_mat = _mat(Color(0.9, 0.1, 0.08))
	_tail_mat.emission_enabled = true
	_tail_mat.emission = Color(1.0, 0.12, 0.06)
	_tail_mat.emission_energy_multiplier = 0.35
	for sx in [-0.48, 0.48]:
		var tl := MeshInstance3D.new()
		var tmesh := BoxMesh.new()
		tmesh.size = Vector3(0.2, 0.1, 0.05)
		tmesh.material = _tail_mat
		tl.mesh = tmesh
		tl.position = Vector3(sx, 0.14, 1.2)
		_visual_root.add_child(tl)


func _build_wheels() -> void:
	var rim_mat := _mat(Color(0.75, 0.76, 0.8))
	rim_mat.metallic = 0.9
	rim_mat.roughness = 0.25
	for i in 4:
		var anchor: Vector3 = wheel_anchors[i]
		var steer_pivot := Node3D.new()
		steer_pivot.position = anchor
		add_child(steer_pivot)

		var spin := Node3D.new()
		steer_pivot.add_child(spin)

		var tire := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = wheel_radius
		cyl.bottom_radius = wheel_radius
		cyl.height = 0.24
		cyl.material = _mat(Color(0.08, 0.08, 0.09))
		tire.mesh = cyl
		tire.rotation.z = PI / 2.0
		spin.add_child(tire)

		var rim := MeshInstance3D.new()
		var rmesh := CylinderMesh.new()
		rmesh.top_radius = wheel_radius * 0.55
		rmesh.bottom_radius = wheel_radius * 0.55
		rmesh.height = 0.26
		rmesh.material = rim_mat
		rim.mesh = rmesh
		rim.rotation.z = PI / 2.0
		spin.add_child(rim)

		_steer_pivots.append(steer_pivot)
		_spin_nodes.append(spin)


func _build_effects() -> void:
	_muzzle = OmniLight3D.new()
	_muzzle.position = Vector3(0.0, 0.3, -1.4)
	_muzzle.light_color = Color(1.0, 0.8, 0.3)
	_muzzle.light_energy = 0.0
	_muzzle.omni_range = 5.0
	add_child(_muzzle)

	_drift_smoke_l = _make_particles(Vector3(-0.62, -0.35, 0.9), Color(0.85, 0.85, 0.85, 0.55), 26, 0.7, 0.8, 2.0, 0.14)
	_drift_smoke_r = _make_particles(Vector3(0.62, -0.35, 0.9), Color(0.85, 0.85, 0.85, 0.55), 26, 0.7, 0.8, 2.0, 0.14)
	_damage_smoke = _make_particles(Vector3(0.0, 0.4, 0.5), Color(0.15, 0.15, 0.15, 0.7), 20, 1.1, 1.0, 2.2, 0.16)

	# لهب النيترو الأزرق من العوادم
	_boost_flame_l = _make_flame(Vector3(-0.35, -0.1, 1.2))
	_boost_flame_r = _make_flame(Vector3(0.35, -0.1, 1.2))

	# فقاعة الدرع (مخفية حتى تتفعّل)
	_shield_mesh = MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 1.5
	sph.height = 3.0
	_shield_mat = StandardMaterial3D.new()
	_shield_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shield_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shield_mat.albedo_color = Color(0.3, 0.7, 1.0, 0.22)
	_shield_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	sph.material = _shield_mat
	_shield_mesh.mesh = sph
	_shield_mesh.visible = false
	add_child(_shield_mesh)


func _make_flame(pos: Vector3) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0.0, 0.0, 1.0)
	mat.spread = 12.0
	mat.initial_velocity_min = 8.0
	mat.initial_velocity_max = 12.0
	mat.gravity = Vector3.ZERO
	mat.scale_min = 0.5
	mat.scale_max = 1.2
	mat.color = Color(0.4, 0.65, 1.0, 0.85)
	p.process_material = mat
	var mesh := SphereMesh.new()
	mesh.radius = 0.13
	mesh.height = 0.26
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.albedo_color = Color(0.45, 0.7, 1.0, 0.85)
	mesh.material = mm
	p.draw_pass_1 = mesh
	p.amount = 30
	p.lifetime = 0.35
	p.local_coords = false
	p.emitting = false
	p.position = pos
	add_child(p)
	return p


func _build_sounds() -> void:
	if not sounds_enabled:
		return
	var engine_stream: AudioStreamWAV = load("res://assets/sfx/engine_loop.wav")
	engine_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	engine_stream.loop_begin = 0
	engine_stream.loop_end = engine_stream.data.size() / 2
	_engine_snd = AudioStreamPlayer3D.new()
	_engine_snd.stream = engine_stream
	_engine_snd.volume_db = -15.0
	_engine_snd.max_distance = 60.0
	add_child(_engine_snd)
	_engine_snd.play()

	var drift_stream: AudioStreamWAV = load("res://assets/sfx/drift_loop.wav")
	drift_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	drift_stream.loop_begin = 0
	drift_stream.loop_end = drift_stream.data.size() / 2
	_drift_snd = AudioStreamPlayer3D.new()
	_drift_snd.stream = drift_stream
	_drift_snd.volume_db = -9.0
	_drift_snd.max_distance = 50.0
	add_child(_drift_snd)

	_gun_snd = AudioStreamPlayer3D.new()
	_gun_snd.stream = load("res://assets/sfx/shot.wav")
	_gun_snd.volume_db = -6.0
	_gun_snd.max_distance = 70.0
	add_child(_gun_snd)

	var boost_stream: AudioStreamWAV = load("res://assets/sfx/boost.wav")
	boost_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	boost_stream.loop_begin = int(boost_stream.data.size() / 2 * 0.3)
	boost_stream.loop_end = boost_stream.data.size() / 2
	_boost_snd = AudioStreamPlayer3D.new()
	_boost_snd.stream = boost_stream
	_boost_snd.volume_db = -4.0
	_boost_snd.max_distance = 60.0
	add_child(_boost_snd)

	var alarm_stream: AudioStreamWAV = load("res://assets/sfx/alarm.wav")
	alarm_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	alarm_stream.loop_begin = 0
	alarm_stream.loop_end = alarm_stream.data.size() / 2
	_alarm_snd = AudioStreamPlayer3D.new()
	_alarm_snd.stream = alarm_stream
	_alarm_snd.volume_db = 0.0
	_alarm_snd.max_distance = 70.0
	add_child(_alarm_snd)

	var elec_stream: AudioStreamWAV = load("res://assets/sfx/electric.wav")
	elec_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	elec_stream.loop_begin = 0
	elec_stream.loop_end = elec_stream.data.size() / 2
	_charge_snd = AudioStreamPlayer3D.new()
	_charge_snd.stream = elec_stream
	_charge_snd.volume_db = -4.0
	_charge_snd.max_distance = 45.0
	add_child(_charge_snd)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.55
	m.metallic = 0.25
	return m
