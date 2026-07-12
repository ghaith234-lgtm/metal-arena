class_name Terrain
extends Node3D

# ============================================================
#  🏔️ نظام التضاريس: أرض بتلال ومطبات وحفر ومياه
#  يُبنى من ملف الخريطة (JSON) - كله قابل للتحكم
# ============================================================

var size := 120.0
var res := 60                      # دقة الشبكة (60x60 = 7200 مثلث)
var hills := 0.0                   # ارتفاع التلال العامة
var hill_scale := 0.035            # حجم التلال (أصغر = تلال أكبر)
var bumps := 0.0                   # قوة المطبات الصغيرة
var bump_scale := 0.25
var ground_color := Color(0.28, 0.42, 0.2)

var craters: Array = []            # [{pos:[x,z], radius:r, depth:d}]
var pools: Array = []              # [{pos:[x,z], radius:r, depth:d}]  → تنملي ماي
var flat_zones: Array = []         # مناطق دائرية مسطحة (مباني، نقاط بداية)
var corridors: Array = []          # ممرات مسطحة مستمرة (الشوارع)

var _heights: PackedFloat32Array = PackedFloat32Array()
var _noise: FastNoiseLite
var _noise2: FastNoiseLite


func build() -> void:
	_setup_noise()
	_compute_heights()
	_build_mesh()
	_build_skirt()            # 🧱 جدران جانبية (تخلي الأرض كتلة مو ورقة رقيقة)
	_build_collision()
	_build_safety_floor()     # 🛡️ أرضية احتياطية (ما تخلي السيارة تطيح)
	_build_water()


# 🧱 جدران جانبية حول التضاريس: تنزل للأسفل فتصير الأرض "كتلة" صلبة
func _build_skirt() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := size / float(res)
	var half := size * 0.5
	var bottom := -12.0        # عمق الجدران

	var side_col := ground_color.darkened(0.5)

	# الحواف الأربعة
	for i in res:
		# الحافة الشمالية (z = -half)
		var x0 := -half + i * step
		var x1 := x0 + step
		var hA := _heights[0 * (res + 1) + i]
		var hB := _heights[0 * (res + 1) + i + 1]
		_quad(st, Vector3(x0, hA, -half), Vector3(x1, hB, -half),
			Vector3(x1, bottom, -half), Vector3(x0, bottom, -half), side_col)
		# الحافة الجنوبية (z = +half)
		var hC := _heights[res * (res + 1) + i]
		var hD := _heights[res * (res + 1) + i + 1]
		_quad(st, Vector3(x1, hD, half), Vector3(x0, hC, half),
			Vector3(x0, bottom, half), Vector3(x1, bottom, half), side_col)
		# الحافة الغربية (x = -half)
		var z0 := -half + i * step
		var z1 := z0 + step
		var hE := _heights[i * (res + 1) + 0]
		var hF := _heights[(i + 1) * (res + 1) + 0]
		_quad(st, Vector3(-half, hF, z1), Vector3(-half, hE, z0),
			Vector3(-half, bottom, z0), Vector3(-half, bottom, z1), side_col)
		# الحافة الشرقية (x = +half)
		var hG := _heights[i * (res + 1) + res]
		var hH := _heights[(i + 1) * (res + 1) + res]
		_quad(st, Vector3(half, hG, z0), Vector3(half, hH, z1),
			Vector3(half, bottom, z1), Vector3(half, bottom, z0), side_col)

	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = side_col
	mat.roughness = 1.0
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	add_child(mi)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	var q: Array[Vector3] = [a, b, c, a, c, d]
	for v in q:
		st.set_color(Color(col.r, col.g, col.b, 1.0))
		st.add_vertex(v)


# 🛡️ أرضية صلبة تحت التضاريس: لو صار أي ثقب، السيارة ما تطيح للفراغ
func _build_safety_floor() -> void:
	var body := StaticBody3D.new()
	add_child(body)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	# نلگه أوطى نقطة بالتضاريس
	var lowest := 0.0
	for h in _heights:
		lowest = minf(lowest, h)
	shape.size = Vector3(size + 20.0, 2.0, size + 20.0)
	col.shape = shape
	col.position.y = lowest - 1.6      # تحت أوطى نقطة مباشرة
	body.add_child(col)


func _setup_noise() -> void:
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = hill_scale
	_noise.seed = randi()

	_noise2 = FastNoiseLite.new()
	_noise2.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise2.frequency = bump_scale
	_noise2.seed = randi()


