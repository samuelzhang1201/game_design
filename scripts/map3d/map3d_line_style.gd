class_name Map3DLineStyle
extends RefCounted
## How one ribbon of Map3DLayerLines is drawn (border_line.gdshader): its two
## colours (a dash and its gap), the balance.csv keys of its screen widths,
## its row of Map3DPriority, and the band's extras — a one-sided ribbon, a
## colour per line in place of a's rgb, a fade away from the line by the
## curve fade_power_key names ("" linear).

var a := Color.BLACK
var b := Color.BLACK
var width_key := ""
var dash_key := ""
var gap_key := ""
var priority := 0
var edge_soft := 0.0
var one_sided := false
var colours: Array = []
var fade_across := 0.0
var fade_power_key := ""


static func solid(colour: Color, p_width_key: String, p_priority: int) -> Map3DLineStyle:
	var s := Map3DLineStyle.new()
	s.a = colour
	s.b = colour
	s.width_key = p_width_key
	s.priority = p_priority
	return s


static func dashed(p_a: Color, p_b: Color, p_width_key: String, p_dash_key: String,
		p_gap_key: String, p_priority: int) -> Map3DLineStyle:
	var s := solid(p_a, p_width_key, p_priority)
	s.b = p_b
	s.dash_key = p_dash_key
	s.gap_key = p_gap_key
	return s
