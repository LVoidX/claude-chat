extends Node3D
## The look of all on-screen text: a book-like serif font for every label, button and 3D sign (a font already on
## Windows, so nothing to ship: Palatino Linotype, else Book Antiqua, Georgia...). Set as Godot's fallback font, so
## it reaches every part's UI without them doing anything. Also recolours world.gd's own HUD text to match.

const FONTS := ["Palatino Linotype", "Book Antiqua", "Georgia", "Cambria", "Times New Roman", "serif"]
const PARCHMENT := Color("#f2e6c8")
const GOLD := Color("#ffd24d")

var ctx: Dictionary
var W


func build(c: Dictionary) -> void:
	ctx = c
	W = ctx["world"]
	if not ctx.has("ui_font"):
		var f := SystemFont.new()
		f.font_names = PackedStringArray(FONTS)
		f.font_weight = 500
		f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		ctx["ui_font"] = f
	ThemeDB.fallback_font = ctx["ui_font"]  # 3D signs (Label3D) and anything without a theme
	var theme := Theme.new()  # and every Control in the window (panels, buttons)
	theme.default_font = ctx["ui_font"]
	get_tree().root.theme = theme
	ctx["ui_theme"] = theme  # (a CanvasLayer stops the window's theme: HUD panels set this themselves)
	for l in [W.notice_label, W.quest_label]:  # world.gd's labels: parchment and gold instead of green
		if l:
			l.add_theme_font_override("font", ctx["ui_font"])
	if W.notice_label:
		W.notice_label.add_theme_color_override("font_color", PARCHMENT)
		W.notice_label.add_theme_constant_override("outline_size", 5)
	if W.quest_label:
		W.quest_label.add_theme_color_override("font_color", GOLD)
