class_name CarAI
extends Node

# ============================================================
#  دماغ الذكاء الاصطناعي لسيارة العدو
#  يتصرف كمصدر إدخال: يلاحق، يناور، يطلق، يهرب لما يتأذى
#  يعمل عبر ضبط متغيرات الإدخال بالسيارة مباشرة كل إطار
# ============================================================

enum State { WANDER, CHASE, STRAFE, RETREAT }

var car: ArcadeCar = null
var get_enemies: Callable        # دالة ترجّع قائمة الأعداء المحتملين

@export var sight_range := 55.0
@export var strafe_range := 18.0    # يبدأ يلتف حوالين الهدف
@export var retreat_health := 25.0  # تحت هذا يهرب
@export var reaction := 0.15        # تأخير بشري بسيط

var _state: State = State.WANDER
var _target: Node3D = null
var _think_t := 0.0
var _wander_dir := Vector3.FORWARD
var _wander_t := 0.0
var _strafe_sign := 1.0
var _fire_t := 0.0
var _nuke_launch_t := 0.0


func _physics_process(delta: float) -> void:
	if car == null or not is_instance_valid(car) or not car.alive:
		return

	# لو تحمل السلاح النووي: تهرب من الأعداء وتطلقه بأسرع وقت
	if car.nuke_carrier:
		_choose_target()
		if _target != null and is_instance_valid(_target):
			# تهرب بعيد عن أقرب عدو
			var away := car.global_position - _target.global_position
			away.y = 0.0
			var goal := car.global_position + away.normalized() * 15.0
			goal.x = clampf(goal.x, -50, 50)
			goal.z = clampf(goal.z, -50, 50)
			car.ai_steer = _steer_towards(goal)
		car.ai_throttle = 1.0
		car.ai_boost = car.get_boost_ratio() > 0.15
		car.ai_drift = false
		car.ai_fire = false
		car.ai_special = false
		# يطلق النووي (يضغط زر التفجير) بعد فترة الحظر - الـ car يحوّله لإطلاق
		_nuke_launch_t += delta
		car.ai_detonate = _nuke_launch_t > 7.5   # ينتظر انتهاء فترة الحظر ثم يطلق
		return
	_nuke_launch_t = 0.0

	# الحالة الحرجة: يهجم على أقرب عدو ويفجّر نفسه
	if car.critical:
		car.ai_detonate = false
		_choose_target()
		if _target != null and is_instance_valid(_target):
			var to_t := _target.global_position - car.global_position
			car.ai_steer = _steer_towards(_target.global_position)
			car.ai_throttle = 1.0
			car.ai_boost = car.get_boost_ratio() > 0.1
			car.ai_drift = false
			# لو قرب كفاية من العدو، يفجّر فوراً!
			if to_t.length() < 6.0:
				car.ai_detonate = true
		else:
			car.ai_throttle = 0.3
		car.ai_fire = false
		car.ai_special = false
		return

	_think_t -= delta
	if _think_t <= 0.0:
		_think_t = reaction
		_choose_target()
		_choose_state()

	match _state:
		State.WANDER:
			_do_wander(delta)
		State.CHASE:
			_do_chase()
		State.STRAFE:
			_do_strafe(delta)
		State.RETREAT:
			_do_retreat()

	_do_combat(delta)


# ---------- القرارات ----------

func _choose_target() -> void:
	if not get_enemies.is_valid():
		return
	var best: Node3D = null
	var best_d := 1e9
	for e in get_enemies.call():
		if e == car or not is_instance_valid(e) or not e.alive:
			continue
		var d: float = car.global_position.distance_to(e.global_position)
		if d < best_d:
			best_d = d
			best = e
	_target = best


func _choose_state() -> void:
	if _target == null:
		_state = State.WANDER
		return
	var d := car.global_position.distance_to(_target.global_position)
	if d > sight_range:
		_state = State.WANDER
	elif car.health <= retreat_health:
		_state = State.RETREAT
	elif d <= strafe_range:
		_state = State.STRAFE
		if randf() < 0.02:
			_strafe_sign = -_strafe_sign
	else:
		_state = State.CHASE


# ---------- الحركة ----------

