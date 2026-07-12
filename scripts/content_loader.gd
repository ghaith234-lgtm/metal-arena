extends Node

# ============================================================
#  نظام المحتوى: يمسح مجلد الشخصيات ويحمّل الموديلات والصور
#  كل مجلد = شخصية. اسم المجلد = اسم الشخصية.
#  داخل المجلد: car.glb (الموديل) + portrait.png (الصورة) + stats.json
# ============================================================

# ثلاث فئات للسيارات - كل فئة لها إحصائيات مميزة
# tank = كبيرة/بطيئة/قوية | medium = متوازنة | fast = صغيرة/سريعة/ضعيفة
# ⚖️ قدرات موحّدة ثابتة لكل السيارات — عدالة كاملة
# الفرق بين الشخصيات بالشكل فقط، مو بالقدرة
const CAR_STATS = {
	"label": "متوازن",
	"body_scale": 1.0,
	"max_health": 250.0,
	"engine_power": 1350.0,     # تسارع أسرع شوي
	"max_speed": 26.0,          # ⚡ أسرع شوي (متوازنة)
	"mass": 60.0,
	"gun_damage": 5.0,
	"boost_force": 2250.0,      # نيترو أقوى شوي
	"steer_strength": 4.5,
	"color": [0.85, 0.2, 0.2]
}

# للتوافق: أي فئة ترجع نفس القدرات
const CLASSES = {
	"tank": CAR_STATS,
	"medium": CAR_STATS,
	"fast": CAR_STATS
}

const CONTENT_DIR = "res://content/characters/"

# قائمة الشخصيات المحمّلة
# كل عنصر: {name, folder, model_path, portrait (Texture2D or null), class, subtitle, scale, stats}
var characters: Array = []


func _ready() -> void:
	_scan_characters()


func _scan_characters() -> void:
	characters.clear()
	var dir := DirAccess.open(CONTENT_DIR)
	if dir == null:
		push_warning("مجلد الشخصيات غير موجود: " + CONTENT_DIR)
		return

	dir.list_dir_begin()
	var folder := dir.get_next()
	while folder != "":
		if dir.current_is_dir() and not folder.begins_with("."):
			var char_data := _load_character(folder)
			if not char_data.is_empty():
				characters.append(char_data)
		folder = dir.get_next()
	dir.list_dir_end()

	# لو ما لگينا أي شخصية، نضيف الافتراضية (السيارة المرسومة)
	if characters.is_empty():
		characters.append(_default_character())
	print("[Content] عدد الشخصيات المحمّلة: ", characters.size())
	for c in characters:
		print("  - ", c["name"], " | فئة: ", c["class"], " | موديل: ", c["model_path"])


