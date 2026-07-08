class_name Mine
extends Node3D

# ============================================================
#  عبوة ناسفة - بحركة نبض حية
#  size_mult=1 عادية، وأكبر = عبوة عملاقة (زلزال وعصف)
# ============================================================

var owner_car: Node3D = null
var size_mult := 1.0       # 1 = عادية، 2.2 = عملاقة
var damage := 30.0
var blast_radius := 4.2
var launch_dv := 12.0
var quake_strength := 1.0

var _t := 0.0
var _armed_at := 0.9
var _lamp: MeshInstance3D
var _lamp_mat: StandardMaterial3D
var _core: MeshInstance3D
var _ring: MeshInstance3D
var _trigger_radius := 2.7


func _ready() -> void:
	_trigger_radius = 2.7 * (1.0 + (size_mult - 1.0) * 0.6)

	var base := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.35 * size_mult
	cyl.bottom_radius = 0.42 * size_mult
	cyl.height = 0.22 * size_mult
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.13, 0.14, 0.16)
	mat.roughness = 0.4
	mat.metallic = 0.6
	cyl.material = mat
	base.mesh = cyl
	base.position.y = 0.11 * size_mult
	add_child(base)
	_core = base

	# حلقة حول العبوة العملاقة تأكيداً إنها خطيرة
	if size_mult > 1.5:
		_ring = MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.5 * size_mult
		torus.outer_radius = 0.62 * size_mult
		var rm := StandardMaterial3D.new()
		rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rm.albedo_color = Color(1.0, 0.4, 0.1)
		torus.material = rm
		_ring.mesh = torus
		_ring.position.y = 0.12 * size_mult
		add_child(_ring)

	_lamp = MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.09 * size_mult
	sph.height = 0.18 * size_mult
	_lamp_mat = StandardMaterial3D.new()
	_lamp_mat.albedo_color = Color(1.0, 0.15, 0.1)
	_lamp_mat.emission_enabled = true
	_lamp_mat.emission = Color(1.0, 0.15, 0.1)
	_lamp_mat.emission_energy_multiplier = 2.5
	sph.material = _lamp_mat
	_lamp.mesh = sph
	_lamp.position.y = 0.26 * size_mult
	add_child(_lamp)

	var area := Area3D.new()
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = _trigger_radius
	col.shape = shape
	area.add_child(col)
	area.position.y = 0.5
	add_child(area)
	area.body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_t += delta
	# نبض الحجم والضوء
	var pulse := 1.0 + sin(_t * 6.0) * 0.06
	_core.scale = Vector3(pulse, 1.0, pulse)
	if _t < _armed_at:
		_lamp.visible = true
		_lamp_mat.emission_energy_multiplier = 1.0
	else:
		var blink := fmod(_t, 0.5) < 0.25
		_lamp.visible = blink
		_lamp_mat.emission_energy_multiplier = 3.5 if blink else 0.0
	if _ring != null:
		_ring.rotation.y += delta * 2.5
		_ring.scale = Vector3(pulse, 1.0, pulse)


func _on_body_entered(body: Node) -> void:
	if _t < _armed_at:
		return
	if body == owner_car and _t < 2.5:
		return
	if body is ArcadeCar and body.alive:
		_boom()


func _boom() -> void:
	Fx.explosion(global_position, damage, blast_radius, launch_dv, owner_car, quake_strength)
	queue_free()
