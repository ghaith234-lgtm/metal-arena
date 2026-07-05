class_name ArcadeCar
extends RigidBody3D

# ============================================================
#  سيارة أركيد بنظام Raycast Suspension
#  جسم RigidBody3D واحد + 4 أشعة مكان الإطارات (بدون VehicleBody3D)
#  المدخلات تجي من كائن controls خارجي => جاهزة للملتيبلاير لاحقاً
# ============================================================

# ---------- التعليق (Suspension) ----------
@export var suspension_rest: float = 0.5     # طول التعليق وهو مرتاح
@export var wheel_radius: float = 0.3        # نصف قطر الإطار
@export var spring_strength: float = 480.0   # قوة النابض (أعلى = أقسى)
@export var spring_damping: float = 90.0     # تخميد النابض (أعلى = أقل نطّة)

# ---------- الدفع ----------
@export var engine_power: float = 1500.0     # قوة المحرك (التسارع تلقائي)
@export var max_speed: float = 28.0          # السرعة القصوى m/s (~100 كم/س)
@export var reverse_speed: float = 10.0      # سرعة الرجوع القصوى
@export var brake_power: float = 2200.0      # قوة البريك
@export var extra_air_gravity: float = 6.0   # جاذبية إضافية بالهواء (قفزات أسرع)

# ---------- التحكم ----------
@export var steer_strength: float = 4.5      # حدّة الانعطاف
@export var grip: float = 6.0                # تماسك الإطارات الطبيعي
@export var drift_grip: float = 1.7          # التماسك وقت الدرفت (أقل = ينزلق أكثر)
@export var air_steer: float = 0.8           # توجيه بالهواء
@export var body_color: Color = Color(0.85, 0.16, 0.1)

# مصدر المدخلات (TouchControls) - إذا null يشتغل كيبورد مباشرة
var controls: Node = null

const WHEEL_ANCHORS = [
	Vector3(-0.62, -0.15, -0.85),  # أمامي يسار
	Vector3(0.62, -0.15, -0.85),   # أمامي يمين
	Vector3(-0.62, -0.15, 0.85),   # خلفي يسار
	Vector3(0.62, -0.15, 0.85),    # خلفي يمين
]

var _spawn_transform: Transform3D
var _grounded := false
var _drifting := false
var _braking := false
var _steer := 0.0
var _flip_timer := 0.0
var _wheel_dist := [0.0, 0.0, 0.0, 0.0]
var _steer_pivots: Array = []
var _spin_nodes: Array = []


func _ready() -> void:
	mass = 60.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, -0.25, 0.0)  # مركز ثقل واطي = انقلاب أقل
	angular_damp = 3.0
	linear_damp = 0.05
	can_sleep = false
	continuous_cd = true
	var pm := PhysicsMaterial.new()
	pm.friction = 0.5
	pm.bounce = 0.2
	physics_material_override = pm
	_build_body()
	_build_wheels()
	_spawn_transform = global_transform


func get_speed_kmh() -> float:
	return linear_velocity.length() * 3.6


# ============================================================
#  الحلقة الفيزيائية
# ============================================================

func _physics_process(delta: float) -> void:
	_read_input()
	var wheels_on_ground := 0
	for i in 4:
		if _process_wheel(i):
			wheels_on_ground += 1
	_grounded = wheels_on_ground > 0
	_apply_drive()
	_update_wheel_visuals(delta)
	_check_recovery(delta)


func _read_input() -> void:
	if controls != null:
		_steer = controls.get_steer()
		_drifting = controls.is_drifting()
		_braking = controls.is_braking()
	else:
		_steer = Input.get_axis("ui_left", "ui_right")
		_drifting = Input.is_key_pressed(KEY_SPACE)
		_braking = Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S)


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

	# قوة النابض حسب مقدار الانضغاط (0 الى 1)
	var compression := clampf(1.0 - (dist - wheel_radius) / suspension_rest, 0.0, 1.0)
	var point_vel := _point_velocity(from)
	var spring_f := spring_strength * compression
	var damp_f := spring_damping * up.dot(point_vel)
	var force := up * (spring_f - damp_f)

	# تماسك جانبي: نقتل السرعة الجانبية عند الإطار (هنا يصير الدرفت)
	var side := b.x
	var lateral_vel := side.dot(point_vel)
	var current_grip := drift_grip if _drifting else grip
	force += -side * lateral_vel * current_grip * (mass / 4.0)

	apply_force(force, from - global_position)
	return true


