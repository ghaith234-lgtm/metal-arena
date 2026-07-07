class_name Destructible
extends StaticBody3D

# ============================================================
#  جسم قابل للتدمير: شجرة أو بناية
#  كل نوع له صحة معينة، يومض عند الضرر، ويتفتت عند التدمير
# ============================================================

signal destroyed(pos)

enum Kind { TREE, BUILDING_SMALL, BUILDING_TALL, BARREL, NUKE_CRATE }

@export var kind: Kind = Kind.TREE
var health := 40.0
var max_health := 40.0

var _visual: Node3D
var _mats: Array = []
var _flash := 0.0
var _dead := false
var _debris_color := Color(0.5, 0.5, 0.5)


func setup(k: Kind) -> void:
	kind = k
	add_to_group("destructibles")
	match kind:
		Kind.TREE:
			max_health = 35.0
			_build_tree()
			_debris_color = Color(0.35, 0.5, 0.2)
		Kind.BUILDING_SMALL:
			max_health = 120.0
			_build_building(3.0, 3.5, 3.0, Color(0.6, 0.55, 0.48))
			_debris_color = Color(0.55, 0.5, 0.45)
		Kind.BUILDING_TALL:
			max_health = 220.0
			_build_building(3.5, 7.0, 3.5, Color(0.5, 0.52, 0.58))
			_debris_color = Color(0.5, 0.52, 0.55)
		Kind.BARREL:
			max_health = 18.0
			_build_barrel()
			_debris_color = Color(0.8, 0.4, 0.1)
		Kind.NUKE_CRATE:
			max_health = 300.0
			_build_nuke_crate()
			_debris_color = Color(0.9, 0.75, 0.1)
	health = max_health


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
			m.emission_enabled = true
			m.emission_energy_multiplier = e * 2.0
	elif not _mats.is_empty() and _mats[0].emission_enabled:
		for m in _mats:
			m.emission_enabled = false


func _destroy() -> void:
	_dead = true
	destroyed.emit(global_position)
	# الحطام
	_spawn_debris()
	# البراميل تنفجر
	if kind == Kind.BARREL:
		Fx.explosion(global_position + Vector3.UP * 0.5, 28.0, 4.5, 8.0, null, 1.1)
	elif kind == Kind.NUKE_CRATE:
		# صندوق النووي: صوت خاص، الإشارة تكفي (اللعبة تخلق السلاح)
		Fx.sound(global_position, "explosion", -2.0, 0.6)
	else:
		Fx.sound(global_position, "explosion", -4.0, 0.7)
	# إزالة التصادم فوراً والاختفاء
	collision_layer = 0
	collision_mask = 0
	if _visual != null:
		_visual.queue_free()
	queue_free()


func _spawn_debris() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var p := GPUParticles3D.new()
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 75.0
	mat.initial_velocity_min = 3.0
	mat.initial_velocity_max = 9.0
	mat.gravity = Vector3(0, -12.0, 0)
	mat.scale_min = 0.5
	mat.scale_max = 1.4
	mat.color = _debris_color
	p.process_material = mat
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.35, 0.35, 0.35)
	var mm := StandardMaterial3D.new()
	mm.albedo_color = _debris_color
	mesh.material = mm
	p.draw_pass_1 = mesh
	p.amount = 26
	p.lifetime = 1.4
	p.one_shot = true
	p.explosiveness = 0.9
	p.emitting = true
	scene.add_child(p)
	p.global_position = global_position + Vector3.UP * 0.8
	var timer := get_tree().create_timer(1.6)
	timer.timeout.connect(p.queue_free)


# ---------- بناء الأشكال ----------

func _add_col(size: Vector3, ypos: float) -> void:
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.position.y = ypos
	add_child(col)


