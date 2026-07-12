extends Node3D

# ============================================================
#  المشهد الرئيسي - المرحلة 4
#  ساحة + أهداف + صناديق أسلحة عشوائية + HUD موسع
# ============================================================

const ARENA_SIZE := 120.0

var _dummy_spots: Array = DUMMY_SPOTS
var _pickup_range := 48.0
var _water_areas: Array = []
var _terrain: Terrain = null

const DUMMY_SPOTS = [
	Vector3(-12.0, 1.5, -14.0),
	Vector3(16.0, 1.5, 6.0),
	Vector3(-24.0, 1.5, 20.0),
	Vector3(8.0, 1.5, -26.0),
]

const DUMMY_COLORS = [
	Color(0.2, 0.5, 0.9),
	Color(0.2, 0.75, 0.35),
	Color(0.85, 0.65, 0.15),
	Color(0.6, 0.3, 0.8),
]

const PICKUP_KINDS = ["rocket", "homing", "mine", "shield", "repair", "rocket", "mine", "homing", "shield", "repair"]
const SPECIAL_NAMES = {"rocket": "قاذف", "homing": "متتبع", "mine": "لغم"}
const SPECIAL_CODES = {"rocket": "R", "homing": "H", "mine": "M"}

var car: ArcadeCar
var controls: TouchControls
var _cam: ChaseCamera
var _weather: Weather
var _nuke: NukeEvent
var _nuke_flash_rect: ColorRect
var _hit_vignette: ColorRect
var _nuke_timer_label: Label
var _countdown_label: Label
var _announce_label: Label
var _announce_time := 0.0
var _headlight_check := 0.0
var _projector_lights: Array = []
var _projector_mats: Array = []
var _projectors_on := false
var _radar: Radar
var _lock_marker: Control
var _lock_off_screen := false
var _shield_label: Label
var _dummies: Array = []
var _speed_label: Label
var _kills_label: Label
var _ammo_label: Label
var _center_label: Label
var _drift_label: Label
var _hitmarker: Label
var _hp_fill: ColorRect
var _boost_fill: ColorRect
var _kills := 0
var SCORE_TO_WIN := 8           # 🏆 يحدده اللاعب بشاشة الميدان
var _enemy_scores := {}          # قتلات كل عدو
var _deaths := {}                # موتات كل سيارة (اللاعب والأعداء)
var _player_deaths := 0
var _scoreboard: Control = null   # 📊 جدول النقاط
var _match_over := false
var _result_panel: Panel = null
var _ui_layer: CanvasLayer = null
var _last_hp := 100.0
var _marker_time := 0.0
var _drift_time := 0.0


func _ready() -> void:
	SCORE_TO_WIN = Global.score_to_win
	# نبني الأساسيات أولاً (بيئة + كاميرا) حتى لو فشل شي بعدها يبقى المشهد ظاهر
	_build_environment()
	_build_arena()
	_build_ui()
	_spawn_player()
	_spawn_camera()          # الكاميرا مبكراً حتى ما تصير الشاشة رمادية
	_spawn_dummies()
	_spawn_pickups()
	Fx.boom.connect(_on_boom)
	if _weather != null and car != null:
		_weather.set_follow(car)
	_setup_nuke_event()
	_refresh_ammo()
	_build_scoreboard()
	_start_countdown()


func _setup_nuke_event() -> void:
	_nuke = NukeEvent.new()
	_nuke.get_cars = _get_all_cars
	add_child(_nuke)
	_nuke.announce.connect(_on_nuke_announce)
	_nuke.nuke_flash.connect(_on_nuke_flash)


func _get_all_cars() -> Array:
	var list: Array = []
	if car != null and is_instance_valid(car):
		list.append(car)
	for d in _dummies:
		if is_instance_valid(d):
			list.append(d)
	return list


func _process(delta: float) -> void:
	if car != null and _speed_label != null:
		_speed_label.text = "%d km/h" % roundi(car.get_speed_kmh())
	if _marker_time > 0.0:
		_marker_time -= delta
		if _marker_time <= 0.0:
			_hitmarker.visible = false
	if _drift_time > 0.0:
		_drift_time -= delta
		_drift_label.modulate.a = clampf(_drift_time / 0.5, 0.0, 1.0)
		if _drift_time <= 0.0:
			_drift_label.visible = false
	_update_lock_marker()
	_update_nuke_hud(delta)
	_update_mine_hud()
	_update_headlights(delta)
	# نحدّث هدف الرادار (النووي)
	if _radar != null and _nuke != null:
		_radar.objective = _nuke.get_objective()


func _update_headlights(delta: float) -> void:
	_headlight_check -= delta
	if _headlight_check > 0.0:
		return
	_headlight_check = 1.0
	# الأضواء دائماً مشتغلة (سيارات + بروجيكتر)
	if car != null and is_instance_valid(car):
		car.set_headlights(true)
	for d in _dummies:
		if is_instance_valid(d):
			d.set_headlights(true)
	if not _projectors_on:
		_projectors_on = true
		for spot in _projector_lights:
			spot.light_energy = 2.5
		for lm in _projector_mats:
			lm.emission_energy_multiplier = 3.0
	# عدّاد الدرع
	if car != null and car.shield_time > 0.0:
		_shield_label.visible = true
		_shield_label.text = "🛡 درع %.1f" % car.shield_time
	elif _shield_label.visible:
		_shield_label.visible = false


func _update_lock_marker() -> void:
	if car == null or _cam == null or _lock_marker == null:
		return
	# 🎯 دائماً على أقرب عدو - حتى لو وراك
	var tgt: Node3D = car.lock_target
	if tgt == null or not is_instance_valid(tgt) or not car.alive:
		_lock_marker.visible = false
		return
	var world: Vector3 = tgt.global_position + Vector3.UP * 0.4
	var vp := get_viewport().get_visible_rect().size
	var behind: bool = _cam.is_position_behind(world)
	var screen: Vector2 = _cam.unproject_position(world)
	if behind:
		# ورا الكاميرا: نعكس ونثبته بحافة الشاشة
		screen = vp * 0.5 + (vp * 0.5 - screen)
	# نثبته داخل حدود الشاشة (سهم حافة)
	var margin := 42.0
	var clamped := Vector2(
		clampf(screen.x, margin, vp.x - margin),
		clampf(screen.y, margin, vp.y - margin))
	_lock_off_screen = behind or clamped != screen
	_lock_marker.position = clamped - _lock_marker.size / 2.0
	_lock_marker.visible = true
	_lock_marker.queue_redraw()


func _draw_lock_marker() -> void:
	var s := _lock_marker.size
	var c := Color(1.0, 0.55, 0.15) if _lock_off_screen else Color(1.0, 0.3, 0.25)
	if _lock_off_screen:
		# دائرة نابضة تدل على عدو خارج الرؤية
		var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.012)
		_lock_marker.draw_arc(s * 0.5, s.x * 0.42, 0.0, TAU, 24, Color(1.0, 0.5, 0.1, pulse), 3.0)
	var L := 14.0
	# أربع زوايا بركِت
	var corners := [
		[Vector2(0, 0), Vector2(L, 0), Vector2(0, L)],
		[Vector2(s.x, 0), Vector2(s.x - L, 0), Vector2(s.x, L)],
		[Vector2(0, s.y), Vector2(L, s.y), Vector2(0, s.y - L)],
		[Vector2(s.x, s.y), Vector2(s.x - L, s.y), Vector2(s.x, s.y - L)],
	]
	for cr in corners:
		_lock_marker.draw_line(cr[0], cr[1], c, 3.0)
		_lock_marker.draw_line(cr[0], cr[2], c, 3.0)


# ---------- السماء والإضاءة ----------

func _build_environment() -> void:
	_weather = Weather.new()
	add_child(_weather)
	# ⛅ الطقس: اختيار اللاعب أو عشوائي
	if Global.time_of_day < 0.0 and Global.rain < 0:
		_weather.randomize_weather()
	else:
		_weather.randomize_weather()
		if Global.time_of_day >= 0.0:
			_weather.time_of_day = Global.time_of_day
		if Global.rain >= 0:
			_weather.rain_enabled = Global.rain == 1
		_weather.apply_now()


# ---------- الساحة ----------

