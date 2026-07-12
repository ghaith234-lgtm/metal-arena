class_name NukeEvent
extends Node3D

# ============================================================
#  حدث السلاح النووي (حدث الخريطة الكبير)
#  كل 5 دقائق: هليكوبتر تنزل صندوق محصّن -> صراع على تدميره
#  -> يطلع السلاح -> من ياخذه عنده 10 ثواني للإطلاق
#  -> الباقي يحاول يدمره -> لو أطلق: صاروخ يصعد وينزل انفجار هائل
# ============================================================

signal announce(text)              # رسالة تنبيه على الشاشة
signal nuke_flash                  # وميض أبيض قوي وقت الانفجار

enum Phase { IDLE, INCOMING, CRATE, WEAPON_READY, CARRIED, LAUNCHED }

@export var interval := 180.0      # كل 3 دقائق (بدل 5)
@export var carry_time := 10.0     # ثواني الإطلاق بعد أخذ السلاح
@export var launch_lockout := 7.0  # ما يقدر يطلق يدوياً إلا بعد مرور هذي الثواني
@export var first_delay := 20.0    # أول ظهور بعد 20 ثانية (للتجربة السهلة)

var get_cars: Callable             # ترجّع كل السيارات (لاعب + AI)

var _phase: Phase = Phase.IDLE
var _timer := 0.0
var _heli: Node3D = null
var _crate: NukeCrate = null
var _weapon: Node3D = null
var _carrier: Node3D = null
var _launcher: Node3D = null    # 🏆 من أطلق النووي (للنقاط)
var _carry_left := 0.0
var _drop_pos := Vector3.ZERO
var _heli_snd: AudioStreamPlayer3D


func _ready() -> void:
	_timer = first_delay


func _process(delta: float) -> void:
	match _phase:
		Phase.IDLE:
			_timer -= delta
			if _timer <= 0.0:
				_start_incoming()
		Phase.INCOMING:
			_update_incoming(delta)
		Phase.WEAPON_READY:
			_update_weapon_float(delta)
		Phase.CARRIED:
			_update_carried(delta)


# ---------- 1. الهليكوبتر قادمة ----------

func _start_incoming() -> void:
	_phase = Phase.INCOMING
	announce.emit("☢ السلاح النووي قادم! ☢")
	Fx.sound(Vector3.ZERO, "siren", 4.0, 1.0)
	# نسقط الصندوق قرب وسط الخريطة (مكان يشوفه الكل)
	# منطقة الإسقاط من ملف الخريطة
	var spread: float = Maps.get_map(Global.selected_map)["nuke_spread"]
	_drop_pos = Vector3(randf_range(-spread, spread), 0.0, randf_range(-spread, spread))

	# هليكوبتر تجي من الجو
	_heli = _build_helicopter()
	add_child(_heli)
	_heli.global_position = _drop_pos + Vector3(35, 22, 35)

	_heli_snd = AudioStreamPlayer3D.new()
	var stream: AudioStreamWAV = load("res://assets/sfx/helicopter.wav")
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = stream.data.size() / 2
	_heli_snd.stream = stream
	_heli_snd.volume_db = -2.0
	_heli_snd.max_distance = 150.0
	_heli.add_child(_heli_snd)
	_heli_snd.play()

	_heli_t = 0.0


var _heli_t := 0.0

func _update_incoming(delta: float) -> void:
	if _heli == null:
		_drop_crate()   # احتياط: لو ما أكو طائرة، أسقط الصندوق مباشرة
		return
	_heli_t += delta
	# تطير نحو نقطة فوق موقع الإسقاط
	var target := _drop_pos + Vector3(0, 18, 0)
	_heli.global_position = _heli.global_position.move_toward(target, delta * 20.0)
	if _heli.has_meta("rotor"):
		var rotor: Node3D = _heli.get_meta("rotor")
		rotor.rotation.y += delta * 30.0

	# تسقط الصندوق عند الوصول، أو بعد 5 ثواني كحد أقصى (ضمان)
	if (_heli.global_position.distance_to(target) < 4.0 and _heli_t > 1.0) or _heli_t > 5.0:
		_drop_crate()


