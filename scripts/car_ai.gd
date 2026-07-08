class_name CarAI
extends Node

# ============================================================
#  دماغ الذكاء الاصطناعي لسيارة العدو (نسخة الزعيم - Boss AI)
#  تجنب جدران استباقي من مسافات بعيدة، وقتال هجومي مدمر!
# ============================================================

enum State { WANDER, CHASE, STRAFE, RETREAT }

var car: ArcadeCar = null
var get_enemies: Callable        

@export var sight_range := 10000.0   # رؤية لا نهائية
@export var strafe_range := 15.0    
@export var retreat_health := -1.0   # قتال حتى الموت
@export var reaction := 0.01         # رد فعل فوري تماماً

var _state: State = State.WANDER
var _target: Node3D = null
var _think_t := 0.0
var _wander_dir := Vector3.FORWARD
var _wander_t := 0.0
var _strafe_sign := 1.0
var _fire_t := 0.0
var _nuke_launch_t := 0.0

# --- متغيرات كشف الانحشار والقرارات ---
var _stuck_time := 0.0
var _is_reversing := false
var _reverse_time := 0.0

var _wanted_steer := 0.0
var _wanted_throttle := 0.0
var _wanted_boost := false
var _wanted_drift := false


func _physics_process(delta: float) -> void:
	if car == null or not is_instance_valid(car) or not car.alive:
		return

	_think_t -= delta
	if _think_t <= 0.0:
		_think_t = reaction
		_choose_target()
		_choose_state()

	if car.nuke_carrier:
		_handle_nuke_carrier(delta)
	elif car.critical:
		_handle_critical(delta)
	else:
		match _state:
			State.WANDER: _do_wander(delta)
			State.CHASE: _do_chase()
			State.STRAFE: _do_strafe(delta)
			State.RETREAT: _do_chase() 
		_do_combat(delta)

	# فلتر النجاة وتجنب الجدران (الرادار الطويل)
	_apply_obstacle_avoidance(delta)

	# فلتر الانحشار (اللحظي)
	_apply_stuck_recovery(delta)

	# تطبيق الأوامر
	car.ai_steer = _wanted_steer
	car.ai_throttle = _wanted_throttle
	car.ai_boost = _wanted_boost
	car.ai_drift = _wanted_drift


# ============================================================
#  نظام الرادار الذكي وتجنب الجدران (بعيد المدى)
# ============================================================
func _apply_obstacle_avoidance(delta: float) -> void:
	if _is_reversing:
		return

	var space_state = car.get_world_3d().direct_space_state
	var from = car.global_position + Vector3(0, 0.5, 0)
	var fwd = -car.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right = car.global_transform.basis.x
	
	var speed = car.linear_velocity.length()
	# زيادة طول الرادار بشكل كبير جداً ليكتشف الحائط من بعيد
	var ray_len = maxf(25.0, speed * 1.5) 
	
	# إطلاق 7 أشعة لتغطية جميع الزوايا الأمامية بدقة عالية
	var rays = [
		{"dir": fwd, "weight": 1.0, "steer": 2.5},                                
		{"dir": (fwd + right * 0.4).normalized(), "weight": 0.9, "steer": -2.0}, 
		{"dir": (fwd - right * 0.4).normalized(), "weight": 0.9, "steer": 2.0},  
		{"dir": (fwd + right * 0.8).normalized(), "weight": 0.7, "steer": -1.5},  
		{"dir": (fwd - right * 0.8).normalized(), "weight": 0.7, "steer": 1.5},
		{"dir": (fwd + right * 1.2).normalized(), "weight": 0.4, "steer": -1.0},  
		{"dir": (fwd - right * 1.2).normalized(), "weight": 0.4, "steer": 1.0}
	]
	
	var excludes = [car.get_rid()]
	if _target != null and is_instance_valid(_target) and _target is CollisionObject3D:
		excludes.append(_target.get_rid()) 

	var avoidance_steer := 0.0
	var danger_level := 0.0
	var hit_wall_front := false

	for r in rays:
		var q = PhysicsRayQueryParameters3D.create(from, from + r.dir * (ray_len * r.weight))
		q.exclude = excludes
		var hit = space_state.intersect_ray(q)
		
		if not hit.is_empty():
			var dist = from.distance_to(hit.position)
			var danger = 1.0 - (dist / (ray_len * r.weight))
			danger_level = maxf(danger_level, danger)
			avoidance_steer += r.steer * danger * 3.0 # استجابة توجيه عنيفة للهروب
			
			# إذا اكتشف جداراً من الأمام بمسافة متوسطة يبدأ بالتفاعل
			if r.weight == 1.0 and danger > 0.4:
				hit_wall_front = true

	# إذا استشعر أي خطر من بعيد
	if danger_level > 0.05:
		# يتجاهل أمر ملاحقة اللاعب بنسبة كبيرة ويركز على الانعطاف للنجاة
		_wanted_steer = clampf((_wanted_steer * 0.2) + avoidance_steer, -1.0, 1.0)
		_wanted_boost = false 
		
		# إذا اقترب الخطر، يستخدم التفحيط (Drift) للالتفاف بسرعة خيالية
		if danger_level > 0.3:
			_wanted_drift = speed > 10.0 
		
		# فرملة مبكرة إذا كان الحائط في الأمام مباشرة
		if hit_wall_front:
			_wanted_throttle = -1.0 
		else:
			# يخفف سرعته تدريجياً ليتجاوز المنعطف
			_wanted_throttle = clampf(1.0 - (danger_level * 1.5), 0.3, 1.0) 