func _build_arena() -> void:
	var m: Dictionary = Maps.get_map(Global.selected_map)
	var size: float = m["size"]
	var half := size / 2.0
	_pickup_range = m["pickup_range"]

	# مواقع بداية الأعداء (من الملف)
	var sp: Array = m["spawns"]
	if sp.size() >= 4:
		_dummy_spots = []
		for s in sp:
			_dummy_spots.append(Vector3(float(s[0]), 1.5, float(s[1])))

	# 🏔️ الأرضية: تضاريس (لو مفعّلة) أو مسطحة
	var tcfg: Dictionary = m["terrain"]
	if not tcfg.is_empty() and bool(tcfg.get("enabled", true)):
		_build_terrain(tcfg, m, size)
	else:
		_add_ground(Vector3(0, -0.5, 0), Vector3(size, 1.0, size), m["ground_color"])

	# بقع تراب طبيعية
	var patches: int = m["dirt_patches"]
	for k in patches:
		var lim := half * 0.82
		_add_ground(Vector3(randf_range(-lim, lim), 0.015, randf_range(-lim, lim)),
			Vector3(randf_range(8.0, 16.0), 0.03, randf_range(8.0, 16.0)), Color(0.4, 0.33, 0.22))

	# 🛣️ الشوارع: أسفلت منخفض + أرصفة مرتفعة بحواف
	var road_c := Color(0.19, 0.19, 0.21)
	var line_c := Color(0.88, 0.84, 0.35)
	var curb_c := Color(0.62, 0.62, 0.66)      # حافة الرصيف (فاتحة)
	var walk_c := Color(0.52, 0.52, 0.55)      # سطح الرصيف
	var rw: float = m["road_width"]
	var road_y := 0.03                          # الأسفلت فوق الأرض بشعرة
	var walk_h := 0.24                          # ارتفاع الرصيف الظاهر
	var walk_deep := 0.9                        # عمق القاعدة (يكفي لسد الفجوات)
	var walk_w: float = float(m.get("sidewalk_width", 2.6))
	var half_r := rw * 0.5

	# الأسفلت (طبقة رقيقة فوق الأرض المسطحة)
	for rx in m["roads_x"]:
		_add_ground(Vector3(float(rx), road_y, 0), Vector3(rw, 0.06, size), road_c, true)
	for rz in m["roads_z"]:
		_add_ground(Vector3(0, road_y, float(rz)), Vector3(size, 0.06, rw), road_c, true)

	# 🛣️ الأرصفة: مقاطع تتوقف عند التقاطعات (ما تقطع الشوارع)
	var sides: Array[float] = [-1.0, 1.0]
	var walk_size := Vector3(walk_w, walk_h + walk_deep, 0.0)
	var curb_size := Vector3(0.22, walk_h + walk_deep, 0.0)
	# مركز الصندوق: نص الارتفاع الظاهر ناقص نص العمق => القاعدة تغوص
	var wy := walk_h * 0.5 - walk_deep * 0.5

	# أرصفة الشوارع العمودية (مقاطع بين التقاطعات)
	var segs_z: Array = _road_segments(m["roads_z"], rw, half, walk_w)
	for rx in m["roads_x"]:
		var rxf: float = float(rx)
		for sg in segs_z:
			var z0: float = float(sg[0])
			var z1: float = float(sg[1])
			var seg_len: float = z1 - z0
			var zc: float = (z0 + z1) * 0.5
			for side in sides:
				var cx: float = rxf + side * (half_r + walk_w * 0.5)
				_add_box(Vector3(cx, wy, zc), Vector3(walk_w, walk_size.y, seg_len), walk_c)
				_add_box(Vector3(rxf + side * half_r, wy, zc), Vector3(0.22, curb_size.y, seg_len), curb_c)

	# أرصفة الشوارع الأفقية (مقاطع بين التقاطعات)
	var segs_x: Array = _road_segments(m["roads_x"], rw, half, walk_w)
	for rz in m["roads_z"]:
		var rzf: float = float(rz)
		for sg2 in segs_x:
			var x0: float = float(sg2[0])
			var x1: float = float(sg2[1])
			var seg_len2: float = x1 - x0
			var xc: float = (x0 + x1) * 0.5
			for side2 in sides:
				var cz: float = rzf + side2 * (half_r + walk_w * 0.5)
				_add_box(Vector3(xc, wy, cz), Vector3(seg_len2, walk_size.y, walk_w), walk_c)
				_add_box(Vector3(xc, wy, rzf + side2 * half_r), Vector3(seg_len2, curb_size.y, 0.22), curb_c)

	# 🔲 زوايا التقاطعات: نملأ الأركان بالضبط (بلا أي فجوة تدخلها السيارة)
	# منطقة التقاطع تمتد لـ (half_r + walk_w + 0.15) - نخلي الركن يوصلها تماماً
	var corner_w: float = walk_w + 0.15 + 0.3        # هامش زيادة للأمان (تداخل بسيط)
	var corner_c: float = half_r + corner_w * 0.5
	for rx2 in m["roads_x"]:
		var ix: float = float(rx2)
		for rz2 in m["roads_z"]:
			var iz: float = float(rz2)
			for sx in sides:
				for sz in sides:
					var kx: float = ix + sx * corner_c
					var kz: float = iz + sz * corner_c
					# قطعة رصيف بالركن (تتداخل مع المقاطع = بلا فجوة)
					_add_box(Vector3(kx, wy, kz), Vector3(corner_w, walk_size.y, corner_w), walk_c)
					# حافتان تكملان الكيرب حول الركن
					_add_box(Vector3(ix + sx * half_r, wy, kz), Vector3(0.22, curb_size.y, corner_w), curb_c)
					_add_box(Vector3(kx, wy, iz + sz * half_r), Vector3(corner_w, curb_size.y, 0.22), curb_c)

	# خطوط منتصف الشارع (على الأسفلت المنخفض)
	var lines := int(half / 10.0)
	for rx in m["roads_x"]:
		for i in range(-lines, lines + 1):
			_add_ground(Vector3(float(rx), road_y + 0.04, i * 10.0), Vector3(0.4, 0.02, 3.0), line_c)
	for rz in m["roads_z"]:
		for i in range(-lines, lines + 1):
			_add_ground(Vector3(i * 10.0, road_y + 0.04, float(rz)), Vector3(3.0, 0.02, 0.4), line_c)

	# الجدران المحيطة
	var wh: float = m["wall_height"]
	var wall_c := Color(0.4, 0.42, 0.48)
	_add_box(Vector3(0, wh * 0.5, -half), Vector3(size + 4.0, wh, 2.0), wall_c)
	_add_box(Vector3(0, wh * 0.5, half), Vector3(size + 4.0, wh, 2.0), wall_c)
	_add_box(Vector3(-half, wh * 0.5, 0), Vector3(2.0, wh, size + 4.0), wall_c)
	_add_box(Vector3(half, wh * 0.5, 0), Vector3(2.0, wh, size + 4.0), wall_c)

	# المنحدرات
	var ramp_c := Color(0.7, 0.6, 0.25)
	for ramp in m["ramps"]:
		var rp: Array = ramp.get("pos", [0, 0])
		var rs: Array = ramp.get("size", [8, 7])
		var tilt: float = float(ramp.get("tilt", -16.0))
		var yaw: float = float(ramp.get("yaw", 0.0))
		_add_box(Vector3(float(rp[0]), 0.85, float(rp[1])),
			Vector3(float(rs[0]), 0.5, float(rs[1])), ramp_c, Vector3(tilt, yaw, 0.0))

	# الجبال
	for mt in m["mountains"]:
		var mp: Array = mt.get("pos", [0, 0])
		_spawn_mountain(Vector3(float(mp[0]), 0, float(mp[1])), float(mt.get("scale", 2.0)))

	# الحفر
	for pit in m["pits"]:
		var pp: Array = pit.get("pos", [0, 0])
		_build_pit(Vector3(float(pp[0]), 0, float(pp[1])), float(pit.get("radius", 8.0)))

	# المباني والأشجار والبراميل
	for b in m["buildings"]:
		var kind := Destructible.Kind.BUILDING_TALL if String(b[2]) == "tall" else Destructible.Kind.BUILDING_SMALL
		var bx := float(b[0])
		var bz := float(b[1])
		# 🚫 ممنوع بالشارع (المبنى عرضه ~13م => هامش 8م)
		if _on_road(bx, bz, m, 8.0):
			push_warning("[Map] مبنى بالشارع - تم تخطيه: (%.0f, %.0f)" % [bx, bz])
			continue
		_add_destructible(Vector3(bx, ground_y(bx, bz), bz), kind)
	# 🏙️ مدن عشوائية (توزيع طبيعي مو مربع)
	for city in m["random_cities"]:
		_spawn_random_city(city, m)

	# 🎨 نماذج مخصصة من مجلد الخريطة (أشجار، مباني، أي glb تنزله!)
	for pr in m["props"]:
		var pp: Array = pr.get("pos", [0, 0])
		# 🚫 الصلبة ممنوعة بالشارع (الديكور مسموح)
		if bool(pr.get("solid", true)) and _on_road(float(pp[0]), float(pp[1]), m, 1.5):
			continue
		_spawn_prop(pr)

	for t in m["trees"]:
		var tx := float(t[0])
		var tz := float(t[1])
		# 🚫 ممنوع بالشارع
		if _on_road(tx, tz, m, 1.2):
			continue
		_add_destructible(Vector3(tx, ground_y(tx, tz), tz), Destructible.Kind.TREE)
	for br in m["barrels"]:
		var ox := float(br[0])
		var oz := float(br[1])
		if _on_road(ox, oz, m, 0.8):
			continue
		_add_destructible(Vector3(ox, ground_y(ox, oz), oz), Destructible.Kind.BARREL)
	var rb: int = m["random_barrels"]
	for k in rb:
		var lim2 := half * 0.78
		var qx := randf_range(-lim2, lim2)
		var qz := randf_range(-lim2, lim2)
		if _on_road(qx, qz, m, 0.8):
			continue
		_add_destructible(Vector3(qx, ground_y(qx, qz), qz), Destructible.Kind.BARREL)

	# 🌊 البحيرات (تبطّئ السيارة وترشّ ماي)
	for w in m["water"]:
		var wp: Array = w.get("pos", [0, 0])
		var ws: Array = w.get("size", [20, 20])
		_build_water(Vector3(float(wp[0]), 0, float(wp[1])), float(ws[0]), float(ws[1]))

	# 🌉 الجسور (منحدر صعود + سطح + منحدر نزول)
	for bg in m["bridges"]:
		var bp: Array = bg.get("pos", [0, 0])
		_build_bridge(Vector3(float(bp[0]), 0, float(bp[1])), float(bg.get("length", 30.0)),
			float(bg.get("width", 10.0)), float(bg.get("height", 4.0)), float(bg.get("yaw", 0.0)))

	# 🚇 الأنفاق (ممر مسقوف تمر بيه)
	for tn in m["tunnels"]:
		var tp: Array = tn.get("pos", [0, 0])
		_build_tunnel(Vector3(float(tp[0]), 0, float(tp[1])), float(tn.get("length", 24.0)),
			float(tn.get("width", 9.0)), float(tn.get("height", 4.0)), float(tn.get("yaw", 0.0)))

	# 🚧 الحواجز (جدران قصيرة للتغطية)
	for bar in m["barriers"]:
		var brp: Array = bar.get("pos", [0, 0])
		var brs: Array = bar.get("size", [6, 1])
		_add_box(Vector3(float(brp[0]), 0.6, float(brp[1])),
			Vector3(float(brs[0]), 1.2, float(brs[1])), Color(0.55, 0.5, 0.42),
			Vector3(0, float(bar.get("yaw", 0.0)), 0))

	_build_projectors()


