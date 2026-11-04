class_name Map3DRoyalReferencePhase
extends RefCounted
## Pure copied-input phase authority. No playback, admission, clock or physical claim.

const Q: int = BodyMotion.LOCOMOTION_Q
const MAX_CURSOR: int = BodyMotion.JSON_INTEGER_MAX
const VERSION: String = "royal-reference-phase-v1"

# Reuse BodyMotion's exact base-2^15 arithmetic; decimal strings preserve lifts
# beyond the JSON/int64 range. No shared engine helper is changed.
class Natural:
	extends RefCounted
	const Nat = BodyMotion._Nat
	var limbs: Array = [0]

	static func from_limbs(value: Array) -> Natural:
		var out := Natural.new()
		out.limbs = value
		return out

	static func of(value: int) -> Natural:
		return from_limbs(Nat.of(value))

	func compare(other: Natural) -> int:
		return Nat.cmp(limbs, other.limbs)

	func add(other: Natural) -> Natural:
		return from_limbs(Nat.add(limbs, other.limbs))

	func multiply(other: Natural) -> Natural:
		return from_limbs(Nat.mul(limbs, other.limbs))

	func shift(count: int) -> Natural:
		var factor: Array = []
		@warning_ignore("integer_division")
		factor.resize(count / 15 + 1)
		factor.fill(0)
		factor[-1] = 1 << (count % 15)
		return from_limbs(Nat.mul(limbs, factor))

	func bits() -> int:
		if limbs == [0]: return 0
		var top: int = limbs.back()
		var count: int = (limbs.size() - 1) * 15
		while top:
			count += 1
			top >>= 1
		return count

	func divide(other: Natural) -> Array[Natural]:
		var quotient: Array = Nat.div(limbs, other.limbs)
		return [from_limbs(quotient), from_limbs(Nat.sub(limbs, Nat.mul(quotient, other.limbs)))]

	func small() -> int:
		assert(bits() <= 63)
		return Nat.integer(limbs)

	func decimal() -> String:
		if limbs == [0]: return "0"
		var value: Array = limbs
		var out: String = ""
		while value != [0]:
			var quotient: Array = Nat.small_div(value, 10)
			out = str(Nat.integer(Nat.sub(value, Nat.mul(quotient, [10])))) + out
			value = quotient
		return out


static func _ratio(n: Natural, d: Natural) -> Array[Natural]:
	var a := n
	var b := d
	while b.limbs != [0]:
		var remainder: Natural = a.divide(b)[1]
		a = b
		b = remainder
	return [n.divide(a)[0], d.divide(a)[0]]


static func _binary64(value: float) -> Array[Natural]:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, value)
	var word: int = bytes.decode_u64(0)
	var exponent: int = (word >> 52) & 2047
	var significand: int = word & 4503599627370495
	if exponent: significand += 4503599627370496
	var power: int = exponent - 1075 if exponent else -1074
	var n := Natural.of(significand)
	var d := Natural.of(1)
	if power >= 0: n = n.shift(power)
	else: d = d.shift(-power)
	return _ratio(n, d)


# Round an exact positive rational once, nearest-even, including subnormals.
static func _float(n: Natural, d: Natural) -> float:
	if n.limbs == [0]: return 0.0
	var exponent: int = n.bits() - d.bits()
	if (n.compare(d.shift(exponent)) if exponent >= 0 else n.shift(-exponent).compare(d)) < 0: exponent -= 1
	var shift: int = 52 - maxi(exponent, -1022)
	var pair: Array[Natural] = n.shift(shift).divide(d) if shift >= 0 else n.divide(d.shift(-shift))
	var divisor: Natural = d if shift >= 0 else d.shift(-shift)
	var mantissa: int = pair[0].small()
	var half: int = pair[1].shift(1).compare(divisor)
	if half > 0 or (half == 0 and mantissa % 2): mantissa += 1
	if mantissa == 9007199254740992:
		mantissa >>= 1
		exponent += 1
	var word: int = mantissa
	if mantissa >= 4503599627370496:
		word = ((maxi(exponent, -1022) + 1023) << 52) + mantissa - 4503599627370496
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_u64(0, word)
	return bytes.decode_double(0)


