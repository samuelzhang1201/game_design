class_name Map3DRoyalCarrierBounds
extends RefCounted
## Pure copied-input native arithmetic and one-sided carrier enclosures.

const SHORTCUT_SQUARED: float = 13743895.0 / 137438953472.0 # exact source0.0001f, word0x38d1b717


## Source bilerp's operation tree, with each binary32 result rounded OUTWARD.
## Keeping the exact real intermediate as well covers fused multiply/add contraction.
static func _height_enclosure(h: Array[float], q: Vector2, index: Vector2i, step: float) -> Array:
	var base := Vector2(float(index.x)*step,float(index.y)*step)
	var end: Vector2 = base+Vector2(step,step)
	var dx: Array = _interval([end.x,end.x],[base.x,base.x],"-")
	var dz: Array = _interval([end.y,end.y],[base.y,base.y],"-")
	var x0: Array = _interval([end.x,end.x],[q.x,q.x],"-")
	var z0: Array = _interval([end.y,end.y],[q.y,q.y],"-")
	var x1: Array = _interval([q.x,q.x],[base.x,base.x],"-")
	var z1: Array = _interval([q.y,q.y],[base.y,base.y],"-")
	var total: Array = [0.0,0.0]
	for i in 4:
		var term: Array = _interval([h[i],h[i]],x0 if i < 2 else x1,"*")
		term = _interval(term,z0 if i % 2 == 0 else z1,"*")
		total = term if i == 0 else _interval(total,term,"+")
	return _interval(total,_interval(dx,dz,"*"),"/")


## All 32-bit endpoints are exact in binary64. Products use at most48 bits;
## +/- with exponent gap<=28 uses at most53. Otherwise pad one binary64 ULP.
## Directed brackets contain BOTH real intermediates and every IEEE32 rounding,
## so multiply/add contraction is included. FTZ/DAZ is included below normal range.
static func _interval(a: Array, b: Array, op: String, bits: int = 32) -> Array:
	if not _bounded(a) or not _bounded(b): return [-INF,INF]
	if bits == 64 and (_subnormal64(a[0]) or _subnormal64(a[1]) or _subnormal64(b[0]) or _subnormal64(b[1])): return [-INF,INF]
	var aa: Array = _seed32(a) if bits == 32 else a
	var bb: Array = _seed32(b) if bits == 32 else b
	if not _bounded(aa) or not _bounded(bb) or (op == "/" and bb[0] <= 0.0 and bb[1] >= 0.0): return [-INF,INF]
	if bb == [0.0,0.0] and op in ["+","-"]: return aa
	if aa == [0.0,0.0] and op == "+": return bb
	if (aa == [0.0,0.0] or bb == [0.0,0.0]) and op == "*": return [0.0,0.0]
	if aa == [0.0,0.0] and op == "/": return [0.0,0.0]
	if bb == [1.0,1.0] and op in ["*","/"]: return aa
	if aa == [1.0,1.0] and op == "*": return bb
	var lower: float = INF
	var upper: float = -INF
	for x: float in aa:
		for y: float in bb:
			var value: float = x+y if op == "+" else (x-y if op == "-" else (x*y if op == "*" else x/y))
			if not is_finite(value): return [-INF,INF]
			var enclosure: Array
			if bits == 32 and (absf(value) < 1.1754943508222875e-38 and value != 0.0):
				enclosure = [-1.1754943508222875e-38,1.1754943508222875e-38]
			elif bits == 32 and op == "/":
				var rounded: float = PackedFloat32Array([value])[0]
				if not is_finite(rounded): return [-INF,INF]
				var relation: float = (rounded*y-x)*y # product exact; nearby subtraction exact (Sterbenz)
				enclosure = [rounded if relation <= 0 else _next32(rounded,-1),rounded if relation >= 0 else _next32(rounded,1)]
				enclosure = _seed32(enclosure)
			elif bits == 32:
				var exact: bool = op == "*" or x == 0.0 or y == 0.0 or absi(_exponent32(x)-_exponent32(y)) <= 28
				enclosure = _seed32([value,value] if exact else [_next64(value,-1),_next64(value,1)])
			else:
				enclosure = [_next64(value,-1),_next64(value,1)]
				if absf(value) < 2.2250738585072014e-308: enclosure = [minf(enclosure[0],-2.2250738585072014e-308),maxf(enclosure[1],2.2250738585072014e-308)]
			lower = minf(lower,enclosure[0])
			upper = maxf(upper,enclosure[1])
	return [lower,upper]