func _mat(c: Color, rough := 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	_mats.append(m)
	return m


func _build_tree() -> void:
	_visual = Node3D.new()
	add_child(_visual)

	var trunk := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.18
	tm.bottom_radius = 0.26
	tm.height = 1.6
	tm.material = _mat(Color(0.4, 0.28, 0.16))
	trunk.mesh = tm
	trunk.position.y = 0.8
	_visual.add_child(trunk)

	# ورق على شكل كرات خضراء
	var leaf_c := Color(0.2, 0.45, 0.18)
	var blobs := [
		[Vector3(0, 1.9, 0), 0.85],
		[Vector3(0.4, 1.6, 0.2), 0.6],
		[Vector3(-0.35, 1.7, -0.25), 0.55],
		[Vector3(0.1, 2.3, -0.1), 0.55],
	]
	for b in blobs:
		var leaf := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = b[1]
		sm.height = b[1] * 2.0
		sm.material = _mat(leaf_c.lightened(randf() * 0.15))
		leaf.mesh = sm
		leaf.position = b[0]
		_visual.add_child(leaf)

	_add_col(Vector3(0.5, 1.6, 0.5), 0.8)
	_add_col(Vector3(1.6, 1.4, 1.6), 1.9)


func _build_building(w: float, h: float, d: float, c: Color) -> void:
	_visual = Node3D.new()
	add_child(_visual)

	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w, h, d)
	bm.material = _mat(c)
	body.mesh = bm
	body.position.y = h / 2.0
	_visual.add_child(body)

	# نوافذ (شبكة مضيئة خفيفة)
	var win_mat := StandardMaterial3D.new()
	win_mat.albedo_color = Color(0.15, 0.2, 0.28)
	win_mat.emission_enabled = true
	win_mat.emission = Color(0.6, 0.7, 0.5)
	win_mat.emission_energy_multiplier = 0.25
	_mats.append(win_mat)
	var rows := int(h / 1.3)
	var cols := int(w / 1.0)
	for r in range(1, rows):
		for cc in range(cols):
			for face in [-1, 1]:
				var win := MeshInstance3D.new()
				var wm := BoxMesh.new()
				wm.size = Vector3(0.4, 0.5, 0.05)
				wm.material = win_mat
				win.mesh = wm
				var cx := -w / 2.0 + 0.6 + cc * (w / cols)
				win.position = Vector3(cx, r * 1.3, face * (d / 2.0 + 0.01))
				_visual.add_child(win)

	# سطح
	var roof := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(w + 0.2, 0.3, d + 0.2)
	rm.material = _mat(c.darkened(0.3))
	roof.mesh = rm
	roof.position.y = h + 0.15
	_visual.add_child(roof)

	_add_col(Vector3(w, h, d), h / 2.0)


func _build_barrel() -> void:
	_visual = Node3D.new()
	add_child(_visual)

	var barrel := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.35
	bm.bottom_radius = 0.35
	bm.height = 0.95
	var mat := _mat(Color(0.75, 0.35, 0.1), 0.5)
	mat.metallic = 0.5
	bm.material = mat
	barrel.mesh = bm
	barrel.position.y = 0.48
	_visual.add_child(barrel)

	# شريط تحذير أصفر
	var stripe := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.37
	sm.bottom_radius = 0.37
	sm.height = 0.18
	sm.material = _mat(Color(0.9, 0.8, 0.1), 0.5)
	stripe.mesh = sm
	stripe.position.y = 0.48
	_visual.add_child(stripe)

	_add_col(Vector3(0.7, 0.95, 0.7), 0.48)


func _build_nuke_crate() -> void:
	_visual = Node3D.new()
	add_child(_visual)

	# صندوق عسكري كبير
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2.4, 2.0, 2.4)
	var mat := _mat(Color(0.35, 0.38, 0.3), 0.6)
	mat.metallic = 0.4
	bm.material = mat
	box.mesh = bm
	box.position.y = 1.0
	_visual.add_child(box)

	# أشرطة صفراء/سوداء تحذيرية على الحواف
	var stripe_mat := _mat(Color(0.9, 0.8, 0.1), 0.5)
	for yy in [0.35, 1.65]:
		var stripe := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(2.5, 0.25, 2.5)
		sm.material = stripe_mat
		stripe.mesh = sm
		stripe.position.y = yy
		_visual.add_child(stripe)

	# رمز إشعاع مضيء على الوجوه (دائرة صفراء)
	var sym_mat := StandardMaterial3D.new()
	sym_mat.albedo_color = Color(1.0, 0.85, 0.0)
	sym_mat.emission_enabled = true
	sym_mat.emission = Color(1.0, 0.8, 0.0)
	sym_mat.emission_energy_multiplier = 1.5
	_mats.append(sym_mat)
	for face in [Vector3(0, 1, 2.45 * 0.5 + 0.01), Vector3(0, 1, -(2.45 * 0.5 + 0.01))]:
		var sym := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.6
		cyl.bottom_radius = 0.6
		cyl.height = 0.05
		cyl.material = sym_mat
		sym.mesh = cyl
		sym.rotation.x = PI / 2.0
		sym.position = face
		_visual.add_child(sym)

	# ضوء أصفر ينبض (يلفت الأنظار)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.8, 0.0)
	light.light_energy = 2.0
	light.omni_range = 8.0
	light.position.y = 1.5
	_visual.add_child(light)

	_add_col(Vector3(2.4, 2.0, 2.4), 1.0)