static func _natural(value: Variant, maximum: int = MAX_CURSOR) -> bool:
	return (value is int or value is float) and is_finite(value) and value >= 0 and value <= maximum and value == floor(value)


static func _reject(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


static func phase_seed(unit: Variant, slot: Variant) -> Dictionary:
	if not unit is String or unit.is_empty() or not slot is String or not slot.is_valid_int() or slot != str(slot.to_int()) or slot.to_int() < 0 or slot.to_int() > MAX_CURSOR:
		return _reject("identity")
	var payload := PackedByteArray()
	for part: String in [VERSION, unit, slot]:
		var bytes: PackedByteArray = part.to_utf8_buffer()
		for i: int in range(7, -1, -1): payload.append((bytes.size() >> (8 * i)) & 255)
		payload.append_array(bytes)
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(payload)
	var digest: PackedByteArray = context.finish()
	var h: int = 0
	for i: int in 7: h = (h << 8) | digest[i]
	h >>= 3
	return {"ok": true, "h": h, "z": float(h) / 9007199254740992.0}


## Exact residue/lift are authoritative. phase is a diagnostic approximation and
## may round to 1; native_time is rounded directly from the exact residue.
static func coordinate(t: Variant, n: Variant, length: Variant, day: Variant, substep: Variant, time_q: Variant, h: Variant) -> Dictionary:
	if not (t is float or t is int) or not (length is float or length is int) or not is_finite(t) or not is_finite(length) or t <= 0 or length <= 0:
		return _reject("frozen_time_or_length")
	if not _natural(n) or n < 1 or not _natural(day) or not _natural(substep) or substep >= n or not _natural(time_q, Q) or not _natural(h):
		return _reject("cursor_or_seed_range")
	var tr: Array[Natural] = _binary64(float(t))
	var lr: Array[Natural] = _binary64(float(length))
	var rate: Array[Natural] = _ratio(tr[0].multiply(lr[1]), tr[1].multiply(lr[0]).multiply(Natural.of(int(n))))
	var sq: Natural = Natural.of(int(n)).multiply(Natural.of(int(day))).add(Natural.of(int(substep))).multiply(Natural.of(Q)).add(Natural.of(int(time_q)))
	var denominator: Natural = rate[1].multiply(Natural.of(Q)).shift(53)
	var numerator: Natural = sq.multiply(rate[0]).shift(53).add(rate[1].multiply(Natural.of(Q)).multiply(Natural.of(int(h))))
	var divided: Array[Natural] = numerator.divide(denominator)
	var residue: Array[Natural] = _ratio(divided[1], denominator)
	return {"ok": true, "classification": "proof_domain_control", "phase_numerator": residue[0].decimal(), "phase_denominator": residue[1].decimal(),
		"winding": divided[0].decimal(), "phase": _float(residue[0], residue[1]),
		"native_time": _float(residue[0].multiply(lr[0]), residue[1].multiply(lr[1])),
		"rate_numerator": rate[0].decimal(), "rate_denominator": rate[1].decimal()}


static func _bits(value: float) -> String:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, value)
	return bytes.hex_encode()


static func _identity_json(value: Variant, ancestors: Array = []) -> bool:
	if value is Dictionary or value is Array:
		for ancestor: Variant in ancestors:
			if is_same(value, ancestor): return false
		var next: Array = ancestors + [value]
		if value is Dictionary:
			for key: Variant in value:
				if not key is String or not _identity_json(value[key], next): return false
		else:
			for item: Variant in value:
				if not _identity_json(item, next): return false
		return true
	return value == null or value is String or value is bool or value is int or (value is float and is_finite(value))


## source is R1's copied {length, identity}; config is the frozen transaction's
## {time_day_seconds, battle_substeps, identity}. Call with current copies each time.
static func law(source: Variant, config: Variant) -> Dictionary:
	if not source is Dictionary or not config is Dictionary or not BodyMotion._keys(source, ["length", "identity"]) or not BodyMotion._keys(config, ["time_day_seconds", "battle_substeps", "identity"]):
		return _reject("law_schema")
	if not source.identity is Dictionary or source.identity.is_empty() or not config.identity is Dictionary or config.identity.is_empty() or not _identity_json(source.identity) or not _identity_json(config.identity):
		return _reject("law_identity_missing")
	var checked: Dictionary = coordinate(config.time_day_seconds, config.battle_substeps, source.length, 0, 0, 0, 0)
	if not checked.ok: return checked
	var identity: Dictionary = {"version": VERSION, "epoch": "0", "q": Q,
		"time_bits": _bits(float(config.time_day_seconds)), "length_bits": _bits(float(source.length)),
		"substep_count": int(config.battle_substeps), "source": source.identity.duplicate(true), "config": config.identity.duplicate(true)}
	return {"ok": true, "identity": identity, "sha256": BodyMotion._hash(identity)}