# 🌊 بحيرة: سطح ماء شفاف + منطقة تبطئة
# 🏙️ مدينة عشوائية: مباني بمواقع وزوايا طبيعية بدون تداخل
func _spawn_random_city(city: Dictionary, m: Dictionary) -> void:
	var c: Array = city.get("center", [0, 0])
	var cx := float(c[0])
	var cz := float(c[1])
	var rad := float(city.get("radius", 40.0))
	var count := int(city.get("count", 14))
	var tall_ratio := float(city.get("tall_ratio", 0.4))
	var min_gap := float(city.get("min_gap", 11.0))
	var road_clear := float(city.get("road_clear", 7.0))
	var jitter := float(city.get("rotate", 25.0))   # زاوية دوران عشوائية للمباني

	var half: float = float(m["size"]) * 0.5
	var rw: float = float(m["road_width"]) * 0.5 + float(m["sidewalk_width"]) + road_clear
	var placed: Array = []

	var tries := 0
	while placed.size() < count and tries < count * 40:
		tries += 1
		# توزيع دائري (أكثف بالمركز = يشبه المدن الحقيقية)
		var ang := randf() * TAU
		var dist: float = rad * sqrt(randf())
		var px := cx + cos(ang) * dist
		var pz := cz + sin(ang) * dist

		# داخل حدود الخريطة؟
		if absf(px) > half - 10.0 or absf(pz) > half - 10.0:
			continue

		# بعيد عن الشوارع؟
		var on_road := false
		for rx in m["roads_x"]:
			if absf(px - float(rx)) < rw:
				on_road = true
				break
		if not on_road:
			for rz in m["roads_z"]:
				if absf(pz - float(rz)) < rw:
					on_road = true
					break
		if on_road:
			continue

		# بعيد عن باقي المباني؟
		var clash := false
		for p in placed:
			if Vector2(px, pz).distance_to(p) < min_gap:
				clash = true
				break
		if clash:
			continue

		# بعيد عن نقاط بداية الأعداء؟
		var near_spawn := false
		for s in _dummy_spots:
			if Vector2(px, pz).distance_to(Vector2(s.x, s.z)) < 12.0:
				near_spawn = true
				break
		if near_spawn:
			continue

		placed.append(Vector2(px, pz))
		var kind := Destructible.Kind.BUILDING_TALL if randf() < tall_ratio else Destructible.Kind.BUILDING_SMALL
		var d := _add_destructible(Vector3(px, ground_y(px, pz), pz), kind)
		# زاوية عشوائية => يكسر شكل المربع
		if d != null and jitter > 0.0:
			d.rotation.y = deg_to_rad(randf_range(-jitter, jitter))


# 🎨 نموذج مخصص (glb من مجلد content/props/)
func _spawn_prop(pr: Dictionary) -> void:
	var file: String = pr.get("model", "")
	if file == "":
		return
	var path := "res://content/props/" + file
	var model := Content.load_model(path)
	if model == null:
		return
	var p: Array = pr.get("pos", [0, 0])
	var scl: float = float(pr.get("scale", 1.0))
	var yaw: float = float(pr.get("yaw", 0.0))
	var solid: bool = pr.get("solid", true)

	if solid:
		# جسم صلب بتصادم تلقائي حسب حجم النموذج
		var body := StaticBody3D.new()
		add_child(body)
		body.global_position = Vector3(float(p[0]), float(pr.get("y", 0.0)), float(p[1]))
		body.rotation_degrees.y = yaw
		body.add_child(model)
		model.scale = Vector3.ONE * scl
		# تصادم من حدود النموذج
		var aabb := _prop_aabb(model)
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(maxf(aabb.size.x, 0.5), maxf(aabb.size.y, 0.5), maxf(aabb.size.z, 0.5))
		col.shape = shape
		col.position = aabb.position + aabb.size * 0.5
		body.add_child(col)
	else:
		var holder := Node3D.new()
		add_child(holder)
		holder.global_position = Vector3(float(p[0]), float(pr.get("y", 0.0)), float(p[1]))
		holder.rotation_degrees.y = yaw
		holder.add_child(model)
		model.scale = Vector3.ONE * scl


func _prop_aabb(node: Node3D) -> AABB:
	var res := AABB()
	var first := true
	for mi in _all_meshes(node):
		var box: AABB = mi.get_aabb()
		box = mi.transform * box
		if first:
			res = box
			first = false
		else:
			res = res.merge(box)
	if first:
		return AABB(Vector3(-1, 0, -1), Vector3(2, 2, 2))
	return res


func _all_meshes(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_all_meshes(c))
	return out


# 🏔️ بناء التضاريس من إعدادات الخريطة
# 📏 ارتفاع الأرض عند أي نقطة (للعناصر تقعد على التضاريس صح)
# 🛣️ يحسب مقاطع الرصيف بين التقاطعات (يتخطى التقاطعات نفسها)
# يرجّع: [[بداية, نهاية], [بداية, نهاية], ...]
func _road_segments(cross_roads: Array, road_w: float, half: float, walk_w: float) -> Array:
	# مناطق التقاطعات (شارع + رصيفيه)
	var zones: Array = []
	var gap: float = road_w * 0.5 + walk_w + 0.15
	for cr in cross_roads:
		var c: float = float(cr)
		zones.append([c - gap, c + gap])
	zones.sort_custom(func(a, b): return float(a[0]) < float(b[0]))

	# نبني المقاطع بين التقاطعات
	var segs: Array = []
	var cur: float = -half
	for z in zones:
		var lo: float = float(z[0])
		var hi: float = float(z[1])
		if hi < -half:
			continue
		if lo > half:
			break
		var start: float = maxf(cur, -half)
		var stop: float = minf(lo, half)
		if stop - start > 0.6:
			segs.append([start, stop])
		cur = maxf(cur, hi)
	# المقطع الأخير بعد آخر تقاطع
	if half - cur > 0.6:
		segs.append([maxf(cur, -half), half])
	return segs