# ============================================================
#  نظام كشف الانحشار (لحظي)
# ============================================================
func _apply_stuck_recovery(delta: float) -> void:
	var speed := car.linear_velocity.length()
	
	if _wanted_throttle > 0.5 and speed < 3.0 and not _is_reversing:
		_stuck_time += delta
		if _stuck_time > 0.4: # استجابة شبه لحظية للانحشار (0.4 ثانية فقط)
			_is_reversing = true
			_reverse_time = 1.2 
			_stuck_time = 0.0
	else:
		_stuck_time = maxf(0.0, _stuck_time - delta)

	if _is_reversing:
		_reverse_time -= delta
		_wanted_throttle = -1.0 
		if absf(_wanted_steer) < 0.3:
			_wanted_steer = -1.0 if randf() > 0.5 else 1.0 
		_wanted_boost = false
		_wanted_drift = false
		car.ai_fire = false
		if _reverse_time <= 0.0:
			_is_reversing = false


# ---------- القرارات والحالات ----------

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
	
	if d <= strafe_range:
		_state = State.STRAFE
		if randf() < 0.15: 
			_strafe_sign = -_strafe_sign
	else:
		_state = State.CHASE 


func _get_steer_towards(world_pos: Vector3) -> float:
	var to := world_pos - car.global_position
	to.y = 0.0
	if to.length() < 0.1:
		return 0.0
	var fwd := -car.global_transform.basis.z
	fwd.y = 0.0
	var right := car.global_transform.basis.x
	var side := right.dot(to.normalized())
	return clampf(side * 5.0, -1.0, 1.0) # توجيه خارق الدقة


# ---------- منطق الحركة ----------

func _do_wander(delta: float) -> void:
	_wander_t -= delta
	if _wander_t <= 0.0:
		_wander_t = randf_range(1.0, 2.0)
		var ang := randf() * TAU
		_wander_dir = Vector3(sin(ang), 0.0, cos(ang))
	var goal := car.global_position + _wander_dir * 20.0
	
	if absf(car.global_position.x) > 52.0 or absf(car.global_position.z) > 52.0:
		goal = Vector3.ZERO
		
	_wanted_steer = _get_steer_towards(goal)
	_wanted_throttle = 1.0 
	_wanted_drift = false
	_wanted_boost = false


