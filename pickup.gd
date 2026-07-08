class_name WeaponPickup
extends Node3D

# ============================================================
#  صندوق عائم يدور - أسلحة أو درع أو تصليح
#  كل نوع له شكل مميز، ويرجع يظهر بمكان عشوائي بعد فترة
# ============================================================

var kind := "rocket"

const AMOUNTS = {"rocket": 5, "homing": 5, "mine": 5}
const COLORS = {
	"rocket": Color(0.95, 0.5, 0.1),
	"homing": Color(0.9, 0.15, 0.15),
	"mine": Color(0.75, 0.7, 0.2),
	"shield": Color(0.3, 0.7, 1.0),
	"repair": Color(0.2, 0.85, 0.35),
}
const LABELS = {"rocket": "قاذف", "homing": "متتبع", "mine": "لغم", "shield": "درع", "repair": "تصليح"}
const RESPAWN = {"rocket": 12.0, "homing": 12.0, "mine": 12.0, "shield": 18.0, "repair": 16.0}

const SHIELD_SECONDS := 6.0
const REPAIR_FRACTION := 0.2

var _visual: Node3D
var _area: Area3D
var _t := 0.0
var _light: OmniLight3D


func _ready() -> void:
	_visual = Node3D.new()
	add_child(_visual)

	match kind:
		"shield":
			_build_shield_shape()
		"repair":
			_build_repair_shape()
		_:
			_build_weapon_shape()

	_light = OmniLight3D.new()
	_light.light_color = COLORS[kind]
	_light.light_energy = 0.6
	_light.omni_range = 4.0
	_light.position.y = 1.0
	add_child(_light)

	var tag := Label3D.new()
	tag.text = LABELS[kind]
	tag.font_size = 64
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.modulate = Color(1, 1, 1, 0.95)
	tag.outline_size = 14
	tag.position.y = 1.5
	_visual.add_child(tag)

	_area = Area3D.new()
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 2.0
	col.shape = shape
	_area.add_child(col)
	_area.position.y = 0.8
	add_child(_area)
	_area.body_entered.connect(_on_body_entered)


func _build_weapon_shape() -> void:
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.85, 0.85, 0.85)
	bm.material = _emat()
	box.mesh = bm
	box.position.y = 1.0
	_visual.add_child(box)


func _build_shield_shape() -> void:
	var core := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.42
	sph.height = 0.84
	sph.material = _emat()
	core.mesh = sph
	core.position.y = 1.0
	_visual.add_child(core)

	for i in 2:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.55
		torus.outer_radius = 0.65
		torus.material = _emat()
		ring.mesh = torus
		ring.position.y = 1.0
		ring.rotation = Vector3(PI / 2.0 * i, 0.0, PI / 3.0 * i)
		_visual.add_child(ring)


func _build_repair_shape() -> void:
	var bar_v := MeshInstance3D.new()
	var vm := BoxMesh.new()
	vm.size = Vector3(0.28, 0.9, 0.28)
	vm.material = _emat()
	bar_v.mesh = vm
	bar_v.position.y = 1.0
	_visual.add_child(bar_v)

	var bar_h := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.9, 0.28, 0.28)
	hm.material = _emat()
	bar_h.mesh = hm
	bar_h.position.y = 1.0
	_visual.add_child(bar_h)


func _emat() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = COLORS[kind]
	mat.emission_enabled = true
	mat.emission = COLORS[kind]
	mat.emission_energy_multiplier = 0.6
	mat.roughness = 0.3
	mat.metallic = 0.3
	return mat


func _process(delta: float) -> void:
	_t += delta
	_visual.rotation.y += delta * 1.7
	_visual.position.y = 1.0 + sin(_t * 2.2) * 0.18


func _on_body_entered(body: Node) -> void:
	if not (body is ArcadeCar and body.alive):
		return
	if not body.input_enabled:
		return
	match kind:
		"shield":
			body.add_shield(SHIELD_SECONDS)
		"repair":
			body.repair(REPAIR_FRACTION)
		_:
			body.give_ammo(kind, AMOUNTS[kind])
	Fx.sound(global_position, "pickup", 0.0, 1.0)
	_collect()


func _collect() -> void:
	visible = false
	_area.set_deferred("monitoring", false)
	await get_tree().create_timer(RESPAWN[kind]).timeout
	global_position = Vector3(randf_range(-50.0, 50.0), 0.0, randf_range(-50.0, 50.0))
	visible = true
	_area.set_deferred("monitoring", true)
