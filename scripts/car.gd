class_name ArcadeCar
extends RigidBody3D

# ============================================================
#  سيارة أركيد قتالية - المرحلة 4
#  فيزياء + رشاش لا نهائي + أسلحة خاصة محدودة + أصوات + تفحيط
# ============================================================

signal died(attacker)
signal health_changed(current, maximum)
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
@export var respawn_delay: float = 4.0

# ---------- بوست الاصطدام (نيترو) ----------
@export var boost_max: float = 100.0
@export var boost_force: float = 2600.0        # قوة الدفع
@export var boost_drain: float = 45.0          # استهلاك بالثانية
@export var boost_regen: float = 12.0          # تعبئة بالثانية
@export var boost_ram_damage: float = 22.0     # ضرر الاصطدام وقت البوست
@export var mine_hold_time: float = 3.0        # ثواني الضغط لزرع عبوة عملاقة

var controls: Node = null
var input_enabled := true
var sounds_enabled := true
var alive := true
var health := 100.0

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
	_apply_drive()
	_apply_boost(delta)
	_try_fire(delta)
	_handle_special(delta)
	_track_drift(delta)
	_update_visuals(delta)
	_update_sounds()
	_check_recovery(delta)


func _read_input() -> void:
	if not input_enabled:
		_steer = 0.0
		_throttle = 0.0
		_drifting = false
		_braking = false
		_firing = false
		_special_in = false
		_cycle_in = false
		return
	if controls != null:
		_steer = controls.get_steer()
		_throttle = controls.get_throttle()
		_drifting = controls.is_drifting()
		_braking = controls.is_braking()
		_firing = controls.is_firing()
		_special_in = controls.is_special_pressed()
		_cycle_in = controls.is_cycle_pressed()
		_boost_in = controls.is_boost_pressed()
		_mine_in = controls.is_mine_pressed()
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

func _try_fire(delta: float) -> void:
	_fire_cooldown -= delta
	if not _firing or _fire_cooldown > 0.0:
		return
	_fire_cooldown = 1.0 / gun_rate

	var b := global_transform.basis
	var from := global_transform * Vector3(0.0, 0.25, -1.25)
	var dir := (-b.z + b.x * randf_range(-0.015, 0.015) + b.y * randf_range(-0.01, 0.01)).normalized()
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

	_spawn_tracer(from, end)
	_muzzle.light_energy = 3.0
	apply_central_force(b.z * 90.0)
	if _gun_snd != null:
		_gun_snd.pitch_scale = randf_range(0.92, 1.12)
		_gun_snd.play()
	fired.emit()


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
	if not alive:
		return
	health = maxf(health - amount, 0.0)
	_flash_timer = 0.12
	health_changed.emit(health, max_health)
	if health <= 0.0:
		_die(attacker)


func _die(attacker: Node) -> void:
	alive = false
	died.emit(attacker)
	Fx.explosion(global_position, 18.0, 4.5, 5.0, attacker)
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

	# ضرر على نفسك فقط من الصدمات المواجهة القوية (جدار/سيارة)
	# الصعود على منحدر أو ملامسة الأرض عموديها للأعلى => closing صغير => لا ضرر
	var self_threshold := 16.0
	if impact > self_threshold:
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


