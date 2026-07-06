extends Node

# ============================================================
#  بيانات عامة تعيش بين المشاهد (Autoload)
#  هنا تضيف شخصيات جديدة: صورة + لون سيارة + مواصفات
#  ملاحظة: damage = ضرر الرشاش (لا نهائي بس خفيف)
# ============================================================

var selected_character := 0

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
