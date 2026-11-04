class_name Map3DRoyalJetMath
extends RefCounted
## Dual real value/derivative intervals plus coupled native-value error.
## Affines are row-major 3x4; derivative bottom rows are zero.

const EPS: float = 0.00001 # Native Animation::_find / Math::is_zero_approx.
const U32: float = 0.00000011920928955078125
const TINY32: float = 1.1754943508222875e-38
const U64: float = 2.220446049250313e-16
const TINY64: float = 2.2250738585072014e-308
# Interval endpoint inputs are bounded by 2^100; even input FTZ in a product
# loses <2^101*2^-1022. 2^-900 encloses that loss and output FTZ as well.
const INTERVAL_FTZ: float = 1.1830521861667747e-271
const SIN_ERROR: float = 3.552713678800501e-15
const SINF_ERROR: float = 0.0000002384185791015625

var issue: String = ""


func _matmul(a: Array, b: Array) -> Array:
	var out: Array = []
	for row: int in 3:
		for col: int in 4:
			var scalar: PackedFloat64Array = _c(0.0)
			for k: int in 3:
				scalar = _add(scalar, _mul(a[row * 4 + k], b[k * 4 + col]))
			if col == 3:
				scalar = _add(scalar, a[row * 4 + 3])
			out.append(scalar)
	return out


func _point(matrix: Array, point: Array) -> Array:
	var out: Array = []
	for row: int in 3:
		var scalar: PackedFloat64Array = _c(0.0)
		for col: int in 3:
			scalar = _add(scalar, _mul(matrix[row * 4 + col], point[col]))
		out.append(_add(scalar, matrix[row * 4 + 3]))
	return out


static func _matrix_finite(matrix: Array) -> bool:
	for scalar: PackedFloat64Array in matrix:
		for value: float in scalar:
			if not is_finite(value) or absf(value) >= 1.2676506002282294e30:
				return false
	return true


static func _constant_matrix(t: Transform3D) -> Array:
	var matrix: Array = []
	for row: int in 3:
		for col: int in 3:
			matrix.append(_c(t.basis[col][row]))
		matrix.append(_c(t.origin[row]))
	return matrix


static func _vector(value: Variant) -> Array:
	var out: Array = []
	for i: int in (4 if value is Quaternion else 3):
		out.append(_c(value[i]))
	return out


static func _packet(matrix: Array, length: float) -> Dictionary:
	var result: Dictionary = {}
	for key: String in ["extension_lower", "extension_upper", "time_derivative_lower", "time_derivative_upper", "native_error"]:
		result[key] = PackedFloat64Array()
	for scalar: PackedFloat64Array in matrix:
		result.extension_lower.append(scalar[0]); result.extension_upper.append(scalar[1])
		result.time_derivative_lower.append(scalar[2]); result.time_derivative_upper.append(scalar[3])
		result.native_error.append(scalar[4])
	result.time_derivative = PackedFloat64Array()
	result.phase_derivative = PackedFloat64Array()
	result.phase_derivative_lower = PackedFloat64Array()
	result.phase_derivative_upper = PackedFloat64Array()
	for i: int in matrix.size():
		var value: float = matrix[i][2] + (matrix[i][3] - matrix[i][2]) * 0.5
		result.time_derivative.append(value); result.phase_derivative.append(value * length)
		result.phase_derivative_lower.append(_down(matrix[i][2] * length))
		result.phase_derivative_upper.append(_up(matrix[i][3] * length))
	return result


static func _c(value: float) -> PackedFloat64Array:
	return PackedFloat64Array([value, value, 0.0, 0.0, 0.0])


func _cast(a: PackedFloat64Array, bits: int) -> PackedFloat64Array:
	var out: PackedFloat64Array = a.duplicate()
	out[4] = _ua(a[4], _round_error(_ua(_magnitude(a), a[4]), bits))
	return out


func _add(a: PackedFloat64Array, b: PackedFloat64Array, bits: int = 32) -> PackedFloat64Array:
	var lo: float = _down(a[0] + b[0])
	var hi: float = _up(a[1] + b[1])
	var error: float = _ua(_ua(a[4], b[4]), 2.0 * _tiny(bits))
	error = _ua(error, _round_error(_ua(maxf(absf(lo), absf(hi)), error), bits))
	return PackedFloat64Array([lo, hi, _down(a[2] + b[2]), _up(a[3] + b[3]), error])


func _sub(a: PackedFloat64Array, b: PackedFloat64Array, bits: int = 32) -> PackedFloat64Array:
	return _add(a, PackedFloat64Array([-b[1], -b[0], -b[3], -b[2], b[4]]), bits)


func _mul(a: PackedFloat64Array, b: PackedFloat64Array, bits: int = 32) -> PackedFloat64Array:
	var real: Array[float] = _product(a[0], a[1], b[0], b[1])
	var left: Array[float] = _product(a[2], a[3], b[0], b[1])
	var right: Array[float] = _product(a[0], a[1], b[2], b[3])
	var ae: float = _ua(a[4], _tiny(bits))
	var be: float = _ua(b[4], _tiny(bits))
	var error: float = _ua(_ua(_um(_magnitude(a), be), _um(_magnitude(b), ae)), _um(ae, be))
	error = _ua(error, _round_error(_ua(maxf(absf(real[0]), absf(real[1])), error), bits))
	return PackedFloat64Array([real[0], real[1], _down(left[0] + right[0]), _up(left[1] + right[1]), error])


func _square(a: PackedFloat64Array) -> PackedFloat64Array:
	var out: PackedFloat64Array = _mul(a, a)
	out[0] = 0.0 if a[0] <= 0.0 and a[1] >= 0.0 else _down(minf(a[0] * a[0], a[1] * a[1]))
	return out