func _point_velocity(world_point: Vector3) -> Vector3:
	return linear_velocity + angular_velocity.cross(world_point - global_position)


func _apply_drive() -> void:
	var b := global_transform.basis
	var fwd := -b.z
	var speed := fwd.dot(linear_velocity)

	if _grounded:
		if _braking:
			if speed > 1.0:
				apply_central_force(-fwd * brake_power)
			elif speed > -reverse_speed:
				apply_central_force(-fwd * engine_power * 0.55)
		else:
			# تسارع تلقائي يخف كلما اقتربت من السرعة القصوى
			var ratio := clampf(speed / max_speed, 0.0, 1.0)
			apply_central_force(fwd * engine_power * (1.0 - ratio * ratio))

		# الانعطاف: عزم حول محور Y، يقوى مع السرعة وينعكس بالرجوع
		var speed_factor := clampf(absf(speed) / 7.0, 0.0, 1.0)
		var reverse_flip := 1.0 if speed >= -0.5 else -1.0
		var boost := 1.25 if _drifting else 1.0
		apply_torque(b.y * (-_steer * steer_strength * boost * speed_factor * reverse_flip * mass))

		# ضغط أرضي بسيط يثبت السيارة بالسرعات العالية
		apply_central_force(-b.y * absf(speed) * 4.0)
	else:
		apply_torque(b.y * (-_steer * air_steer * mass))
		apply_central_force(Vector3.DOWN * extra_air_gravity * mass)


# ============================================================
#  الإطارات المرئية + الاستعادة التلقائية
# ============================================================

func _update_wheel_visuals(delta: float) -> void:
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


func _check_recovery(delta: float) -> void:
	# إذا انقلبت السيارة وتوقفت، نعدلها تلقائياً بعد ثانية
	var upright := global_transform.basis.y.dot(Vector3.UP)
	if upright < 0.2 and linear_velocity.length() < 2.5:
		_flip_timer += delta
		if _flip_timer > 1.2:
			_recover()
	else:
		_flip_timer = 0.0
	# إذا طاحت برا الخارطة لأي سبب
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


# ============================================================
#  بناء الشكل بالكود (بدون أي أصول خارجية)
# ============================================================

func _build_body() -> void:
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.3, 0.5, 2.2)
	col.shape = shape
	add_child(col)

	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.3, 0.45, 2.2)
	bm.material = _mat(body_color)
	body.mesh = bm
	add_child(body)

	var cabin := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(1.0, 0.35, 1.0)
	cm.material = _mat(Color(0.12, 0.14, 0.18))
	cabin.mesh = cm
	cabin.position = Vector3(0.0, 0.38, 0.1)
	add_child(cabin)

	# مقدمة صفراء حتى يبين اتجاه السيارة
	var nose := MeshInstance3D.new()
	var nm := BoxMesh.new()
	nm.size = Vector3(0.5, 0.12, 0.25)
	nm.material = _mat(Color(1.0, 0.85, 0.2))
	nose.mesh = nm
	nose.position = Vector3(0.0, 0.15, -1.15)
	add_child(nose)


func _build_wheels() -> void:
	for i in 4:
		var anchor: Vector3 = WHEEL_ANCHORS[i]
		var steer_pivot := Node3D.new()
		steer_pivot.position = anchor
		add_child(steer_pivot)

		var spin := Node3D.new()
		steer_pivot.add_child(spin)

		var mesh := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = wheel_radius
		cyl.bottom_radius = wheel_radius
		cyl.height = 0.24
		cyl.material = _mat(Color(0.08, 0.08, 0.09))
		mesh.mesh = cyl
		mesh.rotation.z = PI / 2.0
		spin.add_child(mesh)

		_steer_pivots.append(steer_pivot)
		_spin_nodes.append(spin)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.55
	m.metallic = 0.25
	return m
