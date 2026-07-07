extends Node

# ============================================================
#  Fx (Autoload): أصوات + انفجارات + موجة عصف + زلزال
# ============================================================

signal boom(pos: Vector3, strength: float)

const SOUND_PATHS = {
	"shot": "res://assets/sfx/shot.wav",
	"hit": "res://assets/sfx/hit.wav",
	"explosion": "res://assets/sfx/explosion.wav",
	"rocket": "res://assets/sfx/rocket.wav",
	"pickup": "res://assets/sfx/pickup.wav",
	"beep": "res://assets/sfx/beep.wav",
	"boost": "res://assets/sfx/boost.wav",
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
	p.max_distance = 110.0
	scene.add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)


# strength: 1.0 = عادي، 3.0+ = عبوة عملاقة (زلزال)
func explosion(pos: Vector3, damage: float, radius: float, launch_dv: float, attacker: Node = null, strength: float = 1.0) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return

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
		c.apply_torque_impulse(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * launch_dv * f * c.mass * 0.15)
		if damage > 0.0:
			c.take_damage(damage * f, attacker)

	# ضرر على المباني والأشجار القريبة
	for obj in get_tree().get_nodes_in_group("destructibles"):
		var d: float = obj.global_position.distance_to(pos)
		if d > reach:
			continue
		var f := 1.0 - d / reach
		obj.take_damage(damage * f * 1.5, attacker)

	var amount := int(55 * strength)
	var p := _burst_particles(Color(1.0, 0.55, 0.15), amount, 0.9 * strength, 6.0 * strength, 17.0 * strength, 0.22 * strength)
	scene.add_child(p)
	p.global_position = pos + Vector3.UP * 0.4
	p.emitting = true

	var smoke := _burst_particles(Color(0.25, 0.24, 0.23, 0.7), int(24 * strength), 1.5 * strength, 2.0, 5.0 * strength, 0.35 * strength)
	scene.add_child(smoke)
	smoke.global_position = pos + Vector3.UP * 0.6
	smoke.emitting = true

	var light := OmniLight3D.new()
	scene.add_child(light)
	light.global_position = pos + Vector3.UP * 1.0
	light.light_color = Color(1.0, 0.6, 0.2)
	light.light_energy = 7.0 * strength
	light.omni_range = 15.0 * strength

	_shockwave(scene, pos, radius * 2.2, strength)

	sound(pos, "explosion", 2.0 + strength * 2.0, clampf(1.15 - strength * 0.12, 0.55, 1.1))
	boom.emit(pos, strength)

	await get_tree().create_timer(1.6).timeout
	if is_instance_valid(p): p.queue_free()
	if is_instance_valid(smoke): smoke.queue_free()
	if is_instance_valid(light): light.queue_free()


# حلقة عصف مرئية تتوسع على الأرض
func _shockwave(scene: Node, pos: Vector3, max_r: float, strength: float) -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.3
	torus.outer_radius = 0.6
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.75, 0.35, 0.75)
	torus.material = mat
	ring.mesh = torus
	scene.add_child(ring)
	ring.global_position = pos + Vector3(0.0, 0.15, 0.0)

	var dur := 0.45 + strength * 0.12
	var t := 0.0
	while t < dur:
		t += get_process_delta_time()
		var k := t / dur
		var r := lerpf(0.6, max_r, k)
		ring.scale = Vector3(r, 1.0, r)
		mat.albedo_color.a = (1.0 - k) * 0.75
		await get_tree().process_frame
	ring.queue_free()


func _burst_particles(color: Color, amount: int, life: float, vmin: float, vmax: float, size: float) -> GPUParticles3D:
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
	p.amount = maxi(amount, 1)
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 1.0
	p.emitting = false
	return p