func _div(a: PackedFloat64Array, b: PackedFloat64Array, bits: int = 32) -> PackedFloat64Array:
	var minimum: float = minf(absf(b[0]), absf(b[1]))
	if (b[0] <= 0.0 and b[1] >= 0.0) or minimum <= _ua(b[4], _tiny(bits)) or minimum < 7.888609052210118e-31:
		issue = "denominator_not_separated"
		return _c(0.0)
	var inverse: Array[float] = [_down(1.0 / b[1]), _up(1.0 / b[0])]
	var value: Array[float] = _product(a[0], a[1], inverse[0], inverse[1])
	var ab: Array[float] = _product(a[0], a[1], b[2], b[3])
	var da: Array[float] = _product(a[2], a[3], b[0], b[1])
	var den: Array[float] = [_down(minimum * minimum), _up(maxf(b[0] * b[0], b[1] * b[1]))]
	var deriv: Array[float] = _product(_down(da[0] - ab[1]), _up(da[1] - ab[0]), _down(1.0 / den[1]), _up(1.0 / den[0]))
	var magnitude: float = maxf(absf(value[0]), absf(value[1]))
	var error: float = _up(_ua(_ua(a[4], _tiny(bits)), _um(magnitude, _ua(b[4], _tiny(bits)))) / _down(_down(minimum - b[4]) - _tiny(bits)))
	error = _ua(error, _round_error(_ua(magnitude, error), bits))
	return PackedFloat64Array([value[0], value[1], deriv[0], deriv[1], error])


func _sin(a: PackedFloat64Array, bits: int) -> PackedFloat64Array:
	if a[0] - a[4] < -0.5 or a[1] + a[4] > 0.5:
		issue = "sine_domain"
		return _c(0.0)
	var lo: Array[float] = _trig_point(a[0], false)
	var hi: Array[float] = _trig_point(a[1], false)
	var cl: Array[float] = _trig_point(a[0], true)
	var cr: Array[float] = _trig_point(a[1], true)
	var cosine: Array[float] = [minf(cl[0], cr[0]), 1.0 if a[0] <= 0.0 and a[1] >= 0.0 else maxf(cl[1], cr[1])]
	var derivative: Array[float] = _product(cosine[0], cosine[1], a[2], a[3])
	return PackedFloat64Array([lo[0], hi[1], derivative[0], derivative[1], _ua(a[4], (SIN_ERROR if bits == 64 else SINF_ERROR))])


## Alternating series through sin degree21 / cos degree20, |x|<=1/2.
## Recurrence intervals include coefficient division and every binary64 operation.
static func _trig_point(x: float, cosine: bool) -> Array[float]:
	var initial: float = 1.0 if cosine else x
	var term: Array[float] = [initial, initial]
	var sum: Array[float] = term.duplicate()
	var square: Array[float] = [_down(x * x), _up(x * x)]
	for k: int in range(1, 11):
		var denominator: float = float((2 * k - 1) * (2 * k) if cosine else (2 * k) * (2 * k + 1))
		term = _product(term[0], term[1], -square[1], -square[0])
		term = [_down(term[0] / denominator), _up(term[1] / denominator)]
		sum = [_down(sum[0] + term[0]), _up(sum[1] + term[1])]
	# The next term bounds the entire alternating tail, with outward arithmetic.
	var denominator: float = 22.0 * 21.0 if cosine else 22.0 * 23.0
	var tail: float = _up(_um(maxf(absf(term[0]), absf(term[1])), square[1]) / denominator)
	return [_down(sum[0] - tail), _up(sum[1] + tail)]


func _round_error(magnitude: float, bits: int) -> float:
	if not is_finite(magnitude) or magnitude >= 1.2676506002282294e30:
		issue = "arithmetic_range"
		return INF
	return _ua(_um(magnitude, (U32 if bits == 32 else U64)), _tiny(bits))


static func _ua(a: float, b: float) -> float:
	return _up(a + b)


static func _um(a: float, b: float) -> float:
	return _up(a * b)


static func _tiny(bits: int) -> float:
	return TINY32 if bits == 32 else TINY64


static func _magnitude(a: PackedFloat64Array) -> float:
	return maxf(absf(a[0]), absf(a[1]))


static func _product(al: float, au: float, bl: float, bu: float) -> Array[float]:
	if maxf(maxf(absf(al), absf(au)), maxf(absf(bl), absf(bu))) >= 1.2676506002282294e30:
		return [-INF, INF]
	return [_down(minf(minf(al * bl, al * bu), minf(au * bl, au * bu))),
		_up(maxf(maxf(al * bl, al * bu), maxf(au * bl, au * bu)))]


static func _f32(value: float) -> float:
	return PackedFloat32Array([value])[0]


static func _up(value: float) -> float:
	return _next(value + INTERVAL_FTZ)


static func _next(value: float) -> float:
	if not is_finite(value):
		return value
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, value)
	var bits: int = bytes.decode_s64(0)
	if (bits & 0x7fffffffffffffff) == 0:
		bytes.encode_s64(0, 1)
	else:
		bytes.encode_s64(0, bits + (1 if bits >= 0 else -1))
	return bytes.decode_double(0)


static func _negative(value: float) -> bool:
	# Floating comparisons may treat a negative subnormal as -0 under FTZ.
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, value)
	var bits: int = bytes.decode_s64(0)
	return bits < 0 and (bits & 0x7fffffffffffffff) != 0


static func _down(value: float) -> float:
	return -_up(-value)