func _drop_crate() -> void:
	_phase = Phase.CRATE
	announce.emit("دمّروا الصندوق للحصول على السلاح!")

	_crate = NukeCrate.new()
	add_child(_crate)
	_crate.global_position = _drop_pos + Vector3(0, 15, 0)
	_crate.destroyed.connect(_on_crate_destroyed)
	# RigidBody يطيح بالجاذبية طبيعياً - غبار عند الهبوط
	_crate_landed = false

	# الهليكوبتر تطير بعيد وتختفي
	var tw := create_tween()
	tw.tween_property(_heli, "global_position", _drop_pos + Vector3(-80, 45, -80), 4.0)
	tw.tween_callback(func() -> void:
		if is_instance_valid(_heli):
			_heli.queue_free()
			_heli = null)


var _crate_landed := false

func _physics_process(_delta: float) -> void:
	# غبار عند هبوط الصندوق (RigidBody يطيح بالفيزياء)
	if _phase == Phase.CRATE and not _crate_landed and _crate != null and is_instance_valid(_crate):
		if _crate.global_position.y < 1.3:
			_crate_landed = true
			Fx.explosion(_crate.global_position, 0.0, 3.0, 3.0, null, 0.6)  # غبار هبوط


# ---------- 2. الصندوق تدمّر => يطلع السلاح ----------

func _on_crate_destroyed(pos: Vector3) -> void:
	_phase = Phase.WEAPON_READY
	announce.emit("السلاح النووي متاح — استولوا عليه!")
	_weapon = _build_weapon_orb()
	add_child(_weapon)
	_weapon.global_position = Vector3(pos.x, 1.2, pos.z)
	_weapon_t = 0.0


var _weapon_t := 0.0

func _update_weapon_float(delta: float) -> void:
	if _weapon == null:
		return
	_weapon_t += delta
	_weapon.rotation.y += delta * 1.5
	_weapon.position.y = 1.2 + sin(_weapon_t * 2.0) * 0.2

	# فحص إذا سيارة لمست السلاح
	for c in _get_cars_safe():
		if not c.alive:
			continue
		if c.global_position.distance_to(_weapon.global_position) < 3.0:
			_pickup_weapon(c)
			return


# ---------- 3. سيارة أخذت السلاح => 10 ثواني للإطلاق ----------

func _pickup_weapon(car: Node3D) -> void:
	_phase = Phase.CARRIED
	_carrier = car
	_carry_left = carry_time
	if _weapon != null:
		_weapon.queue_free()
		_weapon = null
	# نعلّم السيارة إنها الحامل (للـ HUD وزر الإطلاق)
	car.set_meta("has_nuke", true)
	car.nuke_carrier = true
	announce.emit("سيارة تحمل النووي! دمّروها قبل الإطلاق!")
	Fx.sound(car.global_position, "beep", 2.0, 0.5)


func _update_carried(delta: float) -> void:
	# لو الحامل مات أو دخل الحالة الحرجة أو اختفى => السلاح يطيح ويرجع صراع
	if _carrier == null or not is_instance_valid(_carrier) or not _carrier.alive or _carrier.critical:
		_drop_weapon_back()
		return

	_carry_left -= delta
	# ما يقدر يطلق يدوياً إلا بآخر جزء من الوقت (يعطي فرصة للباقين يقتلوه)
	var elapsed := carry_time - _carry_left
	var can_launch_manually := elapsed >= launch_lockout
	# ينفجر تلقائياً بنهاية الوقت، أو يدوياً بعد انتهاء فترة الحظر
	if _carry_left <= 0.0 or (can_launch_manually and _carrier.nuke_launch_pressed):
		_launch_nuke()
		return


