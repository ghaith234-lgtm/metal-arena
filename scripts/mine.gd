class_name Mine
extends Node3D

# ============================================================
#  عبوة ناسفة: تتسلح بعد لحظة، تومض بالأحمر،
#  وانفجارها يطيّر السيارة بالهوا
# ============================================================

var owner_car: Node3D = null

var _t := 0.0
var _lamp: MeshInstance3D


func _ready() -> void:
	var base := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.35
	cyl.bottom_radius = 0.42
	cyl.height = 0.22
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.13, 0.14, 0.16)
	mat.roughness = 0.4
	mat.metallic = 0.6
	cyl.material = mat
	base.mesh = cyl
	base.position.y = 0.11
	add_child(base)

	_lamp = MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.09
	sph.height = 0.18
	var lm := StandardMaterial3D.new()
	lm.albedo_color = Color(1.0, 0.15, 0.1)
	lm.emission_enabled = true
	lm.emission = Color(1.0, 0.15, 0.1)
	lm.emission_energy_multiplier = 2.5
	sph.material = lm
	_lamp.mesh = sph
	_lamp.position.y = 0.26
	add_child(_lamp)

	var area := Area3D.new()
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 2.7
	col.shape = shape
	area.add_child(col)
	area.position.y = 0.5
	add_child(area)
	area.body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_t += delta
	if _t < 0.9:
		_lamp.visible = true
	else:
		_lamp.visible = fmod(_t, 0.5) < 0.25


func _on_body_entered(body: Node) -> void:
	if _t < 0.9:
		return
	if body == owner_car and _t < 2.5:
		return
	if body is ArcadeCar and body.alive:
		_boom()


func _boom() -> void:
	Fx.explosion(global_position, 30.0, 4.2, 12.0, owner_car)
	queue_free()
