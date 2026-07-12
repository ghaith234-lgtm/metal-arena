extends Node

# ============================================================
#  Fx (Autoload): أصوات + انفجارات + موجة عصف + زلزال
# ============================================================

signal boom(pos: Vector3, strength: float)

# اهتزاز الهاتف (يشتغل بس على الأندرويد/الموبايل)
func vibrate(ms: int) -> void:
	if OS.has_feature("mobile") or OS.get_name() in ["Android", "iOS"]:
		Input.vibrate_handheld(ms)

const SOUND_PATHS = {
	"shot": "res://assets/sfx/shot.wav",
	"hit": "res://assets/sfx/hit.wav",
	"explosion": "res://assets/sfx/explosion.wav",
	"rocket": "res://assets/sfx/rocket.wav",
	"pickup": "res://assets/sfx/pickup.wav",
	"beep": "res://assets/sfx/beep.wav",
	"boost": "res://assets/sfx/boost.wav",
	"alarm": "res://assets/sfx/alarm.wav",
	"siren": "res://assets/sfx/siren.wav",
	"helicopter": "res://assets/sfx/helicopter.wav",
	"nuke_launch": "res://assets/sfx/nuke_launch.wav",
	"nuke_blast": "res://assets/sfx/nuke_blast.wav",
	"electric": "res://assets/sfx/electric.wav",
	"transform": "res://assets/sfx/transform.wav",
}

var _streams := {}


var _buses_ready := false

# 🎚️ نبني باصات صوت بفلاتر (للأصوات البعيدة المكتومة)
func _setup_buses() -> void:
	var cutoffs := [3200.0, 1400.0, 650.0]    # كل ما بعد، الفلتر أقوى
	var names := ["Far1", "Far2", "Far3"]
	for i in 3:
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, names[i])
		AudioServer.set_bus_send(idx, "Master")
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = cutoffs[i]
		lp.resonance = 0.15
		AudioServer.add_bus_effect(idx, lp)
		# البعيد فيه صدى خفيف (انعكاس المدينة)
		if i >= 1:
			var rv := AudioEffectReverb.new()
			rv.room_size = 0.55 + i * 0.15
			rv.wet = 0.18 + i * 0.08
			rv.dry = 0.85
			AudioServer.add_bus_effect(idx, rv)
	_buses_ready = true


func _ready() -> void:
	_setup_buses()
	for k in SOUND_PATHS:
		var s = _load_sound(SOUND_PATHS[k])
		if s != null:
			_streams[k] = s


# 🔊 تحميل مرن: يقبل wav / ogg / mp3 (تنزل أي صيغة وتشتغل)
func _load_sound(path: String):
	var base: String = path.get_basename()
	var exts: Array[String] = [".wav", ".ogg", ".mp3"]
	for ext in exts:
		var p: String = base + ext
		if ResourceLoader.exists(p):
			var res = load(p)
			if res != null:
				return res
	push_warning("[Fx] صوت مفقود: " + path)
	return null


const SPEED_OF_SOUND := 90.0    # م/ث (مبالغ شوي عن الواقع 343 - يخلي التأخير محسوس)

# 🔊 صوت واقعي: يوصل متأخر حسب المسافة + الترددات العالية تخف بالبعد
func sound(pos: Vector3, sname: String, vol: float = 0.0, pitch: float = 1.0) -> void:
	var scene := get_tree().current_scene
	if scene == null or not _streams.has(sname):
		return

	# مسافة الصوت عن المستمع (اللاعب)
	var listener: Vector3 = _get_listener_pos()
	var dist: float = pos.distance_to(listener)

	# ⏱️ التأخير: الصوت البعيد يوصل متأخر (مثل الواقع)
	var delay := dist / SPEED_OF_SOUND
	if delay > 0.06:
		var t := get_tree().create_timer(delay)
		t.timeout.connect(func() -> void: _play_at(pos, sname, vol, pitch, dist))
	else:
		_play_at(pos, sname, vol, pitch, dist)


