class_name CarAI
extends Node

# ============================================================
#  دماغ الذكاء الاصطناعي لسيارة العدو
#  يتصرف كمصدر إدخال: يلاحق، يناور، يطلق، يهرب لما يتأذى
#  يعمل عبر ضبط متغيرات الإدخال بالسيارة مباشرة كل إطار
# ============================================================

enum State { WANDER, CHASE, STRAFE, RETREAT }

var car: ArcadeCar = null
var get_enemies: Callable
var get_score: Callable          # يرجع نقاط أي سيارة (للتنافس)
var difficulty := 2              # 1=سهل | 2=عادي | 3=صعب | 4=قاتل        # دالة ترجّع قائمة الأعداء المحتملين

@export var sight_range := 999.0     # 👁️ يشوف كل الخريطة - ما أكو مهرب
@export var strafe_range := 14.0     # يقرب أكثر قبل ما يلتف
@export var retreat_health := 0.0    # 💀 ما يهرب أبداً - يقاتل للموت
@export var reaction := 0.0          # صفر تأخير - رد فعل فوري

var _state: State = State.WANDER
var _target: Node3D = null
var _think_t := 0.0
var _wander_dir := Vector3.FORWARD
var _wander_t := 0.0
var _strafe_sign := 1.0
var _fire_t := 0.0
var _rocket_hold_t := 0.0
var _mortar_hold_t := 0.0
var _mine_t := 0.0
var _resupply_t := 7.0
var _stuck_t := 0.0
var _reversing_t := 0.0
var _reverse_steer := 1.0
var _front_clear := 99.0
var get_nuke: Callable
var _nuke_interest := 0.0
var _sense_t := 0.0
var _last_steer := 0.0
var _fire_gap := Vector2(0.7, 1.5)
var _aim_err := 0.0
var _resupply_gap := 7.0
var _charge_chance := 0.55
var _nuke_launch_t := 0.0


func apply_difficulty() -> void:
	match difficulty:
		1:  # 😴 سهل
			sight_range = 40.0
			reaction = 0.45
			_fire_gap = Vector2(2.2, 3.8)
			_aim_err = 0.35
			_resupply_gap = 16.0
			_charge_chance = 0.1
		2:  # 🙂 عادي
			sight_range = 70.0
			reaction = 0.22
			_fire_gap = Vector2(1.4, 2.6)
			_aim_err = 0.18
			_resupply_gap = 11.0
			_charge_chance = 0.3
		3:  # 😠 صعب
			sight_range = 140.0
			reaction = 0.08
			_fire_gap = Vector2(0.9, 1.8)
			_aim_err = 0.07
			_resupply_gap = 8.0
			_charge_chance = 0.5
		_:  # 💀 قاتل
			sight_range = 999.0
			reaction = 0.0
			_fire_gap = Vector2(0.6, 1.2)
			_aim_err = 0.0
			_resupply_gap = 6.0
			_charge_chance = 0.7


func _physics_process(delta: float) -> void:
	if car == null or not is_instance_valid(car) or not car.alive:
		return

	# 🔄 إعادة تزود تدريجي: ما تخلص ذخيرتهم = ضغط بلا توقف
	_resupply_t -= delta
	if _resupply_t <= 0.0:
		_resupply_t = _resupply_gap
		if car.ammo["rocket"] < 6:
			car.ammo["rocket"] += 1
		if car.ammo["homing"] < 6:
			car.ammo["homing"] += 1
		if car.ammo["mine"] < 4:
			car.ammo["mine"] += 1

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
			car.ai_steer = _smart_steer(goal)
		car.ai_throttle = 1.0
		car.ai_boost = car.get_boost_ratio() > 0.15
		car.ai_drift = false
		car.ai_fire = false
		car.ai_rocket = false
		car.ai_homing = false
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
		car.ai_rocket = false
		car.ai_homing = false
		return

	_think_t -= delta
	if _think_t <= 0.0:
		_think_t = reaction
		_choose_target()
		_choose_state()

	# ☢️ الصراع على النووي (أولوية عالية)
	if _handle_nuke(delta):
		return

	# 🔧 فك الانحشار له الأولوية على كل شي
	_update_stuck(delta)
	if _apply_reverse():
		_do_combat(delta)     # يظل يطلق وهو راجع
		return

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