static func _bounded(a: Array) -> bool:
	return a.size() == 2 and is_finite(a[0]) and is_finite(a[1]) and a[0] <= a[1]


static func _seed32(a: Array) -> Array:
	var expanded: Array = a.duplicate()
	if _subnormal64(a[0]) or _subnormal64(a[1]) or (a[0] != 0.0 and absf(a[0]) < 1.1754943508222875e-38) or (a[1] != 0.0 and absf(a[1]) < 1.1754943508222875e-38):
		expanded = [minf(a[0],-1.1754943508222875e-38),maxf(a[1],1.1754943508222875e-38)]
	var lo: float = PackedFloat32Array([expanded[0]])[0]
	var hi: float = PackedFloat32Array([expanded[1]])[0]
	if not is_finite(lo) or not is_finite(hi): return [-INF,INF]
	lo = lo if lo <= expanded[0] else _next32(lo,-1)
	hi = hi if hi >= expanded[1] else _next32(hi,1)
	return [lo,hi]


static func _subnormal64(x: float) -> bool:
	var word: int = PackedFloat64Array([x]).to_byte_array().decode_s64(0)
	return (word & 0x7ff0000000000000) == 0 and (word & 0x000fffffffffffff) != 0


static func _exponent32(x: float) -> int:
	return maxi(1,(PackedFloat32Array([x]).to_byte_array().decode_u32(0)>>23)&255)


static func _next64(x: float, direction: int) -> float:
	if not is_finite(x): return x
	if x == 0.0: return float(direction)*4.9406564584124654e-324
	var data: PackedByteArray = PackedFloat64Array([x]).to_byte_array()
	data.encode_s64(0,data.decode_s64(0)+(direction if x > 0.0 else -direction))
	return data.decode_double(0)


## Taylor degree at most96/97, interval-evaluated. Lagrange remainder <= |x|^(n+1)/(n+1)!;
## sin/cos are1-Lipschitz, so the argument interval adds its radius. No libm ULP guess.
static func _trig_interval(angle: Array, cosine: bool) -> Array:
	if not _bounded(angle): return [-1.0,1.0]
	if angle == [0.0,0.0]: return [1.0,1.0] if cosine else [0.0,0.0]
	var center: float = angle[0]+(angle[1]-angle[0])*.5
	if absf(center) > 4.0*PI: return [-1.0,1.0]
	var square: Array = _interval([center,center],[center,center],"*",64)
	var term: Array = [1.0,1.0] if cosine else [center,center]
	var total: Array = term.duplicate()
	var degree: int = 0 if cosine else 1
	for n in range(1,49):
		var denominator: float = float((2*n)*(2*n-1 if cosine else 2*n+1))
		term = _interval(_interval(term,[-square[1],-square[0]],"*",64),[denominator,denominator],"/",64)
		total = _interval(total,term,"+",64)
		degree = 2*n if cosine else 2*n+1
		if maxf(absf(term[0]),absf(term[1])) <= maxf(absf(total[0]),absf(total[1]))*2.220446049250313e-16: break
	var remainder: Array = _interval(_interval([0.0,maxf(absf(term[0]),absf(term[1]))],[absf(center),absf(center)],"*",64),[float(degree+1),float(degree+1)],"/",64)
	var radius: float = maxf(_next64(absf(angle[0]-center),1),_next64(absf(angle[1]-center),1))
	var error: float = _next64(remainder[1]+radius,1)
	return [maxf(-1.0,_next64(total[0]-error,-1)),minf(1.0,_next64(total[1]+error,1))]


