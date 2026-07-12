class_name ChaseCamera
extends Camera3D

# كاميرا مطاردة ناعمة + اهتزاز عند الانفجارات والإصابات

@export var target: Node3D
@export var distance := 5.4          # أقرب شوي
@export var height := 1.35           # 🎬 واطية (منظور سينمائي - السيارة تبين ضخمة)
@export var follow_speed := 5.0      # أبطأ = إحساس بالوزن
@export var base_fov := 55.0         # 🎬 مجال ضيق = ضخامة (كان 68 = يصغّر كل شي)
@export var max_fov := 72.0          # يتوسع بالسرعة (إحساس اندفاع)
@export var look_height := 0.9       # ننظر لجسم السيارة مو فوقها

var _trauma := 0.0
var _roll := 0.0
var _kill_zoom := 0.0


# 🎬 زوم سريع عند القتلة (إحساس الضربة - بلا بطيء زمني)
func kill_zoom() -> void:
	_kill_zoom = 1.0


func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.5)


func _ready() -> void:
	fov = base_fov
	if target != null:
		var flat := _flat_forward()
		global_position = target.global_position - flat * distance + Vector3.UP * height
		look_at(target.global_position + Vector3.UP, Vector3.UP)


func _physics_process(delta: float) -> void:
	if target == null:
		return
	var flat := _flat_forward()
	var desired := target.global_position - flat * distance + Vector3.UP * height
	# 🧱 جدار ورا السيارة؟ الجدار يدفع الكاميرا للأمام وترتفع فوق حتى ما تنغطى السيارة
	var from := target.global_position + Vector3.UP * 1.0
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, desired)
	if target is CollisionObject3D:
		q.exclude = [(target as CollisionObject3D).get_rid()]
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		var n: Vector3 = hit["normal"]
		desired = hit["position"] + n * 0.35
		# كل ما انضغطت أكثر، ترتفع أكثر (رؤية من فوق)
		var closeness := 1.0 - clampf(from.distance_to(desired) / distance, 0.0, 1.0)
		desired += Vector3.UP * closeness * 2.2
	var spd := 0.0
	var vel := Vector3.ZERO
	if target is RigidBody3D:
		vel = (target as RigidBody3D).linear_velocity
		spd = vel.length()
	var sr: float = clampf(spd / 26.0, 0.0, 1.0)

	# 🎬 الكاميرا تتأخر بالسرعة (إحساس اندفاع وقصور ذاتي)
	desired -= flat * sr * 1.3
	desired += Vector3.UP * sr * 0.25

	var t := 1.0 - exp(-follow_speed * delta)
	global_position = global_position.lerp(desired, t)

	# 🎬 نظرة أمامية تسبق السيارة بالسرعة (تحس بالاندفاع)
	var look_ahead: Vector3 = target.global_position + Vector3.UP * look_height + flat * (2.0 + sr * 4.0)
	look_at(look_ahead, Vector3.UP)

	# 🎬 ميلان الكاميرا مع الانعطاف (roll سينمائي)
	var lat := 0.0
	if target is RigidBody3D:
		lat = (target as RigidBody3D).angular_velocity.y
	_roll = lerpf(_roll, clampf(-lat * 0.06, -0.12, 0.12), clampf(delta * 5.0, 0.0, 1.0))
	rotate_object_local(Vector3.FORWARD, _roll)

	# 🎬 اهتزاز خفيف بالسرعة العالية (إحساس السرعة والوزن)
	if sr > 0.35:
		var jitter: float = (sr - 0.35) * 0.035
		var jx: float = sin(Time.get_ticks_msec() * 0.031) * jitter
		var jy: float = sin(Time.get_ticks_msec() * 0.047) * jitter * 0.7
		global_position += global_transform.basis.x * jx + global_transform.basis.y * jy

	# مجال الرؤية يتوسع بالسرعة (نفق السرعة)
	var target_fov := lerpf(base_fov, max_fov, sr * sr)
	# 🎬 زوم القتلة: تضييق سريع ثم رجوع (إحساس التركيز)
	if _kill_zoom > 0.0:
		_kill_zoom = maxf(_kill_zoom - delta * 3.2, 0.0)
		target_fov -= _kill_zoom * 9.0
	fov = lerpf(fov, target_fov, 1.0 - exp(-8.0 * delta))

	# اهتزاز الكاميرا
	if _trauma > 0.0:
		_trauma = maxf(_trauma - delta * 1.6, 0.0)
		var shake := _trauma * _trauma
		h_offset = randf_range(-1.0, 1.0) * shake * 0.6
		v_offset = randf_range(-1.0, 1.0) * shake * 0.6
		rotation.z = randf_range(-1.0, 1.0) * shake * 0.04
	else:
		h_offset = 0.0
		v_offset = 0.0
		rotation.z = lerpf(rotation.z, 0.0, clampf(delta * 8.0, 0.0, 1.0))


func _flat_forward() -> Vector3:
	var f := -target.global_transform.basis.z
	f.y = 0.0
	if f.length() < 0.05:
		return Vector3.FORWARD
	return f.normalized()
