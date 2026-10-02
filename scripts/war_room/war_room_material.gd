class_name WarRoomMaterial
extends RefCounted
## The table material's uniforms (spec 2026-10-01-war-room-design §2), bound
## at every lay from the palette and balance.csv; and the pieces' tin paint (§3).

const TIN := preload("res://scenes/war_room/materials/tin_miniature.tres")
## Tin shader uniform -> its balance key (the tin colour is war_palette's).
const TIN_KEYS := {
	"levels": "war_tin_levels", "wear": "war_tin_wear", "edge_gain": "war_tin_edge_gain",
	"rim_power": "war_tin_rim_power", "rim_weight": "war_tin_rim_weight",
	"paint_metallic": "war_tin_paint_metallic", "tin_metallic": "war_tin_metallic",
	"paint_roughness": "war_tin_paint_roughness", "tin_roughness": "war_tin_roughness",
	"specular": "war_tin_specular",
}

## Shader uniform -> the balance key it is bound from at lay (every tuned
## number is data; the shader's own defaults are only a fallback).
const SHADER_KEYS := {
	"contour_m": "war_contour_m", "index_every": "war_contour_index_every",
	"contour_alpha": "war_contour_alpha", "contour_index_alpha": "war_contour_index_alpha",
	"contour_px": "war_contour_px", "contour_index_px": "war_contour_index_px",
	"sea_hatch_per_m": "war_sea_hatch_per_m",
	"sea_hatch_alpha": "war_sea_hatch_alpha", "sea_hatch_px": "war_sea_hatch_px",
	"grid_alpha": "war_grid_alpha", "grid_px": "war_grid_px", "line_crowd_k": "war_line_crowd_k",
	"paper_age_from": "war_paper_age_from", "paper_age_mix": "war_paper_age_mix",
	"paper_roughness": "war_paper_roughness", "crease_alpha": "war_crease_alpha", "crease_px": "war_crease_px",
	"collar_ink": "war_collar_ink", "collar_shade": "war_collar_shade", "neat_px": "war_neat_px",
	"neat_gap_px": "war_neat_gap_px",
	"parchment_mottle": "war_parchment_mottle", "parchment_blotch_m": "war_parchment_blotch_m",
	"parchment_grain": "war_parchment_grain", "parchment_fox": "war_parchment_fox",
	"parchment_rim": "war_parchment_rim", "sea_wash": "war_sea_wash", "grid_deg": "war_grid_deg",
	"neat_band_alpha": "war_neat_band_alpha",
}


## Bind a laid SHEET (its `rect`, the table, and its `cell`, the neat line).
static func bind(mat: ShaderMaterial, repo: DataRepository, sheet: Dictionary, table_w: float, depth: float) -> void:
	var sheet_rect: Rect2 = sheet["rect"]
	var c: Rect2 = sheet.get("cell", sheet_rect)
	mat.set_shader_parameter("neat_uv", Vector4((c.position.x - sheet_rect.position.x) / sheet_rect.size.x,
		(c.position.y - sheet_rect.position.y) / sheet_rect.size.y,
		(c.end.x - sheet_rect.position.x) / sheet_rect.size.x, (c.end.y - sheet_rect.position.y) / sheet_rect.size.y))
	var pal: Dictionary = repo.war_palette
	# the sheet is PARCHMENT (owner 2026-10-02), the folio's pages stay vellum
	mat.set_shader_parameter("paper", pal.get("parchment", pal["paper"]))
	mat.set_shader_parameter("paper_age", pal.get("parchment_age", pal["paper_age"]))
	mat.set_shader_parameter("grid_ink", pal.get("rubric", pal["ink"]))
	for key in ["ink", "sea_ink"]:
		mat.set_shader_parameter(key, pal[key])
	for uniform: String in SHADER_KEYS:
		mat.set_shader_parameter(uniform, repo.bal(String(SHADER_KEYS[uniform])))
	mat.set_shader_parameter("table_m", Vector2(table_w, depth))
	var g := MapCoords.px_per_deg(repo) * repo.bal("war_grid_deg")
	mat.set_shader_parameter("grid_cells", sheet_rect.size / g)
	mat.set_shader_parameter("grid_phase", Vector2(fposmod(sheet_rect.position.x, g.x), fposmod(sheet_rect.position.y, g.y)) / g)
	mat.set_shader_parameter("tex_aspect", WarRoomInk.used_share(repo, sheet_rect))


## A fresh tin paint, every number bound from data (each caller sets its albedo).
static func tin(repo: DataRepository) -> ShaderMaterial:
	var mat := TIN.duplicate() as ShaderMaterial
	for uniform: String in TIN_KEYS:
		mat.set_shader_parameter(uniform, repo.bal(String(TIN_KEYS[uniform])))
	mat.set_shader_parameter("tin", repo.war_palette["tin"])
	return mat
