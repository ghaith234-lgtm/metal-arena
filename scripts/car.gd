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
signal mine_charging(ratio)

# ---------- التعليق ----------
@export var suspension_rest: float = 0.5
@export var wheel_radius: float = 0.3
@export var spring_strength: float = 480.0
@export var spring_damping: float = 90.0

# ---------- الدفع ----------
@export var engine_power: float = 1500.0
@export var max_speed: float = 28.0
@export var reverse_speed: float = 10.0
@export var brake_power: float = 2200.0
@export var extra_air_gravity: float = 6.0

# ---------- التحكم ----------
@export var steer_strength: float = 4.5
@export var grip: float = 6.0
@export var drift_grip: float = 1.7
@export var air_steer: float = 0.8
@export var body_color: Color = Color(0.85, 0.16, 0.1)

# ---------- القتال ----------
@export var max_health: float = 100.0
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
@export var boost_force: float = 2600.0        # قوة الدفع
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
var ai_special := false
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
var _head_mat: StandardMaterial3D
var _headlights: Array = []
var _headlights_on := false

# الأسلحة الخاصة (محدودة العدد)
var ammo := {"rocket": 0, "homing": 0, "mine": 0}
var special := "rocket"

const SPECIAL_ORDER = ["rocket", "homing"]   # القاذف والمتتبع (اللغم له زر مستقل)

const WHEEL_ANCHORS = [
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
var _special_in := false
var _special_prev := false
var _cycle_in := false
var _cycle_prev := false
var _steer := 0.0
var _throttle := 0.0
var _flip_timer := 0.0
var _fire_cooldown := 0.0
var _special_cooldown := 0.0
var _flash_timer := 0.0
var _drift_time := 0.0
var aim_target: Node3D = null      # الهدف الحالي للتوجيه الذكي (للعرض)
var _boost := 100.0
var _boosting := false
var _boost_in := false
var _mine_in := false
var _mine_prev := false
var _mine_hold := 0.0
var _mine_fired_mega := false
var _boost_snd: AudioStreamPlayer3D
var _boost_flame_l: GPUParticles3D
var _boost_flame_r: GPUParticles3D
var _wheel_dist := [0.0, 0.0, 0.0, 0.0]
var _steer_pivots: Array = []
var _spin_nodes: Array = []
var _visual_root: Node3D
var _body_mat: StandardMaterial3D
var _tail_mat: StandardMaterial3D
var _muzzle: OmniLight3D
var _drift_smoke_l: GPUParticles3D
var _drift_smoke_r: GPUParticles3D
var _damage_smoke: GPUParticles3D
var _shield_mesh: MeshInstance3D
var _shield_mat: StandardMaterial3D
var _engine_snd: AudioStreamPlayer3D
var _drift_snd: AudioStreamPlayer3D
var _gun_snd: AudioStreamPlayer3D


func _ready() -> void:
	add_to_group("cars")
	mass = 60.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, -0.25, 0.0)
	angular_damp = 3.0
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


func give_ammo(kind: String, amount: int) -> void:
	ammo[kind] += amount
	if kind != "mine":            # اللغم له زره الخاص، ما يبدّل مؤشر السلاح
		special = kind
	ammo_changed.emit()


func cycle_special() -> void:
	var idx := SPECIAL_ORDER.find(special)
	for i in SPECIAL_ORDER.size():
		idx = (idx + 1) % SPECIAL_ORDER.size()
		if ammo[SPECIAL_ORDER[idx]] > 0:
			break
	special = SPECIAL_ORDER[idx]
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
	_apply_drive()
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
	_update_sounds()
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
		_special_in = false
		_cycle_in = false
		_boost_in = false
		_mine_in = false
		return
	if ai_controlled:
		_steer = ai_steer
		_throttle = ai_throttle
		_drifting = ai_drift
		_braking = false
		_firing = ai_fire
		_special_in = ai_special
		_cycle_in = false
		_boost_in = ai_boost
		_mine_in = false
		_detonate_in = ai_detonate
	elif controls != null:
		_steer = controls.get_steer()
		_throttle = controls.get_throttle()
		_drifting = controls.is_drifting()
		_braking = controls.is_braking()
		_firing = controls.is_firing()
		_special_in = controls.is_special_pressed()
		_cycle_in = controls.is_cycle_pressed()
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
		_special_in = Input.is_key_pressed(KEY_Q)
		_cycle_in = Input.is_key_pressed(KEY_E)
		_boost_in = Input.is_key_pressed(KEY_SHIFT)
		_mine_in = Input.is_key_pressed(KEY_R)
		_detonate_in = Input.is_key_pressed(KEY_X)