func _update_sounds() -> void:
	if _engine_snd == null:
		return
	var ratio := clampf(linear_velocity.length() / max_speed, 0.0, 1.0)
	_engine_snd.pitch_scale = 0.65 + ratio * 1.15
	if input_enabled:
		_engine_snd.volume_db = -15.0 + ratio * 8.0
	else:
		_engine_snd.volume_db = -24.0
		_engine_snd.pitch_scale = 0.6

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
	shape.size = Vector3(1.3, 0.5, 2.2)
	col.shape = shape
	add_child(col)

	_visual_root = Node3D.new()
	add_child(_visual_root)

	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.3, 0.45, 2.2)
	_body_mat = _mat(body_color)
	_body_mat.emission = Color(1.0, 0.35, 0.25)
	bm.material = _body_mat
	body.mesh = bm
	_visual_root.add_child(body)

	var cabin := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(1.0, 0.35, 1.0)
	var cab_mat := _mat(Color(0.1, 0.13, 0.18))
	cab_mat.roughness = 0.15
	cab_mat.metallic = 0.55
	cm.material = cab_mat
	cabin.mesh = cm
	cabin.position = Vector3(0.0, 0.38, 0.1)
	_visual_root.add_child(cabin)

	var gun := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(0.14, 0.14, 0.9)
	gm.material = _mat(Color(0.2, 0.22, 0.26))
	gun.mesh = gm
	gun.position = Vector3(0.0, 0.28, -0.9)
	_visual_root.add_child(gun)

	# صادم أمامي
	var bumper := MeshInstance3D.new()
	var bump := BoxMesh.new()
	bump.size = Vector3(1.25, 0.18, 0.18)
	bump.material = _mat(Color(0.16, 0.17, 0.2))
	bumper.mesh = bump
	bumper.position = Vector3(0.0, -0.08, -1.14)
	_visual_root.add_child(bumper)

	# جناح خلفي (سبويلر)
	var wing_mat := _mat(Color(0.13, 0.14, 0.17))
	for sx in [-0.4, 0.4]:
		var post := MeshInstance3D.new()
		var pmesh := BoxMesh.new()
		pmesh.size = Vector3(0.08, 0.24, 0.08)
		pmesh.material = wing_mat
		post.mesh = pmesh
		post.position = Vector3(sx, 0.33, 1.0)
		_visual_root.add_child(post)
	var wing := MeshInstance3D.new()
	var wmesh := BoxMesh.new()
	wmesh.size = Vector3(1.25, 0.07, 0.32)
	wmesh.material = wing_mat
	wing.mesh = wmesh
	wing.position = Vector3(0.0, 0.48, 1.02)
	_visual_root.add_child(wing)

	# عوادم
	var ex_mat := _mat(Color(0.35, 0.36, 0.4))
	ex_mat.metallic = 0.8
	ex_mat.roughness = 0.3
	for sx in [-0.35, 0.35]:
		var ex := MeshInstance3D.new()
		var emesh := CylinderMesh.new()
		emesh.top_radius = 0.06
		emesh.bottom_radius = 0.06
		emesh.height = 0.3
		emesh.material = ex_mat
		ex.mesh = emesh
		ex.rotation.x = PI / 2.0
		ex.position = Vector3(sx, -0.1, 1.12)
		_visual_root.add_child(ex)

	# مصابيح أمامية (مضيئة)
	var head_mat := _mat(Color(1.0, 0.95, 0.7))
	head_mat.emission_enabled = true
	head_mat.emission = Color(1.0, 0.9, 0.55)
	head_mat.emission_energy_multiplier = 1.4
	for sx in [-0.42, 0.42]:
		var hl := MeshInstance3D.new()
		var hmesh := BoxMesh.new()
		hmesh.size = Vector3(0.22, 0.1, 0.06)
		hmesh.material = head_mat
		hl.mesh = hmesh
		hl.position = Vector3(sx, 0.08, -1.12)
		_visual_root.add_child(hl)

	# مصابيح خلفية (تشتد مع البريك)
	_tail_mat = _mat(Color(0.9, 0.1, 0.08))
	_tail_mat.emission_enabled = true
	_tail_mat.emission = Color(1.0, 0.12, 0.06)
	_tail_mat.emission_energy_multiplier = 0.35
	for sx in [-0.45, 0.45]:
		var tl := MeshInstance3D.new()
		var tmesh := BoxMesh.new()
		tmesh.size = Vector3(0.22, 0.1, 0.06)
		tmesh.material = _tail_mat
		tl.mesh = tmesh
		tl.position = Vector3(sx, 0.1, 1.12)
		_visual_root.add_child(tl)

	# مقدمة صفراء (اتجاه)
	var nose := MeshInstance3D.new()
	var nm := BoxMesh.new()
	nm.size = Vector3(0.5, 0.12, 0.25)
	nm.material = _mat(Color(1.0, 0.85, 0.2))
	nose.mesh = nm
	nose.position = Vector3(0.0, 0.15, -1.15)
	_visual_root.add_child(nose)


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


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.55
	m.metallic = 0.25
	return m
