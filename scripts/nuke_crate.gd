class_name NukeCrate
extends RigidBody3D

# ============================================================
#  صندوق النووي القابل للدفع
#  RigidBody فتگدر تصدمه وتزحلقه بالسيارة، وله دم لازم يتدمر
# ============================================================

signal destroyed(pos)

var health := 300.0
var max_health := 300.0
var _mats: Array = []
var _flash := 0.0
var _dead := false
var _light: OmniLight3D


func _ready() -> void:
	add_to_group("destructibles")
	collision_layer = 1
	collision_mask = 1
	mass = 40.0
	# نخليه ثقيل بس ممكن يندفع
	linear_damp = 1.5
	angular_damp = 2.0
	continuous_cd = true
	_build_visual()


func take_damage(amount: float, _attacker: Node = null) -> void:
	if _dead:
		return
	health -= amount
	_flash = 0.1
	if health <= 0.0:
		_destroy()


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash -= delta
		var e: float = clampf(_flash / 0.1, 0.0, 1.0)
		for m in _mats:
			m.emission_energy_multiplier = 1.5 + e * 2.0
	# نبض الضوء الأصفر
	if _light != null:
		_light.light_energy = 1.5 + sin(Time.get_ticks_msec() * 0.005) * 0.5


func _destroy() -> void:
	_dead = true
	destroyed.emit(global_position)
	Fx.sound(global_position, "explosion", -2.0, 0.6)
	# حطام
	var scene := get_tree().current_scene
	if scene != null:
		var p := GPUParticles3D.new()
		var pm := ParticleProcessMaterial.new()
		pm.direction = Vector3(0, 1, 0)
		pm.spread = 75.0
		pm.initial_velocity_min = 4.0
		pm.initial_velocity_max = 10.0
		pm.gravity = Vector3(0, -12.0, 0)
		pm.scale_min = 0.5
		pm.scale_max = 1.5
		pm.color = Color(0.9, 0.75, 0.1)
		p.process_material = pm
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.4, 0.4, 0.4)
		var mm := StandardMaterial3D.new()
		mm.albedo_color = Color(0.7, 0.6, 0.2)
		mesh.material = mm
		p.draw_pass_1 = mesh
		p.amount = 30
		p.lifetime = 1.5
		p.one_shot = true
		p.explosiveness = 0.9
		p.emitting = true
		scene.add_child(p)
		p.global_position = global_position + Vector3.UP
		get_tree().create_timer(1.8).timeout.connect(p.queue_free)
	queue_free()


func _build_visual() -> void:
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.4, 2.0, 2.4)
	col.shape = shape
	col.position.y = 1.0
	add_child(col)

	# صندوق عسكري
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2.4, 2.0, 2.4)
	var mat := _mat(Color(0.35, 0.38, 0.3))
	mat.metallic = 0.4
	bm.material = mat
	box.mesh = bm
	box.position.y = 1.0
	add_child(box)

	# أشرطة تحذيرية
	var stripe_mat := _mat(Color(0.9, 0.8, 0.1))
	for yy in [0.35, 1.65]:
		var stripe := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(2.5, 0.25, 2.5)
		sm.material = stripe_mat
		stripe.mesh = sm
		stripe.position.y = yy
		add_child(stripe)

	# رمز إشعاع مضيء على الوجهين
	var sym_mat := StandardMaterial3D.new()
	sym_mat.albedo_color = Color(1.0, 0.85, 0.0)
	sym_mat.emission_enabled = true
	sym_mat.emission = Color(1.0, 0.8, 0.0)
	sym_mat.emission_energy_multiplier = 1.5
	_mats.append(sym_mat)
	for zz in [1.22, -1.22]:
		var sym := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.6
		cyl.bottom_radius = 0.6
		cyl.height = 0.05
		cyl.material = sym_mat
		sym.mesh = cyl
		sym.rotation.x = PI / 2.0
		sym.position = Vector3(0, 1.0, zz)
		add_child(sym)

	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.8, 0.0)
	_light.light_energy = 1.5
	_light.omni_range = 8.0
	_light.position.y = 1.5
	add_child(_light)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.6
	m.metallic = 0.2
	_mats.append(m)
	return m
