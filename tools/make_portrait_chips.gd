extends SceneTree
## Derives the small square portrait chips (assets/portraits/<id>.png, shown
## at 48x48 in council/court screens) from the user-provided full-body art in
## assets/portraits/full/ — head-and-shoulders top crop, written at 96x96 so
## the chip stays crisp on hi-dpi. Replaces the retired hand-authored pixel
## art (tools/gen_portraits.py, deleted with it).
##
## Run headless from the repo root:
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
##     --script tools/make_portrait_chips.gd

const CHIP_SIZE := 96
const FULL_DIR := "res://assets/portraits/full/"
const OUT_DIR := "res://assets/portraits/"
## id -> crop mode: "top" = head crop from full-body art, "center" = centered
## square (the round-table medallion is a single central motif).
const SOURCES := {
	"char_chancellor": "top", "char_marshal": "top", "char_steward": "top",
	"char_spymaster": "top", "char_chaplain": "top", "you": "top",
	"round_table": "center",
}

func _init() -> void:
	for id in SOURCES:
		var src := ProjectSettings.globalize_path(FULL_DIR + id + ".png")
		var img := Image.load_from_file(src)
		if img == null:
			push_error("cannot load " + src)
			continue
		var side := mini(img.get_width(), img.get_height())
		var x := (img.get_width() - side) / 2
		var y := 0 if SOURCES[id] == "top" else (img.get_height() - side) / 2
		var chip := img.get_region(Rect2i(x, y, side, side))
		chip.resize(CHIP_SIZE, CHIP_SIZE, Image.INTERPOLATE_LANCZOS)
		var dst := ProjectSettings.globalize_path(OUT_DIR + id + ".png")
		var err := chip.save_png(dst)
		print("%s -> %s (%s)" % [id, dst, "ok" if err == OK else str(err)])
	quit()