# 🚫 قانون: هل هذي النقطة على شارع أو رصيف؟ (ممنوع نبني عليها)
func _on_road(x: float, z: float, m: Dictionary, extra: float = 1.5) -> bool:
	var rw: float = float(m["road_width"])
	var sw: float = float(m["sidewalk_width"])
	var block: float = rw * 0.5 + sw + extra     # الشارع + الرصيف + هامش
	for rx in m["roads_x"]:
		if absf(x - float(rx)) < block:
			return true
	for rz in m["roads_z"]:
		if absf(z - float(rz)) < block:
			return true
	return false


func ground_y(x: float, z: float) -> float:
	if _terrain != null and is_instance_valid(_terrain):
		return _terrain.height_at(x, z)
	return 0.0


func _build_terrain(cfg: Dictionary, m: Dictionary, size: float) -> void:
	var t := Terrain.new()
	t.size = size
	t.res = clampi(int(cfg.get("resolution", 60)), 20, 100)
	t.hills = float(cfg.get("hills", 3.0))
	t.hill_scale = float(cfg.get("hill_scale", 0.035))
	t.bumps = float(cfg.get("bumps", 0.25))
	t.bump_scale = float(cfg.get("bump_scale", 0.25))
	t.ground_color = m["ground_color"]
	t.craters = cfg.get("craters", [])
	t.pools = cfg.get("pools", [])

	# 🛣️ المناطق المسطحة: الشوارع ونقاط بداية الأعداء (حتى ما تنولد بتلة)
	var flats: Array = []
	# 🛣️ ممرات مسطحة مستمرة للشوارع (تشمل الأرصفة)
	var cors: Array = []
	var corridor_half: float = float(m["road_width"]) * 0.5 + float(m["sidewalk_width"]) + 1.0
	for rx in m["roads_x"]:
		cors.append({"axis": "x", "at": float(rx), "half": corridor_half, "fade": 7.0})
	for rz in m["roads_z"]:
		cors.append({"axis": "z", "at": float(rz), "half": corridor_half, "fade": 7.0})
	t.corridors = cors
	# نقاط البداية
	for s in m["spawns"]:
		flats.append({"pos": [float(s[0]), float(s[1])], "radius": 8.0})
	# المباني (حتى ما تطفو أو تنغرز)
	for b in m["buildings"]:
		flats.append({"pos": [float(b[0]), float(b[1])], "radius": 14.0})
	t.flat_zones = flats

	add_child(t)
	t.build()
	_terrain = t
	# 💧 ربط برك الماء بالتبطئة
	for area in get_tree().get_nodes_in_group("water_areas"):
		if area is Area3D:
			area.body_entered.connect(func(b: Node) -> void:
				if b is ArcadeCar:
					b.enter_water())
			area.body_exited.connect(func(b: Node) -> void:
				if b is ArcadeCar:
					b.exit_water())


func _build_water(pos: Vector3, w: float, d: float) -> void:
	# قاع الحفرة
	_add_ground(pos + Vector3(0, -0.35, 0), Vector3(w, 0.6, d), Color(0.18, 0.22, 0.2))
	# سطح الماء (شفاف - بدون تصادم)
	var surf := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w, 0.1, d)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.2, 0.5, 0.75, 0.6)
	mat.metallic = 0.4
	mat.roughness = 0.15
	bm.material = mat
	surf.mesh = bm
	add_child(surf)
	surf.global_position = pos + Vector3(0, 0.05, 0)
	# منطقة التبطئة
	var area := Area3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(w, 1.6, d)
	col.shape = shape
	area.add_child(col)
	add_child(area)
	area.global_position = pos + Vector3(0, 0.4, 0)
	area.add_to_group("water")
	area.body_entered.connect(func(b: Node) -> void:
		if b is ArcadeCar:
			b.enter_water())
	area.body_exited.connect(func(b: Node) -> void:
		if b is ArcadeCar:
			b.exit_water())
	_water_areas.append(area)


# 🌉 جسر: منحدرين + سطح مرتفع + حواف
func _build_bridge(pos: Vector3, length: float, w: float, h: float, yaw: float) -> void:
	var deck := length * 0.55
	var ramp := (length - deck) * 0.5
	var ang := rad_to_deg(atan2(h, ramp))
	var basis_y := Basis(Vector3.UP, deg_to_rad(yaw))
	var road := Color(0.3, 0.3, 0.33)
	# سطح الجسر
	_add_box(pos + basis_y * Vector3(0, h, 0), Vector3(w, 0.5, deck), road, Vector3(0, yaw, 0))
	# منحدر الصعود والنزول
	var zo := deck * 0.5 + ramp * 0.5
	var rl := sqrt(ramp * ramp + h * h)
	_add_box(pos + basis_y * Vector3(0, h * 0.5, -zo), Vector3(w, 0.5, rl), road, Vector3(ang, yaw, 0))
	_add_box(pos + basis_y * Vector3(0, h * 0.5, zo), Vector3(w, 0.5, rl), road, Vector3(-ang, yaw, 0))
	# حواف السطح (سياج)
	for sx in [-1.0, 1.0]:
		_add_box(pos + basis_y * Vector3(sx * (w * 0.5 - 0.2), h + 0.65, 0),
			Vector3(0.35, 0.9, deck), Color(0.45, 0.46, 0.5), Vector3(0, yaw, 0))
	# أعمدة دعم
	for zz in [-deck * 0.35, deck * 0.35]:
		_add_box(pos + basis_y * Vector3(0, h * 0.5, zz), Vector3(1.2, h, 1.2), Color(0.4, 0.4, 0.44), Vector3(0, yaw, 0))


# 🚇 نفق: جدارين + سقف (تمر جواه)
func _build_tunnel(pos: Vector3, length: float, w: float, h: float, yaw: float) -> void:
	var wall := Color(0.36, 0.36, 0.4)
	var basis_y := Basis(Vector3.UP, deg_to_rad(yaw))
	# جدارين
	for sx in [-1.0, 1.0]:
		_add_box(pos + basis_y * Vector3(sx * (w * 0.5 + 0.5), h * 0.5, 0),
			Vector3(1.0, h, length), wall, Vector3(0, yaw, 0))
	# السقف
	_add_box(pos + basis_y * Vector3(0, h + 0.4, 0), Vector3(w + 2.0, 0.8, length), wall, Vector3(0, yaw, 0))
	# إضاءة داخلية
	for i in 3:
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(1.0, 0.85, 0.6)
		lamp.light_energy = 2.2
		lamp.omni_range = 12.0
		add_child(lamp)
		lamp.global_position = pos + basis_y * Vector3(0, h - 0.4, (i - 1) * length * 0.32)


func _spawn_mountain(pos: Vector3, s: float) -> void:
	var body := StaticBody3D.new()
	add_child(body)
	body.global_position = pos
	var rock := StandardMaterial3D.new()
	rock.albedo_color = Color(0.42, 0.38, 0.34)
	rock.roughness = 0.95
	var sizes = [Vector3(11, 5, 10), Vector3(8, 5, 7.5), Vector3(5, 4.5, 4.5), Vector3(2.6, 3.5, 2.6)]
	var y := 0.0
	for i in sizes.size():
		var sz: Vector3 = sizes[i] * s
		var m := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = sz
		bm.material = rock
		m.mesh = bm
		m.position = Vector3(randf_range(-0.8, 0.8) * s, y + sz.y * 0.5, randf_range(-0.8, 0.8) * s)
		m.rotation.y = randf() * TAU
		body.add_child(m)
		y += sz.y * 0.62
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(9.0 * s, y, 8.5 * s)
	col.shape = shape
	col.position.y = y * 0.5
	body.add_child(col)


