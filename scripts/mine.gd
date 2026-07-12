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
var _trigger_radius := 2.7
var _is_mega := false
var _sparks: Array = []
var _spark_t := 0.0
var _near_t := 0.0
var _enemy_close := false
var _fall_v := 0.0
var _landed := false
var _elec_snd: AudioStreamPlayer3D = null


func _ready() -> void:
	_is_mega = size_mult > 1.5
	# المجمعة تنفجر فقط لما تدوس عليها | العادية نطاق قريب عادي
	# العادية: لازم تدوس عليها فعلاً | المجمعة: بريموت بأي حال
	_trigger_radius = 1.4 if _is_mega else 1.3
	if _is_mega:
		add_to_group("remote_mines")

	# ★ تصميم لغم أرضي صغير (نفس الشكل للعادية والمخزنة)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.14, 0.15, 0.17)
	mat.roughness = 0.45
	mat.metallic = 0.6

	# القرص الأساسي (صغير ومنخفض)
	var base := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.22
	cyl.bottom_radius = 0.27
	cyl.height = 0.095
	cyl.material = mat
	base.mesh = cyl
	base.position.y = 0.048
	add_child(base)
	_core = base

	# 3 أسنان تفجير حول الرأس
	for k in 3:
		var prong := MeshInstance3D.new()
		var pb := BoxMesh.new()
		pb.size = Vector3(0.034, 0.12, 0.034)
		pb.material = mat
		prong.mesh = pb
		var ang := k * TAU / 3.0
		prong.position = Vector3(cos(ang) * 0.12, 0.15, sin(ang) * 0.12)
		add_child(prong)

	# لمبة الرأس: حمراء للعادية، سماوية للمخزنة
	_lamp = MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.06
	sph.height = 0.12
	_lamp_mat = StandardMaterial3D.new()
	var lamp_col := Color(0.3, 0.9, 1.0) if _is_mega else Color(1.0, 0.15, 0.1)
	_lamp_mat.albedo_color = lamp_col
	_lamp_mat.emission_enabled = true
	_lamp_mat.emission = lamp_col
	_lamp_mat.emission_energy_multiplier = 2.5
	sph.material = _lamp_mat
	_lamp.mesh = sph
	_lamp.position.y = 0.185
	add_child(_lamp)

	# ⚡ المخزنة: شرارات كهرباء براسها + صوت كهرباء
	if _is_mega:
		var smat := StandardMaterial3D.new()
		smat.albedo_color = Color(0.8, 0.95, 1.0)
		smat.emission_enabled = true
		smat.emission = Color(0.55, 0.9, 1.0)
		smat.emission_energy_multiplier = 2.8
		smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		for k in 5:
			var spark := MeshInstance3D.new()
			var sb := BoxMesh.new()
			sb.size = Vector3(0.02, 0.02, 0.18)
			sb.material = smat
			spark.mesh = sb
			spark.position = Vector3(0.0, 0.22, 0.0)
			add_child(spark)
			_sparks.append(spark)
		var elec: AudioStreamWAV = load("res://assets/sfx/electric.wav")
		elec.loop_mode = AudioStreamWAV.LOOP_FORWARD
		elec.loop_begin = 0
		elec.loop_end = elec.data.size() / 2
		_elec_snd = AudioStreamPlayer3D.new()
		_elec_snd.stream = elec
		_elec_snd.volume_db = -4.0
		_elec_snd.max_distance = 45.0
		_elec_snd.pitch_scale = 1.35
		add_child(_elec_snd)
		_elec_snd.play()

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

	# 🪂 السقوط للأرض (ما يبقى طائر بالهوا)
	if not _landed:
		_fall_v -= 22.0 * delta
		var next_y := global_position.y + _fall_v * delta
		# نفحص الأرض تحته
		var space := get_world_3d().direct_space_state
		var from := global_position + Vector3.UP * 0.4
		var to := Vector3(global_position.x, next_y - 0.1, global_position.z)
		var q := PhysicsRayQueryParameters3D.create(from, to)
		if owner_car != null and is_instance_valid(owner_car) and owner_car is CollisionObject3D:
			q.exclude = [(owner_car as CollisionObject3D).get_rid()]
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			global_position.y = float(hit["position"].y) + 0.02
			_landed = true
			_fall_v = 0.0
			if _t > 0.15:
				Fx.sound(global_position, "hit", -14.0, 1.4)
		else:
			global_position.y = next_y
			# احتياط: لو طاح تحت الخريطة
			if global_position.y < -5.0:
				queue_free()
				return
	var pulse := 1.0 + sin(_t * 6.0) * 0.06
	_core.scale = Vector3(pulse, 1.0, pulse)
	if _t < _armed_at:
		_lamp.visible = true
		_lamp_mat.emission_energy_multiplier = 1.0
	else:
		var blink := fmod(_t, 0.5) < 0.25
		_lamp.visible = blink
		_lamp_mat.emission_energy_multiplier = 3.5 if blink else 0.0
	# وميض كهرباء الرأس + تنبيه أحمر لما يقرب خصم
	if _is_mega:
		_near_t -= delta
		if _near_t <= 0.0:
			_near_t = 0.2
			_enemy_close = enemy_near()
		if _enemy_close:
			_lamp_mat.emission = Color(1.0, 0.2, 0.1)
			_lamp_mat.emission_energy_multiplier = 5.0 + sin(_t * 25.0) * 3.0
		else:
			_lamp_mat.emission = Color(0.3, 0.9, 1.0)
		_spark_t -= delta
		if _spark_t <= 0.0:
			_spark_t = 0.05
			for spark in _sparks:
				spark.visible = randf() < 0.7
				var dir := Vector3(randf_range(-1, 1), randf_range(0.1, 1), randf_range(-1, 1)).normalized()
				spark.position = Vector3(0, 0.2, 0) + dir * randf_range(0.05, 0.14)
				spark.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)


# 💥 تفجير عن بعد (يستدعيه صاحب اللغم بالزر)
func remote_detonate() -> void:
	if _t < 0.35:
		return
	_boom()


# هل أكو خصم قريب من اللغم؟ (لتنبيه صاحبه)
func enemy_near() -> bool:
	for c in get_tree().get_nodes_in_group("cars"):
		if c == owner_car or not c.get("alive"):
			continue
		if global_position.distance_to(c.global_position) < blast_radius * 0.85:
			return true
	return false


func _on_body_entered(body: Node) -> void:
	if _t < _armed_at:
		return
	# 🎮 المجمعة: بريموت - ما تنفجر بالتلامس، صاحبها يفجرها بالزر
	if _is_mega:
		return
	if body == owner_car and _t < 2.5:
		return
	if body is ArcadeCar and body.alive:
		_boom()


func _boom() -> void:
	Fx.explosion(global_position, damage, blast_radius, launch_dv, owner_car, quake_strength)
	queue_free()
