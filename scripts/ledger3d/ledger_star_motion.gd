# scripts/ledger3d/ledger_star_motion.gd
class_name LedgerStarMotion
extends RefCounted
## The galaxy stars' motion (owner 2026-10-01: 给光球在godot里设置一些animation，
## 轻微小幅度晃动，周边带有类似细微电流的感觉): a slight wobble of every star round
## its layout place and an electric current round its rim (owner 2026-10-01,
## later the same day: 电流可以更大更明显一点，晃动幅度也可以更大更明显). Both run on the
## shaders' real TIME (presentation only: the LEDGER holds the game clock), so
## nothing here runs per frame — this only binds the `ledger_star_wobble_*` /
## `ledger_spark_*` numbers to the materials and deals each star its seed and
## its current's weight (INSTANCE_CUSTOM). The links' ends move with their
## stars (link.gdshader, the same formula, each end's seed and drawn radius
## per vertex — `link_star`); picking and the layout stay on the layout place.

## Floats per star in a MultiMesh buffer: a 3D transform (12), its colour (4)
## and its custom data (4) — the star MultiMeshes use colours and custom data.
const STRIDE := 20

## balance.csv key -> the shared wobble uniform (star_motion.gdshaderinc).
const WOBBLE := {
	"ledger_star_wobble_share": "wobble_share",
	"ledger_star_wobble_selected": "wobble_selected_share",
	"ledger_star_wobble_period_min": "wobble_period_min",
	"ledger_star_wobble_period_max": "wobble_period_max",
	"ledger_star_wobble_ratio": "wobble_ratio",
}
## balance.csv key -> spark.gdshader's uniform.
const SPARK := {
	"ledger_spark_strength": "strength",
	"ledger_spark_width": "width",
	"ledger_spark_arcs": "arcs",
	"ledger_spark_speed": "speed",
	"ledger_spark_cover": "cover",
	"ledger_spark_max_cover": "max_cover",
	"ledger_spark_glow_share": "glow_share",
	"ledger_spark_flicker": "flicker",
	"ledger_spark_flicker_hz": "flicker_hz",
	"ledger_spark_lift": "lift",
	"ledger_spark_min_px": "min_px",
	"ledger_spark_full_px": "full_px",
	"ledger_spark_saturation": "saturation",
	"ledger_spark_core_px": "core_px",
	"ledger_spark_glow_px": "glow_px",
	"ledger_spark_glow": "glow",
	"ledger_spark_jag": "jag",
	"ledger_spark_selected_out": "sel_out",
}


## Binds the wobble to a star material (whole, dimmed or the current's) or
## to the links', whose ends move with their stars.
static func bind_wobble(m: ShaderMaterial, repo: DataRepository) -> void:
	for key: String in WOBBLE:
		m.set_shader_parameter(WOBBLE[key], repo.bal(key))


## Binds the current's numbers (and its wobble) to the spark material.
static func bind_spark(m: ShaderMaterial, repo: DataRepository) -> void:
	bind_wobble(m, repo)
	for key: String in SPARK:
		m.set_shader_parameter(SPARK[key], repo.bal(key))


## Whether the current is drawn at all (ledger_spark_strength 0: no instance).
static func sparks_on(repo: DataRepository) -> bool:
	return repo.bal("ledger_spark_strength") > 0.0


## A star's seed from its id's hash — the same every run and every redraw,
## whichever MultiMesh it is dealt to: x the wobble's phase and the current's
## turn, y the wobble's period. z is left for the current's weight.
static func seed_of(id: String) -> Color:
	var h := id.hash()
	return Color(float(h & 0xFFFF) / 65535.0, float((h >> 16) & 0xFFFF) / 65535.0, 0.0, 0.0)


## One end of a link as link.gdshader reads it (LedgerLinkMesh's `a_star` /
## `b_star`): the star's seed, its drawn radius (before the screen cap, which
## the shader applies as the stars are drawn) and 1 when it is the selected one.
static func link_star(id: String, drawn_r: float, selected: bool) -> Color:
	var c := seed_of(id)
	return Color(c.r, c.g, drawn_r, 1.0 if selected else 0.0)


## A star's custom data: its seed, its current's weight in z — the
## selected star's ledger_spark_selected, a dimmed star's (alpha under 1)
## ledger_spark_dimmed × its own perceived opacity (pow 2.2, as
## star_faint.gdshader draws its body: a current never outshines the star it
## rings), any other 1 — and in w 1 on the selected star, whose current
## spark.gdshader lays just outside its selection ring.
static func custom_of(repo: DataRepository, id: String, alpha: float, selected: bool) -> Color:
	var c := seed_of(id)
	if selected:
		c.b = repo.bal("ledger_spark_selected")
		c.a = 1.0
	elif alpha < 1.0:
		c.b = repo.bal("ledger_spark_dimmed") * pow(clampf(alpha, 0.0, 1.0), 2.2)
	else:
		c.b = 1.0
	return c


## How far past a star's disc its selection ring reaches, in SubViewport px
## (LedgerHud draws the ring ledger_ring_px wide, `gap_rings` ring widths off
## the disc, in design px): the selected star's current starts there.
static func ring_out_px(repo: DataRepository, gap_rings: float, window_scale: float) -> float:
	return repo.bal("ledger_ring_px") * (gap_rings + 1.0) * window_scale


## The band, in SubViewport px, the selected star's sparks keep to past its
## ring: one ring width (critic, fix round 2: at the star's own width they
## reached twice its radius out, across its threads and near its name).
static func ring_band_px(repo: DataRepository, window_scale: float) -> float:
	return repo.bal("ledger_ring_px") * window_scale


## The instance buffer of a star MultiMesh: for each id, in order, its laid
## transform (rows of the basis with the origin, Godot's layout), its colour
## and its custom data. One assignment hands the renderer every star.
static func pack(ids: Array[String], laid: Dictionary, cols: PackedColorArray, custom: Dictionary) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(ids.size() * STRIDE)
	for k in ids.size():
		var t: Transform3D = laid[ids[k]]
		var c: Color = cols[k]
		var u: Color = custom[ids[k]]
		var o := k * STRIDE
		var b := t.basis
		var row := [b.x.x, b.y.x, b.z.x, t.origin.x, b.x.y, b.y.y, b.z.y, t.origin.y,
			b.x.z, b.y.z, b.z.z, t.origin.z, c.r, c.g, c.b, c.a, u.r, u.g, u.b, u.a]
		for j in STRIDE:
			buf[o + j] = row[j]
	return buf


## Instance k's transform in a buffer `pack` built.
static func transform_at(buf: PackedFloat32Array, k: int) -> Transform3D:
	var o := k * STRIDE
	return Transform3D(Vector3(buf[o], buf[o + 4], buf[o + 8]), Vector3(buf[o + 1], buf[o + 5], buf[o + 9]),
		Vector3(buf[o + 2], buf[o + 6], buf[o + 10]), Vector3(buf[o + 3], buf[o + 7], buf[o + 11]))


## Instance k's colour in a buffer `pack` built.
static func colour_at(buf: PackedFloat32Array, k: int) -> Color:
	var o := k * STRIDE + 12
	return Color(buf[o], buf[o + 1], buf[o + 2], buf[o + 3])


## Instance k's custom data (seed, weight, selected) in a buffer `pack` built.
static func custom_at(buf: PackedFloat32Array, k: int) -> Color:
	var o := k * STRIDE + 16
	return Color(buf[o], buf[o + 1], buf[o + 2], buf[o + 3])