# ☢️ سلوك النووي: يدمر الصندوق، ياخذ السلاح، ويطارد حامله
# يرجّع true لو تولّى القيادة هالإطار
func _handle_nuke(delta: float) -> bool:
	if not get_nuke.is_valid():
		return false
	var obj = get_nuke.call()          # الصندوق أو السلاح (أو null)
	if obj == null or not is_instance_valid(obj):
		_nuke_interest = 0.0
		return false

	# لو أنا حامل النووي: أهرب وأطلق (منطق موجود بالأعلى)
	if car.nuke_carrier:
		return false

	var d: float = car.global_position.distance_to(obj.global_position)

	# 🎯 قرار: أروح للنووي لو قريب أو لو ما عندي شي أفضل
	# (كل سيارة لها "شهية" مختلفة => بعضهم يروح للنووي وبعضهم يكمل قتال)
	if _nuke_interest <= 0.0:
		_nuke_interest = randf_range(0.35, 1.0)     # شهيته للنووي
	var want := _nuke_interest > 0.5 or d < 30.0

	# لو الهدف الحالي حامل نووي => نطارده بدل الصندوق
	if _target != null and is_instance_valid(_target) and _target.get("nuke_carrier"):
		return false     # المطاردة العادية تكفي (الاستهداف يعطيه +80)

	if not want:
		return false

	# 🚗 نسوق نحو النووي
	car.ai_steer = _smart_steer(obj.global_position)
	car.ai_throttle = 1.0 if _front_clear > 8.0 else 0.5
	car.ai_boost = car.get_boost_ratio() > 0.3 and _front_clear > 14.0 and d > 12.0
	car.ai_drift = false

	# 💥 لو صندوق: نضربه لين ما ينكسر
	if obj is NukeCrate:
		car.ai_fire = d < car.gun_range
		car.ai_rocket = false
		car.ai_homing = false
		# صاروخ أحياناً لتسريع التدمير
		_fire_t -= delta
		if _fire_t <= 0.0 and d < 45.0 and car.ammo["rocket"] > 0:
			_fire_t = randf_range(1.2, 2.2)
			_rocket_hold_t = 0.1
			car.ai_rocket = true
	else:
		# سلاح جاهز: نركض عليه (اللمس يلتقطه)
		car.ai_fire = false
		car.ai_rocket = false
		car.ai_homing = false
	return true


func _choose_target() -> void:
	if not get_enemies.is_valid():
		return
	# 🏆 اختيار تنافسي: يلاحق اللي يعطيه نقطة أسرع (مو الأقرب دائماً)
	var best: Node3D = null
	var best_score := -1e9
	for e in get_enemies.call():
		if e == car or not is_instance_valid(e) or not e.alive:
			continue
		var d: float = car.global_position.distance_to(e.global_position)
		if d > sight_range:
			continue          # خارج مدى الرؤية (حسب الصعوبة)
		var score := 0.0

		# القرب مهم بس مو كل شي
		score -= d * 1.0

		# 🩸 الجريح فريسة سهلة = نقطة سريعة (أهم عامل)
		var hp_ratio: float = e.health / maxf(e.max_health, 1.0)
		score += (1.0 - hp_ratio) * 55.0
		if hp_ratio < 0.3:
			score += 30.0        # على وشك الموت - انقض عليه!

		# 💀 بالحالة الحرجة = قتلة مضمونة
		if e.get("critical"):
			score += 45.0

		# 👑 المتصدر بالنقاط = تهديد، نوقفه
		if get_score.is_valid():
			var sc: int = get_score.call(e)
			score += float(sc) * 12.0

		# 🎯 ثبات: يفضّل يكمل على هدفه الحالي (ما يتشتت)
		if e == _target:
			score += 18.0

		# ☢️ حامل النووي أولوية قصوى
		if e.get("nuke_carrier"):
			score += 80.0

		if score > best_score:
			best_score = score
			best = e
	_target = best