# حفرة غاطسة دائمة (نفس أسلوب حفرة النووي)
func _build_pit(pos: Vector3, r: float) -> void:
	var pit := Node3D.new()
	add_child(pit)
	pit.global_position = Vector3(pos.x, 0.0, pos.z)
	var layers = [
		[r, 0.04, Color(0.16, 0.13, 0.09)],
		[r * 0.8, -0.7, Color(0.11, 0.09, 0.06)],
		[r * 0.58, -1.4, Color(0.08, 0.07, 0.05)],
		[r * 0.36, -2.1, Color(0.05, 0.045, 0.035)],
	]
	for layer in layers:
		var disc := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = layer[0]
		cyl.bottom_radius = layer[0] * 0.85
		cyl.height = 0.6
		var mat := StandardMaterial3D.new()
		mat.albedo_color = layer[2]
		mat.roughness = 1.0
		cyl.material = mat
		disc.mesh = cyl
		disc.position.y = layer[1]
		pit.add_child(disc)
	var rim := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = r * 0.95
	torus.outer_radius = r * 1.12
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.22, 0.18, 0.13)
	rm.roughness = 1.0
	torus.material = rm
	rim.mesh = torus
	rim.position.y = 0.15
	rim.scale.y = 0.4
	pit.add_child(rim)


func _build_projectors() -> void:
	# كشافات ملعب على أعمدة بالزوايا - تشتغل بالليل
	var corners = [
		Vector3(-50, 0, -50), Vector3(50, 0, -50),
		Vector3(-50, 0, 50), Vector3(50, 0, 50),
	]
	for corner in corners:
		# عمود
		var pole := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.3
		pm.bottom_radius = 0.4
		pm.height = 16.0
		var pole_mat := StandardMaterial3D.new()
		pole_mat.albedo_color = Color(0.3, 0.32, 0.35)
		pole_mat.metallic = 0.6
		pm.material = pole_mat
		pole.mesh = pm
		var body := StaticBody3D.new()
		var col := CollisionShape3D.new()
		var cshape := CylinderShape3D.new()
		cshape.radius = 0.4
		cshape.height = 16.0
		col.shape = cshape
		body.add_child(col)
		body.add_child(pole)
		add_child(body)
		body.position = corner + Vector3(0, 8, 0)

		# صندوق الكشافات فوق العمود
		var head := MeshInstance3D.new()
		var hm := BoxMesh.new()
		hm.size = Vector3(2.5, 0.8, 1.0)
		var head_mat := StandardMaterial3D.new()
		head_mat.albedo_color = Color(0.15, 0.15, 0.17)
		hm.material = head_mat
		head.mesh = hm
		add_child(head)
		# يتجه نحو وسط الملعب
		head.position = corner + Vector3(0, 16, 0)
		head.look_at(Vector3(0, 0, 0), Vector3.UP)

		# سطح مضيء (لمبات) - نخزنه لنطفيه/نشعله
		var lamp := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(2.3, 0.6, 0.1)
		var lamp_mat := StandardMaterial3D.new()
		lamp_mat.albedo_color = Color(0.9, 0.9, 0.8)
		lamp_mat.emission_enabled = true
		lamp_mat.emission = Color(1.0, 0.98, 0.85)
		lamp_mat.emission_energy_multiplier = 0.3
		lm.material = lamp_mat
		lamp.mesh = lm
		lamp.position = corner + Vector3(0, 16, 0)
		lamp.look_at(Vector3(0, 0, 0), Vector3.UP)
		lamp.translate_object_local(Vector3(0, 0, -0.55))
		add_child(lamp)
		_projector_mats.append(lamp_mat)

		# ضوء spotlight فعلي من الكشاف نحو الملعب
		var spot := SpotLight3D.new()
		spot.position = corner + Vector3(0, 16, 0)
		spot.look_at(Vector3(0, 0, 0), Vector3.UP)
		spot.light_color = Color(1.0, 0.98, 0.9)
		spot.light_energy = 0.0                # مطفي بالنهار
		spot.spot_range = 90.0
		spot.spot_angle = 40.0
		spot.spot_attenuation = 0.8
		spot.shadow_enabled = false
		add_child(spot)
		_projector_lights.append(spot)


func _add_destructible(pos: Vector3, kind: int) -> Destructible:
	var d := Destructible.new()
	add_child(d)
	d.setup(kind)
	d.global_position = pos
	return d


func _add_ground(pos: Vector3, box_size: Vector3, color: Color, is_road := false) -> void:
	# أرضية بدون تصادم جانبي مؤثر (مسطحة)
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box_size
	col.shape = shape
	body.add_child(col)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box_size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	# الأسفلت يصير لامع ومبلول لما تمطر
	if is_road and _weather != null and _weather.rain_enabled:
		mat.roughness = 0.25
		mat.metallic = 0.4
	else:
		mat.roughness = 0.9 if is_road else 0.95
	bm.material = mat
	mi.mesh = bm
	body.add_child(mi)
	add_child(body)
	body.position = pos


func _add_box(pos: Vector3, box_size: Vector3, color: Color, rot: Vector3 = Vector3.ZERO) -> void:
	var body := StaticBody3D.new()

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box_size
	col.shape = shape
	body.add_child(col)

	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box_size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED    # يرسم الوجهين (ما يبين شفاف)
	bm.material = mat
	mi.mesh = bm
	body.add_child(mi)

	add_child(body)
	body.position = pos
	body.rotation_degrees = rot


# ---------- الواجهة ----------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	_ui_layer = layer
	add_child(layer)

	controls = TouchControls.new()
	layer.add_child(controls)

	_speed_label = Label.new()
	_speed_label.position = Vector2(26, 14)
	_speed_label.add_theme_font_size_override("font_size", 30)
	_speed_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	layer.add_child(_speed_label)

	var hp_bg := ColorRect.new()
	hp_bg.color = Color(0, 0, 0, 0.45)
	hp_bg.position = Vector2(26, 58)
	hp_bg.size = Vector2(244, 20)
	layer.add_child(hp_bg)

	_hp_fill = ColorRect.new()
	_hp_fill.color = Color(0.25, 0.85, 0.3)
	_hp_fill.position = Vector2(28, 60)
	_hp_fill.size = Vector2(240, 16)
	layer.add_child(_hp_fill)

	# شريط النيترو تحت شريط الصحة
	var boost_bg := ColorRect.new()
	boost_bg.color = Color(0, 0, 0, 0.45)
	boost_bg.position = Vector2(26, 82)
	boost_bg.size = Vector2(244, 12)
	layer.add_child(boost_bg)

	_boost_fill = ColorRect.new()
	_boost_fill.color = Color(0.3, 0.8, 1.0)
	_boost_fill.position = Vector2(28, 84)
	_boost_fill.size = Vector2(240, 8)
	layer.add_child(_boost_fill)

	_ammo_label = Label.new()
	_ammo_label.position = Vector2(26, 100)
	_ammo_label.add_theme_font_size_override("font_size", 20)
	_ammo_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	layer.add_child(_ammo_label)

	_kills_label = Label.new()
	_kills_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_kills_label.offset_left = -260
	_kills_label.offset_right = -26
	_kills_label.offset_top = 14
	_kills_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_kills_label.add_theme_font_size_override("font_size", 30)
	_kills_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	_kills_label.text = "KILLS: 0"
	layer.add_child(_kills_label)

	_center_label = Label.new()
	_center_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_center_label.offset_top = 170
	_center_label.offset_bottom = 240
	_center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_label.add_theme_font_size_override("font_size", 40)
	_center_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3))
	_center_label.text = "تدمرت! إحياء بعد لحظات..."
	_center_label.visible = false
	layer.add_child(_center_label)

	_drift_label = Label.new()
	_drift_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_drift_label.offset_top = 250
	_drift_label.offset_bottom = 300
	_drift_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_drift_label.add_theme_font_size_override("font_size", 30)
	_drift_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.1))
	_drift_label.visible = false
	layer.add_child(_drift_label)

	_hitmarker = Label.new()
	_hitmarker.set_anchors_and_offsets_preset(Control.PRESET_VCENTER_WIDE)
	_hitmarker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hitmarker.add_theme_font_size_override("font_size", 36)
	_hitmarker.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	_hitmarker.text = "+"
	_hitmarker.visible = false
	layer.add_child(_hitmarker)

	var menu_btn := Button.new()
	menu_btn.text = "⟵ القائمة"
	menu_btn.add_theme_font_size_override("font_size", 20)
	menu_btn.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	menu_btn.offset_left = -85
	menu_btn.offset_right = 85
	menu_btn.offset_top = 12
	menu_btn.offset_bottom = 56
	menu_btn.modulate = Color(1, 1, 1, 0.7)
	menu_btn.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/menu.tscn"))
	layer.add_child(menu_btn)

	# الرادار (خريطة الأعداء) فوق يمين تحت عداد القتل
	_radar = Radar.new()
	_radar.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_radar.offset_left = -210
	_radar.offset_top = 60
	_radar.offset_right = -20
	_radar.offset_bottom = 250
	layer.add_child(_radar)

	# علامة قفل الهدف (توجيه ذكي)
	_lock_marker = Control.new()
	_lock_marker.custom_minimum_size = Vector2(60, 60)
	_lock_marker.size = Vector2(60, 60)
	_lock_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lock_marker.visible = false
	_lock_marker.draw.connect(_draw_lock_marker)
	layer.add_child(_lock_marker)

	# مؤشر الدرع
	_shield_label = Label.new()
	_shield_label.position = Vector2(26, 124)
	_shield_label.add_theme_font_size_override("font_size", 22)
	_shield_label.add_theme_color_override("font_color", Color(0.3, 0.75, 1.0))
	_shield_label.visible = false
	layer.add_child(_shield_label)

	# رسالة إعلان حدث النووي (وسط أعلى)
	_announce_label = Label.new()
	_announce_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_announce_label.offset_top = 90
	_announce_label.offset_bottom = 140
	_announce_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_announce_label.add_theme_font_size_override("font_size", 34)
	_announce_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.1))
	_announce_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_announce_label.add_theme_constant_override("outline_size", 6)
	_announce_label.visible = false
	layer.add_child(_announce_label)

	# طبقة الوميض الأبيض (انفجار النووي)
	_nuke_flash_rect = ColorRect.new()
	_nuke_flash_rect.color = Color(1, 1, 1, 0)
	_nuke_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_nuke_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_nuke_flash_rect)

	# 🎬 وميض حواف الشاشة (تأثير القتلة - محلي)
	_hit_vignette = ColorRect.new()
	_hit_vignette.color = Color(1, 1, 1, 0)
	_hit_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hit_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_hit_vignette)

	# عدّاد وصول النووي (فوق يسار تحت السرعة)
	_nuke_timer_label = Label.new()
	_nuke_timer_label.position = Vector2(26, 156)
	_nuke_timer_label.add_theme_font_size_override("font_size", 22)
	_nuke_timer_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.1))
	_nuke_timer_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_nuke_timer_label.add_theme_constant_override("outline_size", 4)
	layer.add_child(_nuke_timer_label)

	# عداد بداية الجولة (3..2..1) - كبير بمنتصف الشاشة
	_countdown_label = Label.new()
	_countdown_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_countdown_label.add_theme_font_size_override("font_size", 130)
	_countdown_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.15))
	_countdown_label.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.0))
	_countdown_label.add_theme_constant_override("outline_size", 14)
	_countdown_label.visible = false
	_countdown_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_countdown_label)