static func _next32(value: float, direction: int) -> float:
	if not is_finite(value): return value
	var bytes: PackedByteArray = PackedFloat32Array([value]).to_byte_array()
	var rounded: float = bytes.decode_float(0)
	if not is_finite(rounded):
		return 3.4028234663852886e38 if rounded > 0 and direction < 0 else (-3.4028234663852886e38 if rounded < 0 and direction > 0 else rounded)
	if rounded == 0.0: return float(direction)*1.401298464324817e-45
	var bits: int = bytes.decode_s32(0)
	bytes.encode_s32(0,bits+(direction if rounded > 0 else -direction))
	return bytes.decode_float(0)


static func _pixel(t: Dictionary, index: Vector2i) -> Dictionary:
	var size: int = t.region_size
	var region := Vector2i(floori(float(index.x)/size),floori(float(index.y)/size))
	if not t.regions.has(region): return _reject("terrain_missing_region",{"region":region,"cell":index,"fallback_sea":t.sea})
	var local: Vector2i = index-region*size
	var offset: int = local.y*size+local.x
	var control: int = int(t.regions[region].control[offset])
	if is_nan(PackedInt32Array([control]).to_byte_array().decode_float(0)): control = -1
	return {"ok":true,"height":float(t.regions[region].height[offset]),"control":control,"height_word":t.regions[region].height.slice(offset,offset+1).to_byte_array().decode_u32(0)}


static func _reject(reason: String, evidence: Dictionary = {}) -> Dictionary:
	return {"ok":false,"reason":reason,"evidence":evidence,"native_covered":false,"disposition":"ADVERSE" if reason == "terrain_jump" else "UNAVAILABLE"}


static func _neg(a: Array) -> Array:
	return [-a[1],-a[0]]


static func _hull(a: Array, b: Array) -> Array:
	return [minf(a[0],b[0]),maxf(a[1],b[1])]


static func _square(a: Array) -> Array:
	var lo: Array = _interval([a[0],a[0]],[a[0],a[0]],"*")
	var hi: Array = _interval([a[1],a[1]],[a[1],a[1]],"*")
	return [0.0 if a[0] <= 0.0 and a[1] >= 0.0 else maxf(0.0,minf(lo[0],hi[0])),maxf(lo[1],hi[1])]


## The same two divisions, floor, local truncation and clamp as native get_pixel.
## A non-singleton integer image address is unavailable, never a guessed neighbor.
static func _pixel_index_box(t: Dictionary, q: Array) -> Dictionary:
	var out: Array[int] = []
	for coordinate: Array in q:
		var scaled: Array = _interval(coordinate,[float(t.spacing),float(t.spacing)],"/")
		if not _bounded(scaled) or scaled[0] < -2147483647.0 or scaled[1] > 2147483647.0: return _reject("native_index_range",{"scaled":scaled})
		var region: Array = _interval(scaled,[float(t.region_size),float(t.region_size)],"/")
		if floori(region[0]) != floori(region[1]): return _reject("native_region_rounding_cut",{"q":q,"region":region})
		var base: int = floori(region[0])*int(t.region_size)
		if base < -2147483648 or base > 2147483647: return _reject("native_region_index_range",{"base":base})
		var local: Array = _interval(scaled,[float(base),float(base)],"-")
		var lo: int = clampi(int(local[0]),0,int(t.region_size)-1)
		var hi: int = clampi(int(local[1]),0,int(t.region_size)-1)
		if lo != hi: return _reject("native_pixel_rounding_cut",{"q":q,"local":local})
		out.append(base+lo)
	return {"ok":true,"index":Vector2i(out[0],out[1])}


static func _source_pixel_box(t: Dictionary, q: Array) -> Dictionary:
	var address := _pixel_index_box(t,q)
	if not address.ok: return address
	var pixel := _pixel(t,address.index)
	if not pixel.ok: return pixel
	if not is_finite(pixel.height): return _reject("native_nonfinite_height",{"cell":address.index,"word":pixel.height_word})
	if (int(pixel.height_word)&0x7f800000) == 0 and (int(pixel.height_word)&0x007fffff) != 0:
		return _reject("native_subnormal_height_unavailable",{"cell":address.index,"word":pixel.height_word})
	pixel["index"] = address.index
	return pixel