func _choose_state() -> void:
	if _target == null:
		_state = State.WANDER
		return
	# 💀 لا هروب، لا رحمة: دائماً هجوم
	var d := car.global_position.distance_to(_target.global_position)
	if d <= strafe_range and randf() < 0.35:
		# أحياناً بس يلتف - وأغلب الوقت يهجم مباشرة
		_state = State.STRAFE
		if randf() < 0.02:
			_strafe_sign = -_strafe_sign
	else:
		_state = State.CHASE


# ---------- الحركة ----------

# ============================================================
#  🚗 نظام القيادة الخبيرة: استشعار العوائق + تفادي + فك الانحشار
# ============================================================

# يرمي شعاع ويرجّع المسافة الحرة (أو المدى الكامل لو صافي)
func _probe(dir: Vector3, dist: float) -> float:
	var space := car.get_world_3d().direct_space_state
	var from: Vector3 = car.global_position + Vector3.UP * 0.4
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * dist)
	q.exclude = [car.get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return dist
	return from.distance_to(hit["position"])


# 🧭 توجيه ذكي: يتفادى العوائق ويلگه أفضل طريق نحو الهدف
func _smart_steer(goal: Vector3) -> float:
	# ⚡ تحسين أداء: نعيد الحساب كل 0.05 ثانية (مو كل إطار)
	_sense_t -= get_physics_process_delta_time()
	if _sense_t > 0.0:
		return _last_steer
	_sense_t = 0.05
	_last_steer = _compute_smart_steer(goal)
	return _last_steer


func _compute_smart_steer(goal: Vector3) -> float:
	var fwd: Vector3 = -car.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right: Vector3 = car.global_transform.basis.x

	var to_goal: Vector3 = goal - car.global_position
	to_goal.y = 0.0
	var goal_dist := to_goal.length()
	if goal_dist < 0.5:
		return 0.0
	to_goal = to_goal.normalized()

	# مدى الاستشعار حسب السرعة (بسرعة عالية يشوف أبعد)
	var spd: float = Vector2(car.linear_velocity.x, car.linear_velocity.z).length()
	var look := clampf(6.0 + spd * 0.75, 7.0, 20.0)

	# نفحص 7 زوايا (من -70° إلى +70°) ونقيّم كل وحدة
	var best_angle := 0.0
	var best_score := -1e9
	var angles := [0.0, -20.0, 20.0, -40.0, 40.0, -65.0, 65.0]
	for a in angles:
		var dir: Vector3 = fwd.rotated(Vector3.UP, deg_to_rad(a))
		var clear := _probe(dir, look)
		# النقاط: المسافة الحرة (الأهم) + التوافق مع اتجاه الهدف
		var score := clear * 3.0
		score += dir.dot(to_goal) * 14.0
		score -= absf(a) * 0.05        # يفضّل المستقيم لو متساوي
		if clear < 3.0:
			score -= 60.0              # جدار قريب جداً - تجنبه
		if score > best_score:
			best_score = score
			best_angle = a

	# نوجّه نحو أفضل زاوية
	var target_dir: Vector3 = fwd.rotated(Vector3.UP, deg_to_rad(best_angle))
	var s: float = right.dot(target_dir)
	var f: float = fwd.dot(target_dir)
	var steer := clampf(s * 2.2, -1.0, 1.0)
	if f < 0.0:
		steer = signf(s) if absf(s) > 0.01 else 1.0
	_front_clear = _probe(fwd, look)
	return steer


# 🔧 كشف الانحشار: يدعس بنزين بس ما يتحرك => يرجع ويلف
func _update_stuck(delta: float) -> void:
	var spd: float = car.linear_velocity.length()
	# ننحشر لو نحاول نتحرك بس السرعة شبه صفر
	if _reversing_t > 0.0:
		_reversing_t -= delta
		return
	if absf(car.ai_throttle) > 0.3 and spd < 1.2:
		_stuck_t += delta
		if _stuck_t > 0.7:
			# انحشرنا! نرجع للخلف ونلف
			_reversing_t = randf_range(0.8, 1.4)
			_reverse_steer = 1.0 if randf() < 0.5 else -1.0
			# نلف نحو الجهة الأكثر انفتاحاً
			var fwd: Vector3 = -car.global_transform.basis.z
			var l := _probe(fwd.rotated(Vector3.UP, deg_to_rad(-90.0)), 8.0)
			var rgt := _probe(fwd.rotated(Vector3.UP, deg_to_rad(90.0)), 8.0)
			_reverse_steer = -1.0 if l > rgt else 1.0
			_stuck_t = 0.0
	else:
		_stuck_t = maxf(_stuck_t - delta * 2.0, 0.0)


# يطبّق الرجوع للخلف لو انحشرنا
func _apply_reverse() -> bool:
	if _reversing_t <= 0.0:
		return false
	car.ai_throttle = -1.0
	car.ai_steer = _reverse_steer     # يلف وهو راجع (يفك نفسه)
	car.ai_boost = false
	car.ai_drift = false
	return true


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
	var goal := car.global_position + _wander_dir * 12.0
	# نتجنب الخروج من الخريطة (الحدود حسب حجمها)
	var lim: float = float(Maps.get_map(Global.selected_map)["size"]) * 0.42
	if absf(car.global_position.x) > lim or absf(car.global_position.z) > lim:
		goal = Vector3.ZERO
	car.ai_steer = _smart_steer(goal)
	car.ai_throttle = 0.6 if _front_clear > 6.0 else 0.3
	car.ai_drift = false
	car.ai_boost = false


func _do_chase() -> void:
	# 🎯 توقّع دقيق لموقع الهدف (يقطع عليه الطريق)
	var d := car.global_position.distance_to(_target.global_position)
	var lead := _target.global_position
	if _target is RigidBody3D:
		var tv: Vector3 = (_target as RigidBody3D).linear_velocity
		# كل ما بعد الهدف، توقّع أبعد (اعتراض حقيقي)
		lead += tv * clampf(d / 28.0, 0.35, 1.4)
	# 🚗 قيادة خبيرة: يتفادى الحيطان وهو يطارد
	car.ai_steer = _smart_steer(lead)
	# سرعة حسب المساحة المفتوحة قدامه (يبطّئ قبل الجدار)
	if _front_clear < 5.0:
		car.ai_throttle = 0.35
	elif _front_clear < 9.0:
		car.ai_throttle = 0.7
	else:
		car.ai_throttle = 1.0
	# 🔥 نيترو بس لو الطريق مفتوح
	car.ai_boost = car.get_boost_ratio() > 0.15 and _front_clear > 14.0 and (d > 18.0 or d < 8.0)
	car.ai_drift = absf(car.ai_steer) > 0.7 and d < 25.0 and _front_clear > 7.0


func _do_strafe(delta: float) -> void:
	# يلتف حوالين الهدف (يمين أو يسار) مع الحفاظ على مسافة
	var to_target := _target.global_position - car.global_position
	to_target.y = 0.0
	var d := to_target.length()
	var tangent := to_target.normalized().cross(Vector3.UP) * _strafe_sign
	var goal := car.global_position + tangent * 8.0
	if d < strafe_range * 0.6:
		goal -= to_target.normalized() * 5.0   # يبتعد شوي لو قرب زيادة
	car.ai_steer = _smart_steer(goal)
	car.ai_throttle = 0.85 if _front_clear > 6.0 else 0.4
	car.ai_drift = false
	car.ai_boost = false


func _do_retreat() -> void:
	# يهرب باتجاه معاكس للهدف ويكبس نيترو
	var away := car.global_position - _target.global_position
	away.y = 0.0
	var goal := car.global_position + away.normalized() * 15.0
	goal.x = clampf(goal.x, -50.0, 50.0)
	goal.z = clampf(goal.z, -50.0, 50.0)
	car.ai_steer = _smart_steer(goal)
	car.ai_throttle = 1.0 if _front_clear > 6.0 else 0.4
	car.ai_boost = car.get_boost_ratio() > 0.2 and _front_clear > 12.0
	car.ai_drift = false


# ---------- القتال ----------

func _do_combat(delta: float) -> void:
	car.ai_fire = false
	car.ai_rocket = false
	car.ai_homing = false
	if _target == null or not is_instance_valid(_target):
		return

	var to := _target.global_position - car.global_position
	var d := to.length()
	var fwd := -car.global_transform.basis.z
	var facing := fwd.dot(to.normalized())

	# 👁️ فحص خط النار (يشوف الهدف؟)
	var clear := false
	if d <= car.gun_range:
		# نقطة آمنة داخل جسم السيارة (مو السبطانة اللي تخترق الجدران)
		var from := car.global_transform * Vector3(0.0, 0.35, -0.5)
		var q := PhysicsRayQueryParameters3D.create(from, _target.global_position + Vector3.UP * 0.3)
		q.exclude = [car.get_rid()]
		var hit := car.get_world_3d().direct_space_state.intersect_ray(q)
		clear = hit.is_empty() or hit["collider"] == _target

	# 🔫 رشاش: الدقة حسب الصعوبة
	if clear and facing > (0.55 + _aim_err):
		car.ai_fire = true

	_fire_t -= delta
	_mine_t -= delta

	# 🚀 استمرار شحن القاذف
	if _rocket_hold_t > 0.0:
		_rocket_hold_t -= delta
		car.ai_rocket = _rocket_hold_t > 0.0
		return

	# ☄️ استمرار وضع الهاون (ضغط متواصل على المتتبع)
	if _mortar_hold_t > 0.0:
		_mortar_hold_t -= delta
		car.ai_homing = _mortar_hold_t > 0.0
		return

	# 💣 لغم للمطاردين: لو أكو عدو وراه قريب، يزرع لغم
	if _mine_t <= 0.0 and car.ammo["mine"] > 0:
		var behind := _enemy_behind()
		if behind != null:
			_mine_t = randf_range(3.0, 5.0)
			car.ai_mine = true
			return
	car.ai_mine = false

	if _fire_t <= 0.0:
		# ⚡ إيقاع نار سريع (بدل 1.5-3 ثانية)
		_fire_t = randf_range(_fire_gap.x, _fire_gap.y)

		# ☄️ الهاون: لو الهدف بعيد أو محجوب (يضربه فوق العوائق!)
		if car.ammo["homing"] >= 3 and (not clear or d > 35.0) and randf() < 0.55:
			_mortar_hold_t = randf_range(1.2, 1.8)
			car.ai_homing = true
			return

		if not clear:
			return

		# 🚀 قاذف مشحون: كل ما زاد الشحن زاد الضرر
		if car.ammo["rocket"] > 0 and facing > 0.75 and randf() < 0.6:
			var charge_time := 0.1
			if car.ammo["rocket"] >= 3 and randf() < _charge_chance:
				charge_time = randf_range(1.0, 2.2)    # شحنة قاتلة x3-x5
			elif car.ammo["rocket"] >= 2 and randf() < 0.5:
				charge_time = randf_range(0.5, 0.9)
			_rocket_hold_t = charge_time
			car.ai_rocket = true
			return

		# 🔵 متتبع
		if car.ammo["homing"] > 0 and d < 55.0:
			car.ai_homing = true


# عدو قريب وراء السيارة؟ (للألغام)
func _enemy_behind() -> Node3D:
	if not get_enemies.is_valid():
		return null
	var back := car.global_transform.basis.z    # +Z = خلف
	for e in get_enemies.call():
		if e == car or not is_instance_valid(e) or not e.alive:
			continue
		var to: Vector3 = e.global_position - car.global_position
		var dist := to.length()
		if dist > 16.0:
			continue
		if back.dot(to.normalized()) > 0.6:
			return e
	return null
