class_name ChaseCamera
extends Camera3D

# كاميرا مطاردة ناعمة: تلحق السيارة من الخلف
# وتوسع زاوية الرؤية (FOV) كلما زادت السرعة = إحساس سرعة

@export var target: Node3D
@export var distance := 6.5
@export var height := 3.0
@export var follow_speed := 6.0
@export var base_fov := 72.0
@export var max_fov := 84.0


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


func _flat_forward() -> Vector3:
	var f := -target.global_transform.basis.z
	f.y = 0.0
	if f.length() < 0.05:
		return Vector3.FORWARD
	return f.normalized()
