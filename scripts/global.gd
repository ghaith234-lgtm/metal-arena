extends Node

# ============================================================
#  بيانات عامة تعيش بين المشاهد (Autoload)
#  هنا تضيف شخصيات جديدة: صورة + لون سيارة + مواصفات
#  ملاحظة: damage = ضرر الرشاش (لا نهائي بس خفيف)
# ============================================================

var selected_character := 0
var selected_map := 0

# ⚙️ إعدادات المباراة (يحددها اللاعب بشاشة الميدان)
var score_to_win := 8            # عدد القتلات للفوز
var time_of_day := -1.0          # -1 = عشوائي | 0.3 = صباح | 0.5 = ظهر | 0.75 = غروب | 0.95 = ليل
var rain := -1                   # -1 = عشوائي | 0 = صافي | 1 = ممطر
var enemy_count := 4             # عدد الأعداء (1-7)
var difficulty := 2              # 1=سهل | 2=عادي | 3=صعب | 4=قاتل

# أوضاع اللعب
enum Mode { AI, LOCAL_MP, PRACTICE }
var game_mode: Mode = Mode.AI      # الافتراضي: ضد الذكاء الاصطناعي

const CHARACTERS = [
	{
		"name": "الذيب",
		"desc": "المقاتل المتوازن — البادئ الأسطوري",
		"portrait": "res://assets/char1.jpg",
		"color": Color(0.85, 0.16, 0.1),
		"speed": 1.0,
		"health": 100.0,
		"damage": 5.0,
		"locked": false,
	},
	{
		"name": "الصاعقة",
		"desc": "سريع وخفيف — يضرب ويختفي",
		"portrait": "",
		"color": Color(0.95, 0.75, 0.1),
		"speed": 1.15,
		"health": 75.0,
		"damage": 4.5,
		"locked": false,
	},
	{
		"name": "المدرعة",
		"desc": "بطيء بس ما ينكسر — دبابة الساحة",
		"portrait": "",
		"color": Color(0.5, 0.25, 0.75),
		"speed": 0.85,
		"health": 145.0,
		"damage": 6.0,
		"locked": false,
	},
	{
		"name": "؟؟؟",
		"desc": "شخصية قادمة...",
		"portrait": "",
		"color": Color(0.22, 0.23, 0.26),
		"speed": 1.0,
		"health": 100.0,
		"damage": 5.0,
		"locked": true,
	},
]