# ---------- السيارات والصناديق ----------

func _spawn_player() -> void:
	car = ArcadeCar.new()
	var ch: Dictionary = Content.get_character(Global.selected_character)
	var stats: Dictionary = ch["stats"]
	car.body_color = Color(stats["color"][0], stats["color"][1], stats["color"][2])
	car.controls = controls
	car.position = Vector3(0, ground_y(0, 30) + 2.0, 30)
	add_child(car)
	# نطبّق فئة السيارة (يجب أن يكون بعد add_child حتى يعمل مع _ready)
	car.apply_class(stats)
	# نحمّل موديل الشخصية لو موجود
	if ch["model_path"] != "":
		var model := Content.load_model(ch["model_path"])
		if model != null:
			car.set_custom_model(model, ch)
			car.set_weapon_heights(ch["weapons_y"])
	car.health_changed.connect(_on_player_health)
	car.died.connect(_on_player_died)
	car.respawned.connect(_on_player_respawned)
	car.hit_landed.connect(_on_hit_landed)
	car.ammo_changed.connect(_refresh_ammo)
	car.drifted.connect(_on_drifted)
	car.boost_changed.connect(_on_boost_changed)
	car.mine_charging.connect(_on_mine_charging)
	car.rocket_charging.connect(func(n: int) -> void: controls.set_rocket_charge(n))
	car.shield_changed.connect(_on_shield_changed)
	car.critical_started.connect(_on_critical_started)
	car.critical_tick.connect(_on_critical_tick)
	car.critical_ended.connect(_on_critical_ended)


func _spawn_dummies() -> void:
	var n: int = clampi(Global.enemy_count, 1, 7)
	for i in n:
		var d := ArcadeCar.new()
		# كل عدو ياخذ شخصية عشوائية من مجلد المحتوى (موديل + فئة)
		var ch: Dictionary = Content.get_character(randi() % Content.count())
		var stats: Dictionary = ch["stats"]
		# لون مميز للعدو (حتى نميّزه عن اللاعب) مع لمسة من لون فئته
		d.body_color = DUMMY_COLORS[i % DUMMY_COLORS.size()]
		if i < _dummy_spots.size():
			var sp: Vector3 = _dummy_spots[i]
			d.position = Vector3(sp.x, ground_y(sp.x, sp.z) + 2.0, sp.z)
		else:
			# أعداء إضافيين: توزيع دائري حول الخريطة
			var ang := TAU * float(i) / float(n)
			var rad: float = float(Maps.get_map(Global.selected_map)["size"]) * 0.32
			d.position = Vector3(cos(ang) * rad, 1.5, sin(ang) * rad)
		d.rotation.y = randf() * TAU
		if Global.game_mode == Global.Mode.AI:
			# عدو ذكي فعّال
			d.input_enabled = true
			d.ai_controlled = true
			# نعطيه ذخيرة ابتدائية حتى يستخدم الأسلحة
			d.ammo["rocket"] = 6
			d.ammo["homing"] = 6
			d.ammo["mine"] = 4
		else:
			# هدف ثابت (وضع التجربة)
			d.input_enabled = false
		add_child(d)
		# نطبّق فئة الشخصية (دبابة/وسط/سريعة) بعد الإضافة
		d.apply_class(stats)
		# نحمّل موديل الشخصية لو موجود
		if ch["model_path"] != "":
			var model := Content.load_model(ch["model_path"])
			if model != null:
				d.set_custom_model(model, ch)
				d.set_weapon_heights(ch["weapons_y"])
		d.died.connect(_on_dummy_died.bind(d))
		d.respawned.connect(_on_dummy_respawned.bind(d))
		_dummies.append(d)

		# نركّب دماغ الذكاء الاصطناعي
		if Global.game_mode == Global.Mode.AI:
			var brain := CarAI.new()
			brain.car = d
			brain.get_enemies = _get_ai_enemies
			brain.get_score = _get_car_score
			brain.get_nuke = _get_nuke_objective
			brain.difficulty = Global.difficulty
			brain.apply_difficulty()
			d.add_child(brain)

	if _radar != null and car != null:
		_radar.setup(car, _dummies)


# 🏆 نقاط أي سيارة (يستخدمها الذكاء للتنافس)
# ☢️ هدف النووي الحالي (صندوق أو سلاح) - للذكاء
func _get_nuke_objective() -> Node3D:
	if _nuke == null or not is_instance_valid(_nuke):
		return null
	return _nuke.get_objective()


func _get_car_score(c: Node) -> int:
	if c == car:
		return _kills
	return int(_enemy_scores.get(c, 0))


func _get_ai_enemies() -> Array:
	# أعداء الـ AI = اللاعب + باقي سيارات الـ AI (كلهم يتقاتلون)
	var list: Array = []
	if car != null and is_instance_valid(car):
		list.append(car)
	for d in _dummies:
		list.append(d)
	return list


func _on_dummy_respawned(d: Node) -> void:
	# نعيد ذخيرة الـ AI عند الإحياء
	if Global.game_mode == Global.Mode.AI and is_instance_valid(d):
		d.ammo["rocket"] = 3
		d.ammo["homing"] = 2


func _spawn_pickups() -> void:
	# الخريطة الكبيرة: ضعف الصناديق ونطاق أوسع
	var repeats: int = Maps.get_map(Global.selected_map)["pickup_sets"]
	for rep in repeats:
		for kind in PICKUP_KINDS:
			var p := WeaponPickup.new()
			p.kind = kind
			add_child(p)
			var ux := randf_range(-_pickup_range, _pickup_range)
			var uz := randf_range(-_pickup_range, _pickup_range)
			p.global_position = Vector3(ux, ground_y(ux, uz) + 0.5, uz)


func _spawn_camera() -> void:
	_cam = ChaseCamera.new()
	_cam.target = car
	add_child(_cam)
	_cam.make_current()


# ---------- ربط الإشارات ----------