## A box touching a moving cell cut cannot choose either one-sided gradient.
## Disk comparisons likewise require strict separation, including box endpoints.
static func _sample_enclosure(t: Dictionary, q: Array, velocity: Array, acceleration: Array, side: String) -> Dictionary:
	var pixel := _source_pixel_box(t,q)
	if not pixel.ok: return pixel
	if (pixel.control&4) != 0: return _reject("terrain_hole",{"cell":pixel.index,"fallback_sea":t.sea})
	var step: float = t.spacing
	var scaled: Array = []
	var snapped: Array = []
	for axis in 2:
		var divided: Array = _interval(q[axis],[step,step],"/")
		if not _bounded(divided): return _reject("native_coordinate_range",{"q":q})
		var moving: bool = velocity[axis] != [0.0,0.0] or acceleration[axis] != [0.0,0.0]
		if moving and ceil(divided[0]) <= floor(divided[1]):
			return _reject("native_cell_side_unresolved",{"q":q,"scaled_coordinate":divided,"axis":axis,"velocity":velocity,"acceleration":acceleration,"side":side})
		scaled.append(divided)
		var round_cell: Array = _interval(divided,[.5,.5],"+")
		var first: int = floori(round_cell[0])
		var last: int = floori(round_cell[1])
		if last-first > 1: return _reject("native_coordinate_box_too_wide",{"q":q,"snap_cells":[first,last]})
		var candidates: Array = []
		for index: int in range(first,last+1): candidates.append(_interval([float(index),float(index)],[step,step],"*"))
		snapped.append(candidates)
	var radius: Array = [INF,-INF]
	for sx: Array in snapped[0]:
		for sz: Array in snapped[1]:
			var squared: Array = _interval(_square(_interval(q[0],sx,"-")),_square(_interval(q[1],sz,"-")),"+")
			radius = _hull(radius,squared)
	if not _bounded(radius): return _reject("native_radius_range",{"q":q,"radius":radius})
	var value: Array
	var gradient: Array
	var branch: String
	if radius[1] < SHORTCUT_SQUARED:
		value = [pixel.height,pixel.height]
		gradient = [[0.0,0.0],[0.0,0.0]]
		branch = "vertex_shortcut"
	elif radius[0] > SHORTCUT_SQUARED:
		var cell: Array[int] = []
		for axis in 2:
			if floori(scaled[axis][0]) != floori(scaled[axis][1]): return _reject("native_bilinear_cell_cut",{"q":q,"scaled":scaled})
			cell.append(floori(scaled[axis][0]))
		var base: Array = [_interval([float(cell[0]),float(cell[0])],[step,step],"*"),_interval([float(cell[1]),float(cell[1])],[step,step],"*")]
		var end: Array = [_interval(base[0],[step,step],"+"),_interval(base[1],[step,step],"+")]
		var corners: Array = []
		for i in 4:
			var at: Array = [base[0] if i < 2 else end[0],base[1] if i%2 == 0 else end[1]]
			var corner := _source_pixel_box(t,at)
			if not corner.ok: return corner
			corners.append([corner.height,corner.height])
		var dx: Array = _interval(end[0],base[0],"-")
		var dz: Array = _interval(end[1],base[1],"-")
		if dx[0] <= 0.0 or dz[0] <= 0.0: return _reject("native_cell_width",{"dx":dx,"dz":dz})
		var x0: Array = _interval(end[0],q[0],"-")
		var x1: Array = _interval(q[0],base[0],"-")
		var z0: Array = _interval(end[1],q[1],"-")
		var z1: Array = _interval(q[1],base[1],"-")
		var total: Array = [0.0,0.0]
		for i in 4:
			var term: Array = _interval(_interval(corners[i],x0 if i < 2 else x1,"*"),z0 if i%2 == 0 else z1,"*")
			total = term if i == 0 else _interval(total,term,"+")
		var area: Array = _interval(dx,dz,"*")
		value = _interval(total,area,"/")
		gradient = [_interval(_interval(_interval(_interval(corners[2],corners[0],"-"),z0,"*"),_interval(_interval(corners[3],corners[1],"-"),z1,"*"),"+"),area,"/"),
			_interval(_interval(_interval(_interval(corners[1],corners[0],"-"),x0,"*"),_interval(_interval(corners[3],corners[2],"-"),x1,"*"),"+"),area,"/")]
		branch = "bilinear"
	else:
		return _reject("native_shortcut_rounding_cut",{"q":q,"radius":radius,"threshold":SHORTCUT_SQUARED})
	var derivative: Array = _interval(_interval(gradient[0],velocity[0],"*"),_interval(gradient[1],velocity[1],"*"),"+")
	var sea: float = t.sea
	if value[1] < sea: derivative = [0.0,0.0]
	elif value[0] <= sea:
		if value == [sea,sea]: derivative = [minf(0.0,derivative[0]),minf(0.0,derivative[1])] if side == "left" else [maxf(0.0,derivative[0]),maxf(0.0,derivative[1])]
		else: derivative = _hull(derivative,[0.0,0.0])
	return {"ok":true,"value":[maxf(value[0],sea),maxf(value[1],sea)],"raw":value,"derivative":derivative,"gradient":gradient,"branch":branch,"cell":pixel.index,"q":q}


