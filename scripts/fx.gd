extends Node

# ============================================================
#  Fx (Autoload): أصوات + انفجارات مشتركة لكل الكائنات
#  الانفجار يوزع ضرر بمنطقة + دفعة تطيّر السيارات
# ============================================================

signal boom(pos: Vector3)

const SOUND_PATHS = {
	"shot": "res://assets/sfx/shot.wav",
	"hit": "res://assets/sfx/hit.wav",
	"explosion": "res://assets/sfx/explosion.wav",
	"rocket": "res://assets/sfx/rocket.wav",
	"pickup": "res://assets/sfx/pickup.wav",
	"beep": "res://assets/sfx/beep.wav",
}

var _streams := {}


func _ready() -> void:
	for k in SOUND_PATHS:
		_streams[k] = load(SOUND_PATHS[k])


func sound(pos: Vector3, sname: String, vol: float = 0.0, pitch: float = 1.0) -> void:
	var scene := get_tree().current_scene
	if scene == null or not _streams.has(sname):
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = _streams[sname]
	p.volume_db = vol
	p.pitch_scale = pitch * randf_range(0.95, 1.05)
	p.max_distance = 90.0
	scene.add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)


func explosion(pos: Vector3, damage: float, radius: float, launch_dv: float, attacker: Node = null) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return

	# ضرر + دفعة على كل السيارات القريبة
	var reach := radius + 1.6
	for c in get_tree().get_nodes_in_group("cars"):
		if not c.alive:
			continue
		var d: float = c.global_position.distance_to(pos)
		if d > reach:
			continue
		var f := 1.0 - d / reach
		var dirv: Vector3 = c.global_position - pos
		dirv.y = maxf(dirv.y, 0.0)
		if dirv.length() < 0.1:
			dirv = Vector3.UP
		dirv = (dirv.normalized() + Vector3.UP * 1.3).normalized()
		c.apply_central_impulse(dirv * launch_dv * f * c.mass)
		if damage > 0.0:
			c.take_damage(damage * f, attacker)

	# جزيئات + ضوء + صوت
	var p := _burst_particles(pos, Color(1.0, 0.55, 0.15), 55, 0.9, 6.0, 17.0, 0.22)
	scene.add_child(p)
	p.global_position = pos + Vector3.UP * 0.4
	p.emitting = true

	var smoke := _burst_particles(pos, Color(0.25, 0.24, 0.23, 0.7), 24, 1.5, 2.0, 5.0, 0.35)
	scene.add_child(smoke)
	smoke.global_position = pos + Vector3.UP * 0.6
	smoke.emitting = true

	var light := OmniLight3D.new()
	scene.add_child(light)
	light.global_position = pos + Vector3.UP * 1.0
	light.light_color = Color(1.0, 0.6, 0.2)
	light.light_energy = 7.0
	light.omni_range = 15.0

	sound(pos, "explosion", 2.0, randf_range(0.9, 1.1))
	boom.emit(pos)

	await get_tree().create_timer(1.6).timeout
	if is_instance_valid(p):
		p.queue_free()
	if is_instance_valid(smoke):
		smoke.queue_free()
	if is_instance_valid(light):
		light.queue_free()


func _burst_particles(_pos: Vector3, color: Color, amount: int, life: float, vmin: float, vmax: float, size: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0.0, 1.0, 0.0)
	mat.spread = 180.0
	mat.initial_velocity_min = vmin
	mat.initial_velocity_max = vmax
	mat.gravity = Vector3(0.0, -5.0, 0.0)
	mat.scale_min = 0.6
	mat.scale_max = 1.5
	mat.color = color
	p.process_material = mat
	var mesh := SphereMesh.new()
	mesh.radius = size
	mesh.height = size * 2.0
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.albedo_color = color
	mesh.material = mm
	p.draw_pass_1 = mesh
	p.amount = amount
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 1.0
	p.emitting = false
	return p