func _load_character(folder: String) -> Dictionary:
	var base := CONTENT_DIR + folder + "/"

	# الموديل (car.glb)
	var model_path := base + "car.glb"
	var has_model := ResourceLoader.exists(model_path) or FileAccess.file_exists(model_path)

	# الإعدادات (stats.json)
	var cls := "medium"
	var subtitle := ""
	var scale := 1.0
	var rotate_y := 0.0
	var lift := 0.0
	var hide_game_wheels := false
	var wheels_opts: Dictionary = {}
	var stats_path := base + "stats.json"
	if FileAccess.file_exists(stats_path):
		var f := FileAccess.open(stats_path, FileAccess.READ)
		if f != null:
			var txt := f.get_as_text()
			var json = JSON.parse_string(txt)
			if json is Dictionary:
				cls = json.get("class", "medium")
				subtitle = json.get("subtitle", "")
				scale = float(json.get("scale", 1.0))
				rotate_y = float(json.get("rotate_y", 0.0))
				if bool(json.get("flip", false)):
					rotate_y += 180.0
				lift = float(json.get("lift", 0.0))
				hide_game_wheels = bool(json.get("hide_game_wheels", false))
				var wj = json.get("wheels", {})
				if wj is Dictionary:
					wheels_opts = wj
	# كل السيارات فئة واحدة متوازنة (بطلب المستخدم)
	cls = "medium"

	# ارتفاعات الأسلحة (weapons.json - اختياري)
	var weapons_y: Dictionary = {}
	var wpath := base + "weapons.json"
	if FileAccess.file_exists(wpath):
		var wf := FileAccess.open(wpath, FileAccess.READ)
		if wf != null:
			var wjson = JSON.parse_string(wf.get_as_text())
			if wjson is Dictionary:
				weapons_y = wjson

	# الصورة (portrait.png)
	var portrait: Texture2D = null
	var portrait_path := base + "portrait.png"
	if FileAccess.file_exists(portrait_path):
		var img := Image.new()
		var err := img.load(portrait_path)
		if err == OK:
			portrait = ImageTexture.create_from_image(img)

	if subtitle == "":
		subtitle = CLASSES[cls]["label"]

	return {
		"name": folder,
		"folder": folder,
		"model_path": model_path if has_model else "",
		"portrait": portrait,
		"class": cls,
		"subtitle": subtitle,
		"scale": scale,
		"rotate_y": rotate_y,
		"lift": lift,
		"hide_game_wheels": hide_game_wheels,
		"wheels": wheels_opts,
		"weapons_y": weapons_y,
		"stats": CLASSES[cls]
	}


func _default_character() -> Dictionary:
	return {
		"name": "الذيب",
		"folder": "",
		"model_path": "",
		"portrait": null,
		"class": "medium",
		"subtitle": "المقاتل المتوازن",
		"scale": 1.0,
		"rotate_y": 0.0,
		"lift": 0.0,
		"hide_game_wheels": false,
		"wheels": {},
		"weapons_y": {},
		"stats": CLASSES["medium"]
	}


# يحمّل موديل GLB، يرجّع Node3D جاهز للإضافة، أو null لو فشل
func load_model(model_path: String) -> Node3D:
	if model_path == "":
		print("[Content] مسار الموديل فارغ")
		return null
	if not FileAccess.file_exists(model_path):
		print("[Content] الملف غير موجود: ", model_path)
		return null
	# الطريقة 1: append_from_file - يحل التكستشرات الخارجية (Textures/...) تلقائياً
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(model_path, state)
	if err == OK:
		var scene := doc.generate_scene(state)
		if scene != null:
			print("[Content] تم تحميل الموديل: ", model_path)
			return scene
	print("[Content] append_from_file فشل (err=", err, ") نجرب الطريقة الثانية...")
	# الطريقة 2: من البايتات مع تمرير مجلد الملف (لحل المسارات النسبية)
	var doc2 := GLTFDocument.new()
	var state2 := GLTFState.new()
	var bytes := FileAccess.get_file_as_bytes(model_path)
	if not bytes.is_empty():
		var err2 := doc2.append_from_buffer(bytes, model_path.get_base_dir(), state2)
		if err2 == OK:
			var scene2 := doc2.generate_scene(state2)
			if scene2 != null:
				print("[Content] تم تحميل الموديل (buffer): ", model_path)
				return scene2
		print("[Content] append_from_buffer فشل (err=", err2, ")")
	# الطريقة 3: عبر نظام الاستيراد (لو مستورد بالمحرر)
	if ResourceLoader.exists(model_path):
		var res = load(model_path)
		if res is PackedScene:
			print("[Content] تم تحميل الموديل (imported): ", model_path)
			return res.instantiate()
	print("[Content] فشل تحميل الموديل نهائياً: ", model_path)
	print("[Content] 💡 لو الموديل من Kenney: انسخ مجلد Textures جنب car.glb بنفس مجلد الشخصية")
	return null


func get_character(index: int) -> Dictionary:
	if index < 0 or index >= characters.size():
		return _default_character()
	return characters[index]


func count() -> int:
	return characters.size()