func _drop_weapon_back() -> void:
	announce.emit("سقط السلاح — الصراع من جديد!")
	var pos := Vector3.ZERO
	if _carrier != null and is_instance_valid(_carrier):
		pos = _carrier.global_position
		_carrier.nuke_carrier = false
		_carrier.set_meta("has_nuke", false)
	_carrier = null
	_phase = Phase.WEAPON_READY
	_weapon = _build_weapon_orb()
	add_child(_weapon)
	_weapon.global_position = Vector3(pos.x, 1.2, pos.z)
	_weapon_t = 0.0


# ---------- 4. الإطلاق: صاروخ يصعد وينزل انفجار هائل ----------

func _launch_nuke() -> void:
	_launcher = _carrier
	_phase = Phase.LAUNCHED
	var launch_pos := Vector3.ZERO
	if is_instance_valid(_carrier):
		launch_pos = _carrier.global_position
		_carrier.nuke_carrier = false
		_carrier.set_meta("has_nuke", false)
	announce.emit("🚀 تم إطلاق السلاح النووي!")
	Fx.sound(launch_pos, "nuke_launch", 6.0, 1.0)

	# صاروخ يصعد للسماء
	var rocket := _build_rocket()
	add_child(rocket)
	rocket.global_position = launch_pos + Vector3(0, 1, 0)
	var up_tw := create_tween()
	up_tw.tween_property(rocket, "global_position", launch_pos + Vector3(0, 80, 0), 2.0).set_ease(Tween.EASE_IN)
	up_tw.tween_callback(func() -> void:
		if is_instance_valid(rocket):
			rocket.queue_free()
		_nuke_descend(launch_pos))


func _nuke_descend(target: Vector3) -> void:
	# نقطة السقوط = وسط الخريطة (أو موقع الإطلاق)
	var ground := Vector3(target.x, 1.0, target.z)
	Fx.sound(ground, "siren", 2.0, 0.7)
	# صاروخ ينزل من السماء
	var bomb := _build_rocket()
	add_child(bomb)
	bomb.global_position = ground + Vector3(0, 80, 0)
	var down_tw := create_tween()
	down_tw.tween_property(bomb, "global_position", ground, 1.5).set_ease(Tween.EASE_IN)
	down_tw.tween_callback(func() -> void:
		if is_instance_valid(bomb):
			bomb.queue_free()
		_nuke_detonate(ground))


func _nuke_detonate(pos: Vector3) -> void:
	# وميض أبيض + سلو موشن
	nuke_flash.emit()
	Fx.sound(pos, "nuke_blast", 8.0, 1.0)
	Fx.vibrate(400)

	# حفرة دائمة مكان الانفجار
	_spawn_crater(pos)

	# 🎬 بلا بطيء زمني (آمن للعب الشبكي) - الوميض والاهتزاز يكفون

	# انفجار ضخم يغطي مساحة كبيرة جداً
	# 🏆 القاتل = اللي أطلق النووي (تنحسب له النقاط)
	Fx.explosion(pos, 500.0, 55.0, 40.0, _launcher, 4.0)
	# موجات ثانوية للتأثير
	for i in 3:
		var d := create_tween()
		d.tween_interval(0.15 * (i + 1))
		d.tween_callback(func() -> void:
			var off := Vector3(randf_range(-20, 20), 0, randf_range(-20, 20))
			Fx.explosion(pos + off, 0.0, 25.0, 10.0, null, 2.0))

	# نعيد المؤقت للدورة الجاية
	await get_tree().create_timer(4.0).timeout
	_reset_cycle()


