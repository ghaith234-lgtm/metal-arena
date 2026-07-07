class_name Radar
extends Control

# ============================================================
#  رادار (خريطة مصغرة): يبين اللاعب بالوسط والأعداء نقاط حمرا
#  يدور مع اتجاه اللاعب حتى "فوق" دائماً قدام السيارة
# ============================================================

var player: Node3D = null
var enemies: Array = []          # قائمة عقد الأعداء
var objective: Node3D = null     # هدف خاص (السلاح النووي) يبين أصفر
var world_range := 70.0          # نصف قطر ما يغطيه الرادار بالعالم

var _radius := 90.0


func _ready() -> void:
	custom_minimum_size = Vector2(190, 190)
	set_process(true)


func setup(p: Node3D, foes: Array) -> void:
	player = p
	enemies = foes


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var center := size / 2.0
	_radius = minf(size.x, size.y) / 2.0 - 6.0

	# خلفية دائرية
	draw_circle(center, _radius, Color(0.05, 0.08, 0.1, 0.55))
	draw_arc(center, _radius, 0.0, TAU, 48, Color(0.3, 0.8, 0.5, 0.6), 2.0)
	# خطوط تقاطع
	draw_line(center - Vector2(_radius, 0), center + Vector2(_radius, 0), Color(0.3, 0.8, 0.5, 0.15), 1.0)
	draw_line(center - Vector2(0, _radius), center + Vector2(0, _radius), Color(0.3, 0.8, 0.5, 0.15), 1.0)

	if player == null or not is_instance_valid(player):
		return

	# زاوية اللاعب حتى نلف الرادار (اتجاه السيارة للأعلى)
	var fwd := -player.global_transform.basis.z
	var yaw := atan2(fwd.x, fwd.z)

	# اللاعب سهم بالوسط
	_draw_player_arrow(center)

	# الأعداء
	for e in enemies:
		if not is_instance_valid(e) or not e.get("alive"):
			continue
		var rel: Vector3 = e.global_position - player.global_position
		var dist := Vector2(rel.x, rel.z).length()
		# تحويل للإحداثيات المحلية للرادار (مع الدوران)
		var lx := rel.x * cos(-yaw) - rel.z * sin(-yaw)
		var lz := rel.x * sin(-yaw) + rel.z * cos(-yaw)
		var screen := Vector2(lx, lz) / world_range * _radius
		var clamped := screen
		var on_edge := false
		if screen.length() > _radius - 6.0:
			clamped = screen.normalized() * (_radius - 6.0)
			on_edge = true
		var dot_pos := center + clamped
		var col := Color(0.95, 0.25, 0.2) if not on_edge else Color(0.95, 0.55, 0.2)
		draw_circle(dot_pos, 5.0 if not on_edge else 4.0, col)

	# الهدف الخاص (النووي) نقطة صفراء نابضة
	if objective != null and is_instance_valid(objective):
		var rel: Vector3 = objective.global_position - player.global_position
		var lx := rel.x * cos(-yaw) - rel.z * sin(-yaw)
		var lz := rel.x * sin(-yaw) + rel.z * cos(-yaw)
		var screen := Vector2(lx, lz) / world_range * _radius
		if screen.length() > _radius - 6.0:
			screen = screen.normalized() * (_radius - 6.0)
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
		draw_circle(center + screen, 6.0 + pulse * 3.0, Color(1.0, 0.85, 0.1, 0.7 + pulse * 0.3))


func _draw_player_arrow(center: Vector2) -> void:
	var pts := PackedVector2Array([
		center + Vector2(0, -9),
		center + Vector2(-6, 7),
		center + Vector2(6, 7),
	])
	draw_colored_polygon(pts, Color(0.3, 0.9, 1.0))
