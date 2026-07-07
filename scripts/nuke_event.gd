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

@export var interval := 300.0      # كل 5 دقائق
@export var carry_time := 10.0     # ثواني الإطلاق بعد أخذ السلاح
@export var first_delay := 90.0    # أول ظهور بعد دقيقة ونصف

var get_cars: Callable             # ترجّع كل السيارات (لاعب + AI)

var _phase: Phase = Phase.IDLE
var _timer := 0.0
var _heli: Node3D = null
var _crate: Destructible = null
var _weapon: Node3D = null
var _carrier: Node3D = null
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
	_drop_pos = Vector3(randf_range(-15, 15), 0.0, randf_range(-15, 15))

	# هليكوبتر بسيطة تجي من بعيد
	_heli = _build_helicopter()
	add_child(_heli)
	_heli.global_position = _drop_pos + Vector3(60, 35, 60)

	_heli_snd = AudioStreamPlayer3D.new()
	var stream: AudioStreamWAV = load("res://assets/sfx/helicopter.wav")
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = stream.data.size() / 2
	_heli_snd.stream = stream
	_heli_snd.volume_db = -2.0
	_heli_snd.max_distance = 120.0
	_heli.add_child(_heli_snd)
	_heli_snd.play()

	_heli_t = 0.0


var _heli_t := 0.0

func _update_incoming(delta: float) -> void:
	if _heli == null:
		return
	_heli_t += delta
	# تطير نحو نقطة فوق موقع الإسقاط
	var target := _drop_pos + Vector3(0, 30, 0)
	_heli.global_position = _heli.global_position.lerp(target, clampf(delta * 0.6, 0.0, 1.0))
	# تدوير المروحة
	if _heli.has_meta("rotor"):
		var rotor: Node3D = _heli.get_meta("rotor")
		rotor.rotation.y += delta * 30.0

	# وصلت فوق الموقع => تسقط الصندوق
	if _heli.global_position.distance_to(target) < 3.0 and _heli_t > 2.0:
		_drop_crate()


func _drop_crate() -> void:
	_phase = Phase.CRATE
	announce.emit("دمّروا الصندوق للحصول على السلاح!")

	_crate = Destructible.new()
	add_child(_crate)
	_crate.setup(Destructible.Kind.NUKE_CRATE)
	_crate.global_position = _drop_pos + Vector3(0, 25, 0)
	_crate.destroyed.connect(_on_crate_destroyed)
	# نخلي الصندوق يطيح للأرض
	_crate_fall = true

	# الهليكوبتر تطير بعيد وتختفي
	var tw := create_tween()
	tw.tween_property(_heli, "global_position", _drop_pos + Vector3(-80, 45, -80), 4.0)
	tw.tween_callback(func() -> void:
		if is_instance_valid(_heli):
			_heli.queue_free()
			_heli = null)


var _crate_fall := false

func _physics_process(delta: float) -> void:
	# إسقاط الصندوق بسلاسة للأرض
	if _crate_fall and _crate != null and is_instance_valid(_crate):
		if _crate.global_position.y > 1.0:
			_crate.global_position.y -= 18.0 * delta
		else:
			_crate.global_position.y = 1.0
			_crate_fall = false
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
	# لو ضغط زر الإطلاق أو خلص الوقت
	if _carrier.nuke_launch_pressed or _carry_left <= 0.0:
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
	_phase = Phase.LAUNCHED
	var launch_pos := _carrier.global_position if is_instance_valid(_carrier) else Vector3.ZERO
	if is_instance_valid(_carrier):
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

	# سلو موشن لحظة
	Engine.time_scale = 0.25
	var slow_timer := get_tree().create_timer(0.5, true, false, true)  # يتجاهل time_scale
	slow_timer.timeout.connect(func() -> void: Engine.time_scale = 1.0)

	# انفجار ضخم يغطي مساحة كبيرة جداً
	Fx.explosion(pos, 500.0, 55.0, 40.0, null, 4.0)
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


func _reset_cycle() -> void:
	_phase = Phase.IDLE
	_timer = interval
	_carrier = null
	_crate = null
	_weapon = null


# ---------- أدوات ----------

func get_carrier() -> Node3D:
	return _carrier if _phase == Phase.CARRIED else null

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