func _spawn_crater(pos: Vector3) -> void:
	# حفرة غاطسة داخل الأرض (وعاء منخفض)
	var crater := Node3D.new()

	# نبني الحفرة كطبقات تنزل للأسفل وتضيق (شكل وعاء غاطس)
	# الطبقة العليا عند سطح الأرض (تبين كفتحة)، وتنزل للأعمق والأغمق
	var layers = [
		[16.0, 0.04, Color(0.16, 0.13, 0.09)],   # فتحة الحفرة عند سطح الأرض
		[13.0, -0.8, Color(0.11, 0.09, 0.06)],
		[9.5,  -1.6, Color(0.08, 0.07, 0.05)],
		[6.0,  -2.4, Color(0.05, 0.045, 0.035)],
		[3.0,  -3.1, Color(0.03, 0.03, 0.025)],   # القاع الأعمق والأغمق
	]
	for layer in layers:
		var radius: float = layer[0]
		var depth: float = layer[1]
		var color: Color = layer[2]
		var disc := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = radius
		cyl.bottom_radius = radius * 0.85
		cyl.height = 0.6
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 1.0
		cyl.material = mat
		disc.mesh = cyl
		disc.position.y = depth      # تحت الأرض (سالب)
		crater.add_child(disc)

	# حافة تراب مرتفعة قليلاً حول الحفرة (واقعية - تراب متطاير)
	var rim := MeshInstance3D.new()
	var rim_torus := TorusMesh.new()
	rim_torus.inner_radius = 15.5
	rim_torus.outer_radius = 18.0
	var rim_mat := StandardMaterial3D.new()
	rim_mat.albedo_color = Color(0.22, 0.18, 0.13)
	rim_mat.roughness = 1.0
	rim_torus.material = rim_mat
	rim.mesh = rim_torus
	rim.position.y = 0.15         # ارتفاع بسيط بس (حافة التراب)
	rim.scale.y = 0.4
	crater.add_child(rim)

	# دخان يتصاعد من الحفرة لفترة
	var smoke := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 10.0
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 20.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 3.0
	pm.gravity = Vector3(0, 0.5, 0)
	pm.scale_min = 3.0
	pm.scale_max = 6.0
	pm.color = Color(0.2, 0.19, 0.18, 0.4)
	smoke.process_material = pm
	var smesh := SphereMesh.new()
	smesh.radius = 1.0
	smesh.height = 2.0
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.albedo_color = Color(0.2, 0.19, 0.18, 0.35)
	smesh.material = smat
	smoke.draw_pass_1 = smesh
	smoke.amount = 30
	smoke.lifetime = 4.0
	smoke.position.y = 0.5
	crater.add_child(smoke)

	# نضيف الحفرة للمشهد (تبقى دائمة)
	var scene := get_tree().current_scene
	if scene != null:
		scene.add_child(crater)
		crater.global_position = Vector3(pos.x, 0.0, pos.z)
		var t := get_tree().create_timer(15.0)
		t.timeout.connect(func() -> void:
			if is_instance_valid(smoke):
				smoke.emitting = false)


func _reset_cycle() -> void:
	_phase = Phase.IDLE
	_timer = interval
	_carrier = null
	_crate = null
	_weapon = null


# ---------- أدوات ----------

func get_carrier() -> Node3D:
	return _carrier if _phase == Phase.CARRIED else null

func get_time_until_nuke() -> float:
	# الوقت المتبقي حتى ظهور النووي (بس بحالة الانتظار)
	return _timer if _phase == Phase.IDLE else -1.0

func get_phase_text() -> String:
	# نص حالة الحدث الحالي (للـ HUD)
	match _phase:
		Phase.INCOMING:
			return "الطائرة قادمة..."
		Phase.CRATE:
			return "دمّر الصندوق!"
		Phase.WEAPON_READY:
			return "استولِ على النووي!"
		Phase.CARRIED:
			return "سيارة تحمل النووي!"
		Phase.LAUNCHED:
			return "تم الإطلاق!"
	return ""

func get_objective() -> Node3D:
	# الصندوق أو السلاح - للرادار
	if _crate != null and is_instance_valid(_crate):
		return _crate
	if _weapon != null and is_instance_valid(_weapon):
		return _weapon
	return null

func get_carry_left() -> float:
	return _carry_left

func is_active() -> bool:
	return _phase != Phase.IDLE


