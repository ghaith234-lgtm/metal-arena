class_name Projectile
extends Node3D

# ============================================================
#  صاروخ: مستقيم (قاذف) أو متتبع (turn_rate > 0)
#  المتتبع دورانه محدود => تگدر تهرب منه بدرفت حاد أو عمود
# ============================================================

var owner_car: Node3D = null
var target: Node3D = null
var direction := Vector3.FORWARD
var speed := 30.0
var damage := 35.0
var blast_radius := 4.0
var launch_dv := 4.5
var turn_rate := 0.0        # راديان/ثانية (0 = مستقيم)
var life := 5.0

var _beep_t := 0.3
var _armed := 0.0


func _ready() -> void:
	var body := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.0
	cyl.bottom_radius = 0.12
	cyl.height = 0.7
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.35, 0.1)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.5, 0.1)
	cyl.material = mat
	body.mesh = cyl
	body.rotation.x = -PI / 2.0
	add_child(body)

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.2)
	light.light_energy = 1.6
	light.omni_range = 5.0
	add_child(light)

	var trail := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0, 1)
	pm.spread = 10.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 1.5
	pm.gravity = Vector3(0, 0.8, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	pm.color = Color(0.8, 0.8, 0.8, 0.6)
	trail.process_material = pm
	var mesh := SphereMesh.new()
	mesh.radius = 0.1
	mesh.height = 0.2
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.albedo_color = Color(0.85, 0.85, 0.85, 0.55)
	mesh.material = mm
	trail.draw_pass_1 = mesh
	trail.amount = 40
	trail.lifetime = 0.6
	trail.emitting = true
	add_child(trail)


func _physics_process(delta: float) -> void:
	life -= delta
	_armed += delta
	if life <= 0.0:
		_explode(global_position)
		return

	# تتبع الهدف بدوران محدود
	if turn_rate > 0.0 and is_instance_valid(target) and target.get("alive"):
		var desired := (target.global_position + Vector3.UP * 0.5 - global_position).normalized()
		var ang := direction.angle_to(desired)
		if ang > 0.001:
			var axis := direction.cross(desired)
			if axis.length() > 0.001:
				direction = direction.rotated(axis.normalized(), minf(turn_rate * delta, ang)).normalized()
		_beep_t -= delta
		if _beep_t <= 0.0:
			_beep_t = 0.45
			Fx.sound(global_position, "beep", -8.0, 1.3)

	var next := global_position + direction * speed * delta
	var query := PhysicsRayQueryParameters3D.create(global_position, next)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	if owner_car != null:
		query.exclude = [owner_car.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		# الانفجار نفسه يوزع الضرر بمنطقة (بضمنها السيارة المصابة)
		_explode(hit["position"])
		return

	global_position = next
	if absf(direction.y) < 0.95:
		look_at(global_position + direction, Vector3.UP)


func _explode(pos: Vector3) -> void:
	Fx.explosion(pos, damage, blast_radius, launch_dv, owner_car)
	queue_free()
