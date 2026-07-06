class_name WeaponPickup
extends Node3D

# ============================================================
#  صندوق سلاح عائم يدور - يعطي ذخيرة ويرجع يظهر
#  بمكان عشوائي جديد بعد 12 ثانية
# ============================================================

var kind := "rocket"

const AMOUNTS = {"rocket": 2, "homing": 1, "mine": 2}
const COLORS = {
	"rocket": Color(0.95, 0.5, 0.1),
	"homing": Color(0.9, 0.15, 0.15),
	"mine": Color(0.75, 0.7, 0.2),
}
const LABELS = {"rocket": "قاذف", "homing": "متتبع", "mine": "لغم"}

var _visual: Node3D
var _area: Area3D
var _t := 0.0


func _ready() -> void:
	_visual = Node3D.new()
	add_child(_visual)

	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.85, 0.85, 0.85)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = COLORS[kind]
	mat.emission_enabled = true
	mat.emission = COLORS[kind]
	mat.emission_energy_multiplier = 0.5
	mat.roughness = 0.35
	bm.material = mat
	box.mesh = bm
	_visual.add_child(box)

	var tag := Label3D.new()
	tag.text = LABELS[kind]
	tag.font_size = 68
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.modulate = Color(1, 1, 1, 0.95)
	tag.outline_size = 14
	tag.position.y = 1.1
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


func _process(delta: float) -> void:
	_t += delta
	_visual.rotation.y += delta * 1.7
	_visual.position.y = 1.0 + sin(_t * 2.2) * 0.18


func _on_body_entered(body: Node) -> void:
	if body is ArcadeCar and body.alive and body.input_enabled:
		body.give_ammo(kind, AMOUNTS[kind])
		Fx.sound(global_position, "pickup", 0.0, 1.0)
		_collect()


func _collect() -> void:
	visible = false
	_area.set_deferred("monitoring", false)
	await get_tree().create_timer(12.0).timeout
	global_position = Vector3(randf_range(-50.0, 50.0), 0.0, randf_range(-50.0, 50.0))
	visible = true
	_area.set_deferred("monitoring", true)
