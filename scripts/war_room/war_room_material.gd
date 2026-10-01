class_name WarRoomMaterial
extends RefCounted
## The table material's uniforms (spec 2026-10-01-war-room-design §2), bound
## at every lay from the palette and balance.csv.

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
}


static func bind(mat: ShaderMaterial, repo: DataRepository, sheet_rect: Rect2, table_w: float, depth: float) -> void:
	var pal: Dictionary = repo.war_palette
	for key in ["paper", "paper_age", "ink", "sea_ink"]:
		mat.set_shader_parameter(key, pal[key])
	for uniform: String in SHADER_KEYS:
		mat.set_shader_parameter(uniform, repo.bal(String(SHADER_KEYS[uniform])))
	mat.set_shader_parameter("table_m", Vector2(table_w, depth))
	var grid := repo.bal("war_grid_km") * WarSheets.px_per_unit(repo)
	mat.set_shader_parameter("grid_cells", sheet_rect.size / grid)
	mat.set_shader_parameter("tex_aspect", sheet_rect.size.y / sheet_rect.size.x)
