class_name ChaseCamera
extends Camera3D

# كاميرا مطاردة ناعمة + اهتزاز عند الانفجارات والإصابات

@export var target: Node3D
@export var distance := 6.5
@export var height := 3.0
@export var follow_speed := 6.0
@export var base_fov := 72.0
@export var max_fov := 84.0

var _trauma := 0.0


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
	var t := 1.0 - exp(-follow_speed * delta)
	global_position = global_position.lerp(desired, t)
	look_at(target.global_position + Vector3.UP * 0.9 + flat * 2.0, Vector3.UP)

	var spd := 0.0
	if target is RigidBody3D:
		spd = (target as RigidBody3D).linear_velocity.length()
	var target_fov := lerpf(base_fov, max_fov, clampf(spd / 28.0, 0.0, 1.0))
	fov = lerpf(fov, target_fov, 1.0 - exp(-4.0 * delta))

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