static func _binding_error(binding: Variant, current_law: Dictionary, neighbors: bool = true) -> String:
	var keys: Array = ["unit", "slot", "abs_day", "substep", "substep_count", "receipt", "op_index", "op", "placement_identity", "law_identity"]
	if neighbors: keys.append_array(["previous", "next", "classification"])
	if not binding is Dictionary or not BodyMotion._keys(binding, keys): return "binding_schema"
	if not phase_seed(binding.unit, binding.slot).ok: return "identity"
	for key: String in ["abs_day", "substep", "substep_count", "op_index"]:
		if not _natural(binding[key]): return "binding_cursor"
	if binding.substep_count != current_law.identity.substep_count or binding.substep >= binding.substep_count: return "substep_count"
	for key: String in ["receipt", "placement_identity", "law_identity"]:
		if not binding[key] is String or not BodyMotion._digest(binding[key]): return "binding_digest"
	if binding.law_identity != current_law.sha256: return "stale_source_or_config"
	var op: Variant = binding.op
	if not op is Dictionary or not BodyMotion._keys(op, ["kind", "t0_q", "t1_q", "a", "b", "yaw0_udeg", "turn_udeg"]): return "op_schema"
	if op.kind not in ["move", "pivot", "hold"] or not _natural(op.t0_q, Q) or not _natural(op.t1_q, Q) or op.t1_q <= op.t0_q:
		return "op_range"
	if not BodyMotion._loco_point(op.a) or not BodyMotion._loco_point(op.b) or not _natural(op.yaw0_udeg, BodyMotion.LOCOMOTION_TURN - 1) or not BodyMotion._loco_integer(op.turn_udeg): return "op_geometry"
	if (op.kind == "move" and op.a == op.b) or (op.kind != "pivot" and op.turn_udeg != 0) or (op.kind != "move" and op.a != op.b) or (op.kind == "pivot" and (op.turn_udeg == 0 or absi(int(op.turn_udeg)) > 180000000)): return "op_kind"
	if neighbors:
		if binding.classification not in ["production_bound", "endpoint_only"]: return "classification"
		for side: String in ["previous", "next"]:
			var neighbor: Variant = binding[side]
			if not neighbor is Dictionary: return "neighbor_schema"
			if neighbor.is_empty(): continue
			var error: String = _binding_error(neighbor, current_law, false)
			if not error.is_empty(): return "neighbor:" + error
			for key: String in ["unit", "slot", "substep_count", "placement_identity", "law_identity"]:
				if neighbor[key] != binding[key]: return "neighbor_identity"
			var left: Dictionary = neighbor if side == "previous" else binding
			var right: Dictionary = binding if side == "previous" else neighbor
			if not _adjacent(left, right): return "neighbor_discontinuity"
	return ""


static func _adjacent(left: Dictionary, right: Dictionary) -> bool:
	if left.op.b != right.op.a or posmod(int(left.op.yaw0_udeg) + int(left.op.turn_udeg), BodyMotion.LOCOMOTION_TURN) != right.op.yaw0_udeg: return false
	if left.abs_day == right.abs_day and left.substep == right.substep:
		return left.receipt == right.receipt and left.op_index < MAX_CURSOR and right.op_index == left.op_index + 1 and left.op.t1_q == right.op.t0_q
	if left.op.t1_q != Q or right.op.t0_q != 0 or right.op_index != 0 or left.receipt == right.receipt: return false
	if left.abs_day == right.abs_day: return left.substep < MAX_CURSOR and right.substep == left.substep + 1
	return left.abs_day < MAX_CURSOR and right.abs_day == left.abs_day + 1 and left.substep == left.substep_count - 1 and right.substep == 0