func _process_wheel(i: int) -> bool:
	var b := global_transform.basis
	var up := b.y
	var anchor_local: Vector3 = WHEEL_ANCHORS[i]
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


func _apply_drive() -> void:
	if not input_enabled:
		return
	var b := global_transform.basis
	var fwd := -b.z
	var speed := fwd.dot(linear_velocity)

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
			apply_central_force(fwd * engine_power * _throttle * (1.0 - ratio * ratio))
		elif _throttle < -0.05:
			# رجوع للخلف
			if speed > 0.5:
				apply_central_force(-fwd * brake_power * 0.8)   # كبح أول
			elif speed > -reverse_speed:
				apply_central_force(fwd * engine_power * _throttle * 0.55)
		else:
			# ما أكو دفع => احتكاك يبطّئ السيارة تدريجياً (ما تنطلق بروحها)
			apply_central_force(-fwd * speed * 6.0)

		# الانعطاف يشتغل بس إذا السيارة تتحرك
		var speed_factor := clampf(absf(speed) / 7.0, 0.0, 1.0)
		var reverse_flip := 1.0 if speed >= -0.5 else -1.0
		var drift_mult := 1.35 if _drifting else 1.0
		apply_torque(b.y * (-_steer * steer_strength * drift_mult * speed_factor * reverse_flip * mass))
		apply_central_force(-b.y * absf(speed) * 4.0)
	else:
		apply_torque(b.y * (-_steer * air_steer * mass))
		apply_central_force(Vector3.DOWN * extra_air_gravity * mass)


# ============================================================
#  بوست الاصطدام (نيترو)
# ============================================================

func _apply_boost(delta: float) -> void:
	var b := global_transform.basis
	var want := _boost_in and _boost > 1.0 and input_enabled
	_boosting = want
	if want:
		apply_central_force(-b.z * boost_force)
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
	var from := global_transform * Vector3(0.0, 0.25, -1.25)
	aim_target = _find_aim_target(from, -global_transform.basis.z)


func _try_fire(delta: float) -> void:
	_fire_cooldown -= delta
	if not _firing or _fire_cooldown > 0.0:
		return
	_fire_cooldown = 1.0 / gun_rate

	var b := global_transform.basis
	var from := global_transform * Vector3(0.0, 0.25, -1.25)
	var base_dir := -b.z

	# توجيه ذكي: نميل الاتجاه نحو الهدف المقفول (يتحدث كل إطار)
	if aim_assist and input_enabled and aim_target != null and is_instance_valid(aim_target):
		var to_target := (aim_target.global_position + Vector3.UP * 0.3 - from).normalized()
		base_dir = base_dir.slerp(to_target, aim_assist_strength).normalized()

	var dir := (base_dir + b.x * randf_range(-0.012, 0.012) + b.y * randf_range(-0.008, 0.008)).normalized()
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
	_special_cooldown -= delta
	# زر السلاح الخاص (قاذف / متتبع فقط)
	if _cycle_in and not _cycle_prev:
		cycle_special()
	if _special_in and not _special_prev and _special_cooldown <= 0.0:
		_fire_special()
	_special_prev = _special_in
	_cycle_prev = _cycle_in
	# زر العبوات المنفصل: ضغطة = وحدة، ضغط مستمر 3 ثواني = عبوة عملاقة
	_handle_mine_button(delta)


func _handle_mine_button(delta: float) -> void:
	if _mine_in:
		if not _mine_prev:
			# بداية الضغط
			_mine_hold = 0.0
			_mine_fired_mega = false
		if ammo["mine"] >= 2 and not _mine_fired_mega:
			_mine_hold += delta
			mine_charging.emit(clampf(_mine_hold / mine_hold_time, 0.0, 1.0))
			if _mine_hold >= mine_hold_time:
				_plant_mega_mine()
				_mine_fired_mega = true
				mine_charging.emit(0.0)
	else:
		if _mine_prev and not _mine_fired_mega:
			# رفعنا الإصبع قبل 3 ثواني => عبوة وحدة
			_plant_single_mine()
		if _mine_prev:
			mine_charging.emit(0.0)
		_mine_hold = 0.0
	_mine_prev = _mine_in