static func _matrix_values(at: Transform3D) -> Array:
	var values: Array = []
	for row in 3:
		for column in 3: values.append(float(at.basis[column][row]))
		values.append(float(at.origin[row]))
	return values


static func _matrix_enclosure(left: Array, right: Transform3D) -> Array:
	var a: Array = _matrix_values(right)
	var result: Array = []
	for row in 3:
		for column in 4:
			var total: Array = [0.0,0.0]
			for k in 3: total = _interval(total,_interval(left[row*4+k],[a[k*4+column],a[k*4+column]],"*"),"+")
			result.append(_interval(total,left[row*4+3],"+") if column == 3 else total)
	return result


## Real trig/curve boxes and the EXACT copied-input native footprint value are
## united before source-branch selection. This reuses placement's primitives;
## it does not infer a global sin/cos error allowance from test observations.
static func _enclose(packet: Dictionary, query: Dictionary) -> Dictionary:
	var p: Dictionary = packet.placement
	var t: Dictionary = packet.terrain
	var origin: Vector2 = query.origin
	var velocity: Vector2 = query.origin_S
	var yaw: float = query.yaw
	var rate: float = query.yaw_S
	var origin_box: Array = query.get("origin_box",[[float(origin.x),float(origin.x)],[float(origin.y),float(origin.y)]])
	var velocity_box: Array = query.get("velocity_box",[[float(velocity.x),float(velocity.x)],[float(velocity.y),float(velocity.y)]])
	var angle_box: Array = query.get("angle_box",[yaw,yaw])
	var rate_box: Array = query.get("rate_box",[rate,rate])
	var c: Array = _trig_interval(angle_box,true)
	var s: Array = _trig_interval(angle_box,false)
	var source_origin: Vector2 = query.native_origin
	var native_offsets: PackedVector2Array = Map3DUnits.footprint(p.extent,query.native_yaw,p.k,p.ring)
	var frozen_offsets: PackedVector2Array = Map3DUnits.footprint(p.extent,0.0,p.k,p.ring)
	var locals: Array = [[[0.0,0.0],[0.0,0.0]]]
	for share: float in [.5,1.0]:
		for i: int in p.ring:
			var angle: Array = _interval(_interval([TAU,_next64(TAU,1)],[float(i),float(i)],"*",64),[float(p.ring),float(p.ring)],"/",64)
			locals.append([_interval(_interval(_trig_interval(angle,true),[float(p.extent.x),float(p.extent.x)],"*"),[share*float(p.k),share*float(p.k)],"*"),
				_interval(_interval(_trig_interval(angle,false),[float(p.extent.y),float(p.extent.y)],"*"),[share*float(p.k),share*float(p.k)],"*")])
	var samples: Array = []
	var maximum: Array = [-INF,-INF]
	for i in locals.size():
		var local: Array = locals[i]
		for axis in 2: local[axis] = _hull(local[axis],[float(frozen_offsets[i][axis]),float(frozen_offsets[i][axis])])
		var offset: Array = [_interval(_interval(local[0],c,"*"),_interval(local[1],s,"*"),"+"),_interval(_interval(local[1],c,"*"),_interval(local[0],s,"*"),"-")]
		var native_point: Vector2 = source_origin+native_offsets[i]
		var q: Array = [_hull(_interval(origin_box[0],offset[0],"+"),[float(native_point.x),float(native_point.x)]),_hull(_interval(origin_box[1],offset[1],"+"),[float(native_point.y),float(native_point.y)])]
		var v: Array = [_interval(velocity_box[0],_interval(rate_box,offset[1],"*"),"+"),_interval(velocity_box[1],_interval(rate_box,offset[0],"*"),"-")]
		var acceleration: Array = [_neg(_interval(offset[0],_square(rate_box),"*")),_neg(_interval(offset[1],_square(rate_box),"*"))]
		var sample := _sample_enclosure(t,q,v,acceleration,query.get("side","right"))
		if not sample.ok: return {"status":"UNAVAILABLE","reason":sample.reason,"evidence":sample.evidence,"sample":i}
		samples.append(sample)
		maximum = [maxf(maximum[0],sample.value[0]),maxf(maximum[1],sample.value[1])]
	var derivative: Array = [INF,-INF]
	var possible: Array[int] = []
	for i in samples.size():
		if samples[i].value[1] >= maximum[0]:
			possible.append(i)
			derivative = _hull(derivative,samples[i].derivative)
	var clear: Array = _interval(_interval([float(p.height),float(p.height)],[float(p.k),float(p.k)],"*",64),[float(p.clear),float(p.clear)],"*",64)
	var y: Array = _interval(_interval(maximum,clear,"+",64),[float(p.sink),float(p.sink)],"-",64)
	var ck: Array = _interval(c,[float(p.k),float(p.k)],"*")
	var sk: Array = _interval(s,[float(p.k),float(p.k)],"*")
	var zero: Array = [0.0,0.0]
	var pm: Array = [ck,zero,sk,_hull(origin_box[0],[float(source_origin.x),float(source_origin.x)]),zero,[float(p.k),float(p.k)],zero,y,_neg(sk),zero,ck,_hull(origin_box[1],[float(source_origin.y),float(source_origin.y)])]
	# Native axis-angle construction is itself reused at the exact copied inputs.
	for native_angle: float in [yaw,query.native_yaw]:
		var native_basis := Transform3D(Basis(Vector3.UP,native_angle).scaled(Vector3.ONE*float(p.k)),Vector3.ZERO)
		var native_values: Array = _matrix_values(native_basis)
		for row in 3:
			for column in 3: pm[row*4+column] = _hull(pm[row*4+column],[native_values[row*4+column],native_values[row*4+column]])
	var ds: Array = _interval(sk,rate_box,"*")
	var dc: Array = _interval(ck,rate_box,"*")
	var ps: Array = [_neg(ds),zero,dc,velocity_box[0],zero,zero,zero,derivative,_neg(dc),zero,_neg(ds),velocity_box[1]]
	var result: Dictionary = {"status":"ENCLOSED_CONTROL","H":_matrix_enclosure(pm,p.ancestor),"H_S":_matrix_enclosure(ps,p.ancestor),"samples":samples,"possible_active_samples":possible,"derivative_bottom_row":[0,0,0,0]}
	for field: String in ["H","H_S"]:
		for bound: Array in result[field]:
			if not _bounded(bound): return {"status":"UNAVAILABLE","reason":"native_matrix_range","evidence":{"field":field,"bound":bound}}
	return result


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