func _steer_towards(world_pos: Vector3) -> float:
	# نحسب زاوية الانعطاف المطلوبة نحو نقطة
	var to := world_pos - car.global_position
	to.y = 0.0
	if to.length() < 0.1:
		return 0.0
	var fwd := -car.global_transform.basis.z
	fwd.y = 0.0
	var right := car.global_transform.basis.x
	var side := right.dot(to.normalized())
	return clampf(side * 2.5, -1.0, 1.0)


func _do_wander(delta: float) -> void:
	_wander_t -= delta
	if _wander_t <= 0.0:
		_wander_t = randf_range(1.5, 3.5)
		var ang := randf() * TAU
		_wander_dir = Vector3(sin(ang), 0.0, cos(ang))
	var goal := car.global_position + _wander_dir * 10.0
	# نتجنب الخروج من الساحة
	if absf(car.global_position.x) > 52.0 or absf(car.global_position.z) > 52.0:
		goal = Vector3.ZERO
	car.ai_steer = _steer_towards(goal)
	car.ai_throttle = 0.55
	car.ai_drift = false
	car.ai_boost = false


func _do_chase() -> void:
	# نتوقع موقع الهدف قليلاً (يلاحق أذكى)
	var lead := _target.global_position
	if _target is RigidBody3D:
		lead += (_target as RigidBody3D).linear_velocity * 0.3
	car.ai_steer = _steer_towards(lead)
	car.ai_throttle = 1.0
	var d := car.global_position.distance_to(_target.global_position)
	car.ai_boost = d > 30.0 and car.get_boost_ratio() > 0.4   # يكبس نيترو لو بعيد
	car.ai_drift = absf(car.ai_steer) > 0.8 and d < 25.0


func _do_strafe(delta: float) -> void:
	# يلتف حوالين الهدف (يمين أو يسار) مع الحفاظ على مسافة
	var to_target := _target.global_position - car.global_position
	to_target.y = 0.0
	var d := to_target.length()
	var tangent := to_target.normalized().cross(Vector3.UP) * _strafe_sign
	var goal := car.global_position + tangent * 8.0
	if d < strafe_range * 0.6:
		goal -= to_target.normalized() * 5.0   # يبتعد شوي لو قرب زيادة
	car.ai_steer = _steer_towards(goal)
	car.ai_throttle = 0.85
	car.ai_drift = false
	car.ai_boost = false


func _do_retreat() -> void:
	# يهرب باتجاه معاكس للهدف ويكبس نيترو
	var away := car.global_position - _target.global_position
	away.y = 0.0
	var goal := car.global_position + away.normalized() * 15.0
	goal.x = clampf(goal.x, -50.0, 50.0)
	goal.z = clampf(goal.z, -50.0, 50.0)
	car.ai_steer = _steer_towards(goal)
	car.ai_throttle = 1.0
	car.ai_boost = car.get_boost_ratio() > 0.2
	car.ai_drift = false


# ---------- القتال ----------

func _do_combat(delta: float) -> void:
	car.ai_fire = false
	car.ai_special = false
	if _target == null or _state == State.WANDER or _state == State.RETREAT:
		return

	var to := _target.global_position - car.global_position
	var d := to.length()
	if d > car.gun_range:
		return

	# يطلق بس لو الهدف تقريباً قدامه ومو محجوب
	var fwd := -car.global_transform.basis.z
	var facing := fwd.dot(to.normalized())
	if facing < 0.9:
		return
	var from := car.global_transform * Vector3(0.0, 0.25, -1.25)
	var q := PhysicsRayQueryParameters3D.create(from, _target.global_position + Vector3.UP * 0.3)
	q.exclude = [car.get_rid()]
	var hit := car.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty() and hit["collider"] != _target:
		return

	# رشاش مستمر
	car.ai_fire = true

	# سلاح خاص أحياناً لو عنده ذخيرة والهدف قريب-متوسط
	_fire_t -= delta
	if _fire_t <= 0.0:
		_fire_t = randf_range(1.5, 3.0)
		if d < 40.0 and (car.ammo["rocket"] > 0 or car.ammo["homing"] > 0):
			car.ai_special = true