func _fire_special() -> void:
	if special == "mine":
		cycle_special()
	if ammo[special] <= 0:
		cycle_special()
	if ammo[special] <= 0 or special == "mine":
		Fx.sound(global_position, "beep", -12.0, 0.6)
		return
	_special_cooldown = 0.5
	match special:
		"rocket":
			_launch_projectile(false)
		"homing":
			_launch_projectile(true)
	ammo[special] -= 1
	if ammo[special] <= 0:
		cycle_special()
	ammo_changed.emit()


func _launch_projectile(homing: bool) -> void:
	var p := Projectile.new()
	p.owner_car = self
	p.direction = -global_transform.basis.z
	if homing:
		p.speed = 25.0
		p.damage = 30.0
		p.blast_radius = 3.8
		p.turn_rate = 2.1
		p.target = _find_target()
	else:
		p.speed = 33.0
		p.damage = 35.0
		p.blast_radius = 4.2
	get_parent().add_child(p)
	p.global_position = global_transform * Vector3(0.0, 0.4, -1.7)
	Fx.sound(global_position, "rocket", 0.0, 1.0)


func _find_target() -> Node3D:
	var fwd := -global_transform.basis.z
	var best: Node3D = null
	var best_d := 1e9
	for c in get_tree().get_nodes_in_group("cars"):
		if c == self or not c.alive:
			continue
		var to: Vector3 = c.global_position - global_position
		var d := to.length()
		if d > 65.0 or d < 0.1:
			continue
		if fwd.dot(to / d) < 0.15:
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


func _plant_mega_mine() -> void:
	# يدمج كل الألغام بعبوة عملاقة: زلزال + عصف
	var count: int = ammo["mine"]
	if count <= 0:
		return
	ammo["mine"] = 0
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
	# انفجار قوي حسب القرب (أكبر من العادي)
	Fx.explosion(global_position, critical_blast_damage, critical_blast_radius, critical_launch, attacker, 1.8)
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

	# صدم سيارة ثانية: نضررها حسب السرعة الأفقية
	if body is ArcadeCar:
		var hv := linear_velocity
		hv.y = 0.0
		var v := hv.length()
		if v >= 8.0:
			var dmg := (v - 6.0) * 2.4
			if _boosting:
				dmg += boost_ram_damage
				var push: Vector3 = (body.global_position - global_position).normalized()
				body.apply_central_impulse(push * mass * 6.0)
			body.take_damage(dmg, self)
			_spawn_impact(contact)
			Fx.sound(contact, "hit", 2.0, 0.6)
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
		var anchor: Vector3 = WHEEL_ANCHORS[i]
		var target_y: float = anchor.y - (_wheel_dist[i] - wheel_radius)
		pivot.position.y = lerpf(pivot.position.y, target_y, blend)
		if i < 2:
			pivot.rotation.y = -_steer * 0.45
		var spin: Node3D = _spin_nodes[i]
		spin.rotate_x(-fwd_speed / maxf(wheel_radius, 0.05) * delta)

	_visual_root.rotation.z = lerpf(_visual_root.rotation.z, -_steer * 0.1, blend)
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


func _update_sounds() -> void:
	if _engine_snd == null:
		return
	var ratio := clampf(linear_velocity.length() / max_speed, 0.0, 1.0)
	_engine_snd.pitch_scale = 0.65 + ratio * 1.15
	if not input_enabled:
		_engine_snd.volume_db = -24.0
		_engine_snd.pitch_scale = 0.6
	elif ai_controlled:
		_engine_snd.volume_db = -22.0 + ratio * 6.0     # الأعداء أهدأ
	else:
		_engine_snd.volume_db = -15.0 + ratio * 8.0

	var drift_active := _drifting and _grounded and linear_velocity.length() > 6.0
	if drift_active and not _drift_snd.playing:
		_drift_snd.play()
	elif not drift_active and _drift_snd.playing:
		_drift_snd.stop()
	_drift_snd.pitch_scale = 0.9 + ratio * 0.35


func _check_recovery(delta: float) -> void:
	var upright := global_transform.basis.y.dot(Vector3.UP)
	if upright < 0.2 and linear_velocity.length() < 2.5:
		_flip_timer += delta
		if _flip_timer > 1.2:
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
		var anchor: Vector3 = WHEEL_ANCHORS[i]
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


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.55
	m.metallic = 0.25
	return m