func _on_player_health(current: float, maximum: float) -> void:
	var r := clampf(current / maximum, 0.0, 1.0)
	_hp_fill.size.x = 240.0 * r
	_hp_fill.color = Color(0.9, 0.2, 0.15).lerp(Color(0.25, 0.85, 0.3), r)
	# اهتزاز عند نقص الصحة (تعرّضت لضرر)
	if current < _last_hp - 0.5:
		Fx.vibrate(40)
	_last_hp = current


func _on_player_died(_attacker) -> void:
	_center_label.visible = true
	_cam.add_trauma(0.7)
	Fx.vibrate(220)
	# 💀 تسجيل الموتة (والانتحار ينقص نقطة)
	_register_kill(car, _attacker)


func _on_player_respawned() -> void:
	_center_label.visible = false
	_last_hp = car.max_health if car != null else 100.0


# 🏆 تسجيل قتلة: victim مات على يد attacker
func _register_kill(victim: Node, attacker) -> void:
	if _match_over:
		return
	# الموتات
	if victim == car:
		_player_deaths += 1
	else:
		_deaths[victim] = int(_deaths.get(victim, 0)) + 1

	# 💀 انتحار: قتل نفسه (نووي/عبوة/صاروخ قريب) => تنقص نقطة
	if attacker == null or attacker == victim:
		if victim == car:
			_kills = maxi(_kills - 1, 0)
			_announce_kill("💀 قتلت نفسك! -1", Color(1.0, 0.3, 0.2))
		else:
			_enemy_scores[victim] = maxi(int(_enemy_scores.get(victim, 0)) - 1, 0)
		_update_score_hud()
		return

	# قتلة عادية
	if attacker == car:
		_kills += 1
		_announce_kill("+1 نقطة", Color(0.35, 1.0, 0.4))
		_update_score_hud()
		_kill_flash()           # 🎬 تأثير بصري محلي (بلا بطيء زمني - آمن للشبكي)
		if _kills >= SCORE_TO_WIN:
			_end_match(true)
	elif attacker in _dummies:
		_enemy_scores[attacker] = int(_enemy_scores.get(attacker, 0)) + 1
		if victim == car:
			_announce_kill("💀 عدو سجّل عليك", Color(1.0, 0.35, 0.25))
		_update_score_hud()
		if _enemy_scores[attacker] >= SCORE_TO_WIN:
			_end_match(false)
	else:
		_update_score_hud()


func _on_dummy_died(attacker, victim: Node) -> void:
	_register_kill(victim, attacker)


# 📊 جدول النقاط (مثل ألعاب القتال)
func _build_scoreboard() -> void:
	_scoreboard = VBoxContainer.new()
	_scoreboard.position = Vector2(26, 200)
	_scoreboard.add_theme_constant_override("separation", 3)
	_ui_layer.add_child(_scoreboard)
	_update_scoreboard()


func _update_scoreboard() -> void:
	if _scoreboard == null or not is_instance_valid(_scoreboard):
		return
	for c in _scoreboard.get_children():
		c.queue_free()

	# نجمع كل السيارات مع نقاطها
	var rows: Array = []
	rows.append({"name": "أنت", "k": _kills, "d": _player_deaths, "col": Color(0.35, 1.0, 0.45), "me": true})
	for i in _dummies.size():
		var d = _dummies[i]
		if not is_instance_valid(d):
			continue
		rows.append({
			"name": "عدو %d" % (i + 1),
			"k": int(_enemy_scores.get(d, 0)),
			"d": int(_deaths.get(d, 0)),
			"col": d.body_color,
			"me": false
		})
	# ترتيب حسب القتلات (الأعلى فوق)
	rows.sort_custom(func(a, b): return int(a["k"]) > int(b["k"]))

	# العنوان
	var hdr := Label.new()
	hdr.text = "  ⚔ قتل   ☠ موت"
	hdr.add_theme_font_size_override("font_size", 14)
	hdr.add_theme_color_override("font_color", Color(0.55, 0.58, 0.65))
	_scoreboard.add_child(hdr)

	for row in rows:
		var line := Label.new()
		var star := "★ " if row["me"] else "   "
		line.text = "%s%-8s  %2d      %2d" % [star, row["name"], row["k"], row["d"]]
		line.add_theme_font_size_override("font_size", 17)
		line.add_theme_color_override("font_color", row["col"])
		line.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		line.add_theme_constant_override("outline_size", 3)
		_scoreboard.add_child(line)


func _update_score_hud() -> void:
	var best_enemy := 0
	for e in _enemy_scores.values():
		best_enemy = maxi(best_enemy, int(e))
	_kills_label.text = "🏆 %d/%d   ☠ %d      أفضل عدو: %d" % [_kills, SCORE_TO_WIN, _player_deaths, best_enemy]
	_update_scoreboard()


# 🎬 تأثير القتلة: بصري بحت (بلا بطيء زمني - آمن للعب الشبكي)
func _kill_flash() -> void:
	if _match_over:
		return
	# اهتزاز كاميرا (محلي فقط)
	if _cam != null and is_instance_valid(_cam):
		_cam.add_trauma(0.4)
		_cam.kill_zoom()          # زوم سريع (إحساس الضربة)
	# وميض أحمر خفيف بحواف الشاشة
	if _hit_vignette != null and is_instance_valid(_hit_vignette):
		_hit_vignette.color = Color(1.0, 0.85, 0.2, 0.28)
		var tw := create_tween()
		tw.tween_property(_hit_vignette, "color:a", 0.0, 0.45)
	Fx.vibrate(70)


func _announce_kill(txt: String, col: Color) -> void:
	_announce_label.text = txt
	_announce_label.visible = true
	_announce_label.modulate = Color(col.r, col.g, col.b, 0.0)
	_announce_time = 1.6
	var tw := create_tween()
	tw.tween_property(_announce_label, "modulate:a", 1.0, 0.15)
	Fx.vibrate(40)


# 🏁 نهاية المباراة
func _end_match(player_won: bool) -> void:
	if _match_over:
		return
	_match_over = true
	# نوقف الكل
	if car != null and is_instance_valid(car):
		car.input_enabled = false
	for d in _dummies:
		if is_instance_valid(d):
			d.input_enabled = false
	# بطيء سينمائي
	Engine.time_scale = 0.35
	var t := get_tree().create_timer(1.2, true, false, true)
	await t.timeout
	Engine.time_scale = 1.0
	_show_result(player_won)


func _show_result(won: bool) -> void:
	var layer := _ui_layer
	_result_panel = Panel.new()
	_result_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.05, 0.07, 0.92)
	_result_panel.add_theme_stylebox_override("panel", sb)
	layer.add_child(_result_panel)

	var title := Label.new()
	title.set_anchors_preset(Control.PRESET_FULL_RECT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.offset_top = -120
	title.text = "🏆 فزت!" if won else "💀 خسرت"
	title.add_theme_font_size_override("font_size", 84)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2) if won else Color(0.95, 0.3, 0.25))
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	title.add_theme_constant_override("outline_size", 10)
	_result_panel.add_child(title)

	var sub := Label.new()
	sub.set_anchors_preset(Control.PRESET_FULL_RECT)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sub.offset_top = 20
	var best_enemy := 0
	for e in _enemy_scores.values():
		best_enemy = maxi(best_enemy, int(e))
	sub.text = "نقاطك: %d      أفضل عدو: %d" % [_kills, best_enemy]
	sub.add_theme_font_size_override("font_size", 30)
	sub.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	_result_panel.add_child(sub)

	var again := Button.new()
	again.text = "🔄 العب مرة ثانية"
	again.custom_minimum_size = Vector2(280, 62)
	again.set_anchors_preset(Control.PRESET_CENTER)
	again.position = Vector2(-300, 110)
	again.add_theme_font_size_override("font_size", 24)
	again.pressed.connect(func() -> void: get_tree().reload_current_scene())
	_result_panel.add_child(again)

	var menu := Button.new()
	menu.text = "🏠 القائمة"
	menu.custom_minimum_size = Vector2(280, 62)
	menu.set_anchors_preset(Control.PRESET_CENTER)
	menu.position = Vector2(20, 110)
	menu.add_theme_font_size_override("font_size", 24)
	menu.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/menu.tscn"))
	_result_panel.add_child(menu)

	# أنيميشن دخول
	_result_panel.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_result_panel, "modulate:a", 1.0, 0.4)
	Fx.sound(Vector3.ZERO, "explosion" if not won else "pickup", 0.0, 1.0)


func _on_hit_landed() -> void:
	_hitmarker.visible = true
	_marker_time = 0.08
	Fx.vibrate(15)


