extends Node

# ============================================================
#  نظام الخرائط: يمسح مجلد الخرائط ويقرأ ملفات JSON
#  كل ملف .json = خريطة. تعدّلها أو تضيف خرائط جديدة بدون كود!
# ============================================================

const MAPS_DIR = "res://content/maps/"

var maps: Array = []


func _ready() -> void:
	_scan_maps()


func _scan_maps() -> void:
	maps.clear()
	var dir := DirAccess.open(MAPS_DIR)
	if dir != null:
		var files: Array = []
		dir.list_dir_begin()
		var f := dir.get_next()
		while f != "":
			if not dir.current_is_dir() and f.ends_with(".json"):
				files.append(f)
			f = dir.get_next()
		dir.list_dir_end()
		files.sort()
		for fname in files:
			var m := _load_map(MAPS_DIR + fname)
			if not m.is_empty():
				maps.append(m)
	if maps.is_empty():
		maps.append(_default_map())
	print("[Maps] عدد الخرائط: ", maps.size())
	for m in maps:
		print("  - ", m["name"], " | حجم: ", m["size"])


func _load_map(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var data = JSON.parse_string(file.get_as_text())
	if not (data is Dictionary):
		push_warning("[Maps] ملف خريطة تالف: " + path)
		return {}
	var d: Dictionary = data
	# قيم افتراضية لأي حقل ناقص
	return {
		"name": d.get("name", "خريطة"),
		"desc": d.get("desc", ""),
		"tags": d.get("tags", ""),
		"icon": d.get("icon", "🗺"),
		"color": _to_color(d.get("color", [0.8, 0.4, 0.2])),
		"size": float(d.get("size", 120.0)),
		"ground_color": _to_color(d.get("ground_color", [0.28, 0.42, 0.2])),
		"wall_height": float(d.get("wall_height", 4.0)),
		"pickup_range": float(d.get("pickup_range", 48.0)),
		"pickup_sets": int(d.get("pickup_sets", 1)),
		"nuke_spread": float(d.get("nuke_spread", 10.0)),
		"spawns": d.get("spawns", []),
		"roads_x": d.get("roads_x", []),
		"roads_z": d.get("roads_z", []),
		"road_width": float(d.get("road_width", 8.0)),
		"sidewalk_width": float(d.get("sidewalk_width", 2.6)),
		"dirt_patches": int(d.get("dirt_patches", 0)),
		"buildings": d.get("buildings", []),
		"trees": d.get("trees", []),
		"barrels": d.get("barrels", []),
		"random_barrels": int(d.get("random_barrels", 0)),
		"mountains": d.get("mountains", []),
		"pits": d.get("pits", []),
		"ramps": d.get("ramps", []),
		"water": d.get("water", []),
		"bridges": d.get("bridges", []),
		"tunnels": d.get("tunnels", []),
		"barriers": d.get("barriers", []),
		"random_cities": d.get("random_cities", []),
		"terrain": d.get("terrain", {}),
		"props": d.get("props", []),
		"fog": d.get("fog", true),
		"fog_color": _to_color(d.get("fog_color", [0.62, 0.66, 0.72])),
		"fog_density": float(d.get("fog_density", 0.006)),
	}


func _to_color(v) -> Color:
	if v is Array and v.size() >= 3:
		return Color(float(v[0]), float(v[1]), float(v[2]))
	return Color(0.8, 0.4, 0.2)


func _default_map() -> Dictionary:
	return {
		"name": "الساحة",
		"desc": "ساحة افتراضية",
		"tags": "",
		"icon": "🗺",
		"color": Color(0.85, 0.35, 0.15),
		"size": 120.0,
		"ground_color": Color(0.28, 0.42, 0.2),
		"wall_height": 4.0,
		"pickup_range": 48.0,
		"pickup_sets": 1,
		"nuke_spread": 10.0,
		"spawns": [],
		"roads_x": [0.0], "roads_z": [0.0], "road_width": 8.0, "sidewalk_width": 2.6,
		"dirt_patches": 0,
		"buildings": [], "trees": [], "barrels": [], "random_barrels": 0,
		"mountains": [], "pits": [], "ramps": [],
		"water": [], "bridges": [], "tunnels": [], "barriers": [],
		"random_cities": [],
		"terrain": {},
		"props": [], "fog": true, "fog_color": Color(0.62, 0.66, 0.72), "fog_density": 0.006,
	}


func get_map(i: int) -> Dictionary:
	if i < 0 or i >= maps.size():
		return _default_map()
	return maps[i]


func count() -> int:
	return maps.size()