func _play_at(pos: Vector3, sname: String, vol: float, pitch: float, dist: float) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = _streams[sname]
	p.volume_db = vol
	p.pitch_scale = pitch * randf_range(0.95, 1.05)
	p.max_distance = 140.0
	p.unit_size = 12.0
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE

	# 🌫️ الصوت البعيد: الترددات العالية تختفي (يصير "مكتوم" مثل الواقع)
	if dist > 25.0:
		var muffle := clampf((dist - 25.0) / 85.0, 0.0, 1.0)
		var bus := _get_far_bus(muffle)
		if bus != "":
			p.bus = bus
		# والبعيد أعمق نغمة شوي (الهواء يبتلع الحدة)
		p.pitch_scale *= 1.0 - muffle * 0.12

	scene.add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)


# موقع المستمع (سيارة اللاعب أو الكاميرا) - يرجّع Vector3 دائماً
func _get_listener_pos() -> Vector3:
	for c in get_tree().get_nodes_in_group("cars"):
		if c.get("controls") != null:      # سيارة اللاعب
			return c.global_position
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		return cam.global_position
	return Vector3.ZERO


# باصات صوت بفلتر ترددات (للأصوات البعيدة)
func _get_far_bus(muffle: float) -> String:
	var idx := clampi(int(muffle * 3.0), 0, 2)
	var names := ["Far1", "Far2", "Far3"]
	return names[idx] if _buses_ready else ""


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
		# اندفاع أفقي حسب قوة الانفجار + رفعة صغيرة مقيّدة (ما يطير للسماء)
		var dir_h: Vector3 = c.global_position - pos
		dir_h.y = 0.0
		if dir_h.length() < 0.1:
			dir_h = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
		dir_h = dir_h.normalized()
		var push := clampf(launch_dv * 1.3, 0.0, 75.0) * f
		var up := clampf(push * 0.28, 0.8, 4.5)
		c.apply_central_impulse((dir_h * push + Vector3.UP * up) * c.mass)
		c.apply_torque_impulse(Vector3(randf_range(-1, 1), randf_range(-0.6, 0.6), randf_range(-1, 1)) * push * c.mass * 0.14)
		if damage > 0.0:
			c.take_damage(damage * f, attacker)

	# ضرر على المباني والأشجار القريبة
	for obj in get_tree().get_nodes_in_group("destructibles"):
		var d: float = obj.global_position.distance_to(pos)
		if d > reach:
			continue
		var f := 1.0 - d / reach
		obj.take_damage(damage * f * 1.5, attacker)

	# 🌪️ عاصفة العصف (للانفجارات القوية): حلقة تتوسع وتدفع السيارات بنطاق أوسع
	if damage >= 45.0 or strength >= 1.5:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.85
		torus.outer_radius = 1.0
		var rmat := StandardMaterial3D.new()
		rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rmat.albedo_color = Color(1.0, 0.8, 0.5, 0.6)
		torus.material = rmat
		ring.mesh = torus
		ring.scale = Vector3.ONE * 0.6
		scene.add_child(ring)
		ring.global_position = pos + Vector3.UP * 0.35
		var storm_r := radius * 2.6
		var tw := scene.create_tween()
		tw.set_parallel(true)
		tw.tween_property(ring, "scale", Vector3.ONE * storm_r, 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(rmat, "albedo_color:a", 0.0, 0.55)
		tw.chain().tween_callback(ring.queue_free)
		# العاصفة توصل السيارات بعد لحظة وتدفعها
		var st := get_tree().create_timer(0.15)
		st.timeout.connect(func() -> void:
			for c2 in get_tree().get_nodes_in_group("cars"):
				if not c2.get("alive"):
					continue
				var d2: float = c2.global_position.distance_to(pos)
				if d2 > storm_r:
					continue
				var f2 := 1.0 - d2 / storm_r
				var dh: Vector3 = c2.global_position - pos
				dh.y = 0.0
				if dh.length() < 0.1:
					dh = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
				dh = dh.normalized()
				var sp := clampf(launch_dv * 0.55, 6.0, 34.0) * f2
				c2.apply_central_impulse((dh * sp + Vector3.UP * clampf(sp * 0.15, 0.4, 1.6)) * c2.mass))

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