func _on_boom(pos: Vector3, strength: float) -> void:
	if car == null:
		return
	var d := car.global_position.distance_to(pos)
	var reach := 30.0 * strength
	var intensity := clampf((0.85 - d / reach) * strength, 0.0, 1.4)
	_cam.add_trauma(intensity)
	# اهتزاز حسب قرب الانفجار
	if intensity > 0.1:
		Fx.vibrate(int(clampf(intensity * 120.0, 20.0, 200.0)))


func _on_drifted(duration: float) -> void:
	_drift_label.text = "تفحيط %.1f ثانية!" % duration
	_drift_label.visible = true
	_drift_label.modulate.a = 1.0
	_drift_time = 1.6


func _on_boost_changed(current: float, maximum: float) -> void:
	var r := clampf(current / maximum, 0.0, 1.0)
	_boost_fill.size.x = 240.0 * r
	_boost_fill.color = Color(0.9, 0.4, 0.2).lerp(Color(0.3, 0.8, 1.0), r)
	controls.set_boost_ratio(r)


func _on_shield_changed(active: bool, _time_left: float) -> void:
	_shield_label.visible = active


func _start_countdown() -> void:
	# نجمّد الكل لين ما يخلص العد
	if car != null:
		car.input_enabled = false
	for d in _dummies:
		d.input_enabled = false
	for n in ["3", "2", "1"]:
		_countdown_label.text = n
		_pop_countdown(Color(1.0, 0.82, 0.15))
		Fx.sound(car.global_position, "beep", -4.0, 0.9)
		await get_tree().create_timer(1.0).timeout
	_countdown_label.text = "انطلق!"
	_pop_countdown(Color(0.3, 1.0, 0.4))
	Fx.sound(car.global_position, "beep", 0.0, 1.5)
	await get_tree().create_timer(0.8).timeout
	_countdown_label.visible = false
	if car != null:
		car.input_enabled = true
	if Global.game_mode == Global.Mode.AI:
		for d in _dummies:
			if is_instance_valid(d):
				d.input_enabled = true


func _pop_countdown(col: Color) -> void:
	_countdown_label.visible = true
	_countdown_label.add_theme_color_override("font_color", col)
	_countdown_label.pivot_offset = _countdown_label.size * 0.5
	_countdown_label.scale = Vector2(2.2, 2.2)
	_countdown_label.modulate.a = 0.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_countdown_label, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_countdown_label, "modulate:a", 1.0, 0.22)


func _on_nuke_announce(text: String) -> void:
	_announce_label.text = text
	_announce_label.visible = true
	_announce_label.modulate.a = 0.0
	_announce_time = 3.5
	var tw := create_tween()
	tw.tween_property(_announce_label, "modulate:a", 1.0, 0.25)
	Fx.vibrate(60)


func _on_nuke_flash() -> void:
	_nuke_flash_rect.color = Color(1, 1, 1, 1)     # وميض أبيض كامل
	# 🎬 اهتزاز عنيف طويل (يعوّض البطيء الزمني المشال)
	if _cam != null and is_instance_valid(_cam):
		_cam.add_trauma(1.0)


func _update_mine_hud() -> void:
	if car == null or not is_instance_valid(car) or controls == null:
		return
	# أولوية: الحالة الحرجة وحمل النووي يملكون الزر
	if car.critical:
		controls.set_detonate_mode("فجّر!", true)
		return
	if car.nuke_carrier:
		controls.set_detonate_mode("🚀 أطلق", true)
		return
	var mines: Array = car.my_remote_mines()
	if mines.is_empty():
		controls.set_show_detonate(false)
		if _radar != null:
			_radar.mines = []
		return
	# ألغام مزروعة => الزر يظهر
	var ready := false
	for m in mines:
		if m.enemy_near():
			ready = true
			break
	controls.set_show_detonate(true)
	controls.set_detonate_mode("💣 فجّر", ready)
	if _radar != null:
		_radar.mines = mines
	if ready:
		Fx.vibrate(18)


func _update_nuke_hud(delta: float) -> void:
	# عدّاد وصول النووي / حالة الحدث
	if _nuke != null and _nuke_timer_label != null:
		var t := _nuke.get_time_until_nuke()
		if t > 0.0:
			var mins := int(t) / 60
			var secs := int(t) % 60
			_nuke_timer_label.text = "☢ النووي بعد %d:%02d" % [mins, secs]
			if t <= 10.0:
				var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012)
				_nuke_timer_label.add_theme_color_override("font_color", Color(1.0, 0.25 + pulse * 0.4, 0.1))
			else:
				_nuke_timer_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.1))
		else:
			var phase_txt := _nuke.get_phase_text()
			_nuke_timer_label.text = ("☢ " + phase_txt) if phase_txt != "" else "☢ ..."
			_nuke_timer_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.15))
	# تلاشي الإعلان
	if _announce_time > 0.0:
		_announce_time -= delta
		if _announce_time < 0.6:
			_announce_label.modulate.a = clampf(_announce_time / 0.6, 0.0, 1.0)
		if _announce_time <= 0.0:
			_announce_label.visible = false
	# تلاشي وميض النووي
	if _nuke_flash_rect.color.a > 0.0:
		_nuke_flash_rect.color.a = maxf(_nuke_flash_rect.color.a - delta * 0.7, 0.0)
	# لو اللاعب يحمل النووي: عداد + زر إطلاق (إلا لو بالحالة الحرجة)
	if car == null or not is_instance_valid(car):
		return
	if car.nuke_carrier and not car.critical:
		var carry_left: float = _nuke.get_carry_left()
		var elapsed: float = 10.0 - carry_left
		if elapsed < _nuke.launch_lockout:
			# فترة الحظر - ما يقدر يطلق بعد
			controls.set_show_detonate(false)
			_center_label.visible = true
			_center_label.modulate = Color(1.0, 0.7, 0.1)
			_center_label.text = "احمِ نفسك! الإطلاق متاح بعد %.0f" % (_nuke.launch_lockout - elapsed)
		else:
			controls.set_show_detonate(true)
			_center_label.visible = true
			_center_label.modulate = Color(0.4, 1.0, 0.3)
			_center_label.text = "🚀 أطلق الآن! %.1f" % carry_left
	elif _nuke != null and _nuke.get_carrier() != null and _nuke.get_carrier() != car:
		# عدو يحمله - تحذير
		if not car.critical:
			_center_label.visible = true
			_center_label.modulate = Color(1.0, 0.5, 0.1)
			_center_label.text = "⚠ عدو يحمل النووي — دمّره!"
	elif not car.critical:
		if _center_label.modulate.g > 0.5 or _center_label.text.begins_with("⚠ عدو") or _center_label.text.begins_with("🚀"):
			_center_label.visible = false


func _on_critical_started(_time_left: float) -> void:
	_center_label.visible = true
	_center_label.modulate = Color(1.0, 0.25, 0.15)
	controls.set_show_detonate(true)
	Fx.vibrate(150)


func _on_critical_tick(time_left: float) -> void:
	_center_label.visible = true
	_center_label.text = "⚠ خطر! فجّر سيارتك على العدو — %.1f" % time_left
	_center_label.modulate = Color(1.0, 0.25, 0.15)
	# نبض اهتزاز كل ثانية تقريباً
	if int(time_left * 2.0) != int((time_left + 0.05) * 2.0):
		Fx.vibrate(30)


func _on_critical_ended() -> void:
	controls.set_show_detonate(false)
	if car != null and car.alive:
		_center_label.visible = false
		_center_label.modulate = Color(1.0, 0.35, 0.3)


func _on_mine_charging(count: int) -> void:
	controls.set_mine_charge(count)
	if count > 1:
		_center_label.visible = true
		_center_label.text = "💣 تجميع العبوات ×%d" % count
		_center_label.modulate = Color(1.0, 0.55, 0.1)
	elif car != null and car.alive:
		_center_label.visible = false
		_center_label.modulate = Color(1.0, 0.35, 0.3)


func _refresh_ammo() -> void:
	if car == null:
		return
	_ammo_label.text = "قاذف %d  |  متتبع %d  |  لغم %d" % [car.ammo["rocket"], car.ammo["homing"], car.ammo["mine"]]
	# وميض خفيف عند تغيّر الذخيرة
	_ammo_label.modulate = Color(2.0, 1.9, 1.2)
	var tw := create_tween()
	tw.tween_property(_ammo_label, "modulate", Color.WHITE, 0.3)
	controls.set_ammo_text(str(car.ammo["rocket"]), str(car.ammo["homing"]))
	controls.set_mine_text("لغم %d" % car.ammo["mine"])