# ارتفاع الأرض عند أي نقطة (يستخدمه الميش والتصادم)
func height_at(x: float, z: float) -> float:
	var h := 0.0
	# تلال ناعمة
	if hills > 0.0:
		h += _noise.get_noise_2d(x, z) * hills
	# مطبات صغيرة
	if bumps > 0.0:
		h += _noise2.get_noise_2d(x, z) * bumps

	# 🕳️ الحفر: تنزل الأرض
	for c in craters:
		var cp: Array = c.get("pos", [0, 0])
		var cr: float = float(c.get("radius", 8.0))
		var cd: float = float(c.get("depth", 2.5))
		var d := Vector2(x - float(cp[0]), z - float(cp[1])).length()
		if d < cr:
			# منحنى ناعم (وعاء)
			var t := d / cr
			h -= cd * (1.0 - t * t) * (1.0 - t * 0.35)

	# 💧 برك الماء: منخفضات
	for p in pools:
		var pp: Array = p.get("pos", [0, 0])
		var pr: float = float(p.get("radius", 10.0))
		var pd: float = float(p.get("depth", 1.8))
		var d := Vector2(x - float(pp[0]), z - float(pp[1])).length()
		if d < pr:
			var t := d / pr
			h -= pd * (1.0 - t * t)

	# 🛣️ ممرات الشوارع: تسطيح مستمر على طول الشارع (مو دوائر متقطعة)
	# corridor: {axis:"x"/"z", at: موقع الشارع, half: نصف العرض, fade: مسافة التدرج}
	for cor in corridors:
		var axis: String = cor.get("axis", "x")
		var at: float = float(cor.get("at", 0.0))
		var hw: float = float(cor.get("half", 8.0))
		var fade: float = float(cor.get("fade", 6.0))
		var d := absf((x - at) if axis == "x" else (z - at))
		if d < hw + fade:
			var t := clampf((d - hw) / maxf(fade, 0.01), 0.0, 1.0)
			h *= t * t     # داخل الممر مسطح تماماً، ويتدرج للأطراف

	# مناطق دائرية مسطحة (مباني، نقاط بداية)
	for fz in flat_zones:
		var fp: Array = fz.get("pos", [0, 0])
		var fr: float = float(fz.get("radius", 10.0))
		var d2 := Vector2(x - float(fp[0]), z - float(fp[1])).length()
		if d2 < fr:
			var t2 := clampf(d2 / fr, 0.0, 1.0)
			h *= t2 * t2

	return h


func _compute_heights() -> void:
	_heights.resize((res + 1) * (res + 1))
	var step := size / float(res)
	var half := size * 0.5
	for j in res + 1:
		for i in res + 1:
			var x := -half + i * step
			var z := -half + j * step
			_heights[j * (res + 1) + i] = height_at(x, z)


func _build_mesh() -> void:
	# ArrayMesh مباشر (أضمن من SurfaceTool)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()

	var step := size / float(res)
	var half := size * 0.5

	for j in res:
		for i in res:
			var x0 := -half + i * step
			var z0 := -half + j * step
			var x1 := x0 + step
			var z1 := z0 + step
			var h00: float = _heights[j * (res + 1) + i]
			var h10: float = _heights[j * (res + 1) + i + 1]
			var h01: float = _heights[(j + 1) * (res + 1) + i]
			var h11: float = _heights[(j + 1) * (res + 1) + i + 1]

			var v00 := Vector3(x0, h00, z0)
			var v10 := Vector3(x1, h10, z0)
			var v01 := Vector3(x0, h01, z1)
			var v11 := Vector3(x1, h11, z1)

			_push_tri(verts, normals, colors, v00, v01, v10)
			_push_tri(verts, normals, colors, v10, v01, v11)

	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_COLOR] = colors

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 1)
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	mat.metallic = 0.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	mesh.surface_set_material(0, mat)

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)

	print("[Terrain] ✓ %d مثلث | حجم %.0fم" % [verts.size() / 3, size])


func _push_tri(verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray,
		a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := (b - a).cross(c - a).normalized()
	if n.y < 0.0:
		n = -n
	var tri: Array[Vector3] = [a, b, c]
	for v in tri:
		verts.push_back(v)
		normals.push_back(n)
		colors.push_back(_color_at(v.y))


func _color_at(y: float) -> Color:
	var t: float = clampf((y + 3.0) / 8.0, 0.0, 1.0)
	var col: Color = ground_color.darkened(0.3 * (1.0 - t)).lightened(0.1 * t)
	col.a = 1.0
	return col


func _build_collision() -> void:
	# 🛡️ HeightMapShape3D: مصمم للتضاريس - أقوى وأسرع وما تعبره السيارة
	var body := StaticBody3D.new()
	add_child(body)

	var shape := HeightMapShape3D.new()
	shape.map_width = res + 1
	shape.map_depth = res + 1
	# نفس شبكة الارتفاعات (بنفس الترتيب)
	var data := PackedFloat32Array()
	data.resize((res + 1) * (res + 1))
	for j in res + 1:
		for i in res + 1:
			data[j * (res + 1) + i] = _heights[j * (res + 1) + i]
	shape.map_data = data

	var col := CollisionShape3D.new()
	col.shape = shape
	# HeightMap يمتد بوحدة 1 لكل خلية => نكبّره ليطابق حجم الخريطة
	var step := size / float(res)
	col.scale = Vector3(step, 1.0, step)
	body.add_child(col)


# 💧 سطح الماء بالبرك
func _build_water() -> void:
	for p in pools:
		var pp: Array = p.get("pos", [0, 0])
		var pr: float = float(p.get("radius", 10.0))
		var level: float = float(p.get("level", -0.35))

		var surf := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = pr * 0.94
		cyl.bottom_radius = pr * 0.94
		cyl.height = 0.08
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.18, 0.45, 0.62, 0.72)
		mat.metallic = 0.55
		mat.roughness = 0.08
		mat.rim_enabled = true
		cyl.material = mat
		surf.mesh = cyl
		add_child(surf)
		surf.position = Vector3(float(pp[0]), level, float(pp[1]))

		# منطقة تبطئة (السيارة تثقل بالماي)
		var area := Area3D.new()
		var ashape := CylinderShape3D.new()
		ashape.radius = pr * 0.94
		ashape.height = 2.5
		var acol := CollisionShape3D.new()
		acol.shape = ashape
		area.add_child(acol)
		add_child(area)
		area.position = Vector3(float(pp[0]), level + 0.6, float(pp[1]))
		area.add_to_group("water_areas")