## admitted is a trusted copied admission projection, NOT a caller-created proof
## of admission. This pure function checks request equality; it never grants an
## engine receipt. Missing neighbors stay explicitly unavailable.
static func sample(source: Variant, config: Variant, request: Variant, admitted: Variant) -> Dictionary:
	var current_law: Dictionary = law(source, config)
	if not current_law.ok: return current_law
	if not request is Dictionary or not BodyMotion._keys(request, ["binding", "time_q", "initial_native_phase"]): return _reject("request_schema")
	var error: String = _binding_error(admitted, current_law)
	if not error.is_empty(): return _reject(error)
	if not _binding_error(request.binding, current_law).is_empty() or BodyMotion._hash(request.binding) != BodyMotion._hash(admitted): return _reject("admission_mismatch")
	if not _natural(request.time_q, Q) or request.time_q < admitted.op.t0_q or request.time_q > admitted.op.t1_q: return _reject("sample_range")
	if admitted.classification == "endpoint_only" and (request.time_q != Q or admitted.op.t1_q != Q): return _reject("endpoint_only")
	var seeded: Dictionary = phase_seed(admitted.unit, admitted.slot)
	var result: Dictionary = coordinate(config.time_day_seconds, config.battle_substeps, source.length, admitted.abs_day, admitted.substep, request.time_q, seeded.h)
	var initial: Variant = request.initial_native_phase
	if initial != null and (request.time_q != admitted.op.t0_q or not initial is float or not is_finite(initial) or initial < 0.0 or initial >= 1.0 or _bits(initial) != _bits(result.phase)):
		return _reject("initial_native_phase_mismatch")
	result["classification"] = admitted.classification
	result["law_identity"] = current_law.sha256
	result["binding_sha256"] = BodyMotion._hash(admitted)
	result["phase_identity"] = BodyMotion._hash([admitted.unit, admitted.slot, current_law.sha256, str(seeded.h)])
	result["time_q"] = int(request.time_q)
	result["phase_seed"] = str(seeded.h)
	result["entry"] = coordinate(config.time_day_seconds, config.battle_substeps, source.length, admitted.abs_day, admitted.substep, admitted.op.t0_q, seeded.h)
	result["exit"] = coordinate(config.time_day_seconds, config.battle_substeps, source.length, admitted.abs_day, admitted.substep, admitted.op.t1_q, seeded.h)
	result["previous_status"] = "UNAVAILABLE_NEIGHBOR" if admitted.previous.is_empty() else "copied_admitted"
	result["next_status"] = "UNAVAILABLE_NEIGHBOR" if admitted.next.is_empty() else "copied_admitted"
	result["transition_claim"] = false
	return result


## Exact rational hand controls, deliberately without production binding/receipts.
## Independent phase pairs remain in the proof domain; no production override.
static func proof_interval(offset: Variant, rate: Variant, duration: Variant) -> Dictionary:
	for rational: Variant in [offset, rate, duration]:
		if not rational is Array or rational.size() != 2 or not _natural(rational[0]) or not _natural(rational[1]) or rational[1] == 0: return _reject("proof_rational")
	if offset[0] >= offset[1]: return _reject("proof_phase")
	var n: Natural = Natural.of(int(offset[0])).multiply(Natural.of(int(rate[1]))).multiply(Natural.of(int(duration[1]))).add(Natural.of(int(offset[1])).multiply(Natural.of(int(rate[0]))).multiply(Natural.of(int(duration[0]))))
	var d: Natural = Natural.of(int(offset[1])).multiply(Natural.of(int(rate[1]))).multiply(Natural.of(int(duration[1])))
	var pair: Array[Natural] = n.divide(d)
	var residue: Array[Natural] = _ratio(pair[1], d)
	return {"ok": true, "classification": "proof_domain_control", "phase": _float(residue[0], residue[1]),
		"phase_numerator": residue[0].decimal(), "phase_denominator": residue[1].decimal(), "winding": pair[0].decimal()}


static func proof_pair(phi0: Variant, phi1: Variant) -> Dictionary:
	for value: Variant in [phi0, phi1]:
		if not value is float or not is_finite(value) or value < 0.0 or value >= 1.0: return _reject("proof_phase")
	return {"ok": true, "classification": "proof_domain_control", "phi0": phi0, "phi1": phi1}