func _get_cars_safe() -> Array:
	if get_cars.is_valid():
		return get_cars.call()
	return []


func _build_helicopter() -> Node3D:
	var h := Node3D.new()
	# جسم
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.5, 1.3, 3.5)
	bm.material = _mat(Color(0.2, 0.25, 0.2))
	body.mesh = bm
	h.add_child(body)
	# ذيل
	var tail := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(0.4, 0.4, 2.5)
	tm.material = _mat(Color(0.18, 0.22, 0.18))
	tail.mesh = tm
	tail.position = Vector3(0, 0.3, 2.5)
	h.add_child(tail)
	# مروحة علوية
	var rotor := Node3D.new()
	rotor.position.y = 0.9
	h.add_child(rotor)
	for a in range(4):
		var blade := MeshInstance3D.new()
		var blm := BoxMesh.new()
		blm.size = Vector3(0.2, 0.05, 5.0)
		blm.material = _mat(Color(0.1, 0.1, 0.1))
		blade.mesh = blm
		blade.rotation.y = a * PI / 2.0
		rotor.add_child(blade)
	h.set_meta("rotor", rotor)
	return h


func _build_weapon_orb() -> Node3D:
	var w := Node3D.new()
	# كرة نووية مضيئة
	var core := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.6
	sm.height = 1.2
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 1.0, 0.3)
	mat.emission_enabled = true
	mat.emission = Color(0.4, 1.0, 0.2)
	mat.emission_energy_multiplier = 2.5
	core.mesh = sm
	core.mesh.material = mat
	core.position.y = 1.0
	w.add_child(core)
	# حلقات مدارية
	for i in 3:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.8
		torus.outer_radius = 0.9
		var rmat := StandardMaterial3D.new()
		rmat.albedo_color = Color(0.9, 1.0, 0.3)
		rmat.emission_enabled = true
		rmat.emission = Color(0.9, 1.0, 0.2)
		rmat.emission_energy_multiplier = 1.5
		torus.material = rmat
		ring.mesh = torus
		ring.position.y = 1.0
		ring.rotation = Vector3(PI / 3.0 * i, PI / 4.0 * i, 0)
		w.add_child(ring)
	# ضوء قوي
	var light := OmniLight3D.new()
	light.light_color = Color(0.4, 1.0, 0.3)
	light.light_energy = 3.0
	light.omni_range = 12.0
	light.position.y = 1.0
	w.add_child(light)
	# عمود ضوئي للأعلى (يبين مكانه من بعيد)
	var beam := MeshInstance3D.new()
	var beam_m := CylinderMesh.new()
	beam_m.top_radius = 0.15
	beam_m.bottom_radius = 0.4
	beam_m.height = 40.0
	var bmat := StandardMaterial3D.new()
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmat.albedo_color = Color(0.4, 1.0, 0.3, 0.25)
	beam_m.material = bmat
	beam.mesh = beam_m
	beam.position.y = 20.0
	w.add_child(beam)
	return w


func _build_rocket() -> Node3D:
	var r := Node3D.new()
	var body := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.0
	cyl.bottom_radius = 0.5
	cyl.height = 2.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.85, 0.85)
	mat.metallic = 0.5
	cyl.material = mat
	body.mesh = cyl
	r.add_child(body)
	# لهب خلفي
	var flame := MeshInstance3D.new()
	var fm := CylinderMesh.new()
	fm.top_radius = 0.4
	fm.bottom_radius = 0.0
	fm.height = 1.5
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.albedo_color = Color(1.0, 0.6, 0.1)
	fmat.emission_enabled = true
	fmat.emission = Color(1.0, 0.5, 0.1)
	fm.material = fmat
	flame.mesh = fm
	flame.position.y = -1.8
	flame.rotation.x = PI
	r.add_child(flame)
	# ضوء
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.7, 0.2)
	light.light_energy = 2.5
	light.omni_range = 8.0
	r.add_child(light)
	return r


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.6
	m.metallic = 0.2
	return m