func _do_chase() -> void:
	var lead := _target.global_position
	var distance := car.global_position.distance_to(lead)
	
	if _target is RigidBody3D:
		var target_vel = (_target as RigidBody3D).linear_velocity
		var my_speed = maxf(car.linear_velocity.length(), 10.0)
		var time_to_reach = distance / my_speed
		lead += target_vel * clampf(time_to_reach * 1.3, 0.0, 3.0) # يتوقع حركتك المستقبلية بامتياز

	_wanted_steer = _get_steer_towards(lead)
	_wanted_throttle = 1.0
	
	var fwd := -car.global_transform.basis.z
	var facing := fwd.dot((lead - car.global_position).normalized())
	
	if facing > 0.8:
		_wanted_boost = car.get_boost_ratio() > 0.05
	else:
		_wanted_boost = false
		
	_wanted_drift = absf(_wanted_steer) > 0.5 and car.linear_velocity.length() > 18.0


func _do_strafe(delta: float) -> void:
	var to_target := _target.global_position - car.global_position
	to_target.y = 0.0
	var d := to_target.length()
	var tangent := to_target.normalized().cross(Vector3.UP) * _strafe_sign
	var goal := car.global_position + tangent * 6.0 + to_target.normalized() * 8.0 
	
	_wanted_steer = _get_steer_towards(goal)
	_wanted_throttle = 1.0
	_wanted_boost = car.get_boost_ratio() > 0.1 
	_wanted_drift = absf(_wanted_steer) > 0.7 and car.linear_velocity.length() > 15.0


func _handle_nuke_carrier(delta: float) -> void:
	_choose_target()
	if _target != null and is_instance_valid(_target):
		var away := car.global_position - _target.global_position
		away.y = 0.0
		var goal := car.global_position + away.normalized() * 20.0
		goal.x = clampf(goal.x, -50, 50)
		goal.z = clampf(goal.z, -50, 50)
		_wanted_steer = _get_steer_towards(goal)
	
	_wanted_throttle = 1.0
	_wanted_boost = car.get_boost_ratio() > 0.15
	_wanted_drift = false
	car.ai_fire = false
	car.ai_special = false
	_nuke_launch_t += delta
	car.ai_detonate = _nuke_launch_t > 7.5   


func _handle_critical(delta: float) -> void:
	car.ai_detonate = false
	_choose_target()
	if _target != null and is_instance_valid(_target):
		var to_t := _target.global_position - car.global_position
		_wanted_steer = _get_steer_towards(_target.global_position)
		_wanted_throttle = 1.0
		_wanted_boost = car.get_boost_ratio() > 0.02 
		_wanted_drift = false
		if to_t.length() < 15.0: # ينفجر من مسافة أبعد لضمان تدميرك
			car.ai_detonate = true
	else:
		_wanted_throttle = 1.0
	car.ai_fire = false
	car.ai_special = false


# ---------- القتال الشرس ----------

func _do_combat(delta: float) -> void:
	car.ai_fire = false
	car.ai_special = false
	
	# يرمي ألغام حتى لو كنت بعيداً نسبياً خلفه (مسافة 50 متراً!)
	if _target != null and is_instance_valid(_target) and "ai_mine" in car:
		var to_target = _target.global_position - car.global_position
		var fwd = -car.global_transform.basis.z
		if fwd.dot(to_target.normalized()) < -0.3 and to_target.length() < 50.0:
			if car.ammo.has("mine") and car.ammo["mine"] > 0:
				car.set("ai_mine", true) 

	if _target == null or _state == State.WANDER:
		return

	var to := _target.global_position - car.global_position
	var d := to.length()
	if d > car.gun_range:
		return

	var fwd := -car.global_transform.basis.z
	var facing := fwd.dot(to.normalized())
	if facing < 0.5: # يطلق النار حتى بزوايا واسعة جداً
		return
		
	var from := car.global_transform * Vector3(0.0, 0.25, -1.25)
	var q := PhysicsRayQueryParameters3D.create(from, _target.global_position + Vector3.UP * 0.3)
	q.exclude = [car.get_rid()]
	var hit := car.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty() and hit["collider"] != _target:
		return

	car.ai_fire = true 

	_fire_t -= delta
	if _fire_t <= 0.0:
		_fire_t = randf_range(0.2, 0.8) # يطلق الأسلحة الخاصة كالمجنون
		if d < 70.0 and (car.ammo["rocket"] > 0 or car.ammo["homing"] > 0):
			car.ai_special = true