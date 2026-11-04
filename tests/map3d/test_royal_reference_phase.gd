extends GutTest
## Phase input component only; no contact/provider/CERT or visual acceptance.
const Phase = preload("res://scripts/map3d/map3d_royal_reference_phase.gd")
const Natural = Phase.Natural
const Q: int = BodyMotion.LOCOMOTION_Q
const MAXIMUM: int = BodyMotion.JSON_INTEGER_MAX
var _source: Dictionary = {"length": 8.0 / 15.0, "identity": {"source_sha256": "native-control"}}
var _config: Dictionary = {"time_day_seconds": 8.0, "battle_substeps": 10, "identity": {"frozen": "config-control"}}

func _binding(day: int = 0, substep: int = 2) -> Dictionary:
	return {"unit": "王军", "slot": "12", "abs_day": day, "substep": substep, "substep_count": 10,
		"receipt": "a".repeat(64), "op_index": 0,
		"op": BodyMotion._loco_op("hold", 0, Q, [0, 0], [0, 0], 0),
		"placement_identity": "b".repeat(64), "law_identity": Phase.law(_source, _config).sha256,
		"previous": {}, "next": {}, "classification": "production_bound"}

func _request(binding: Dictionary, time_q: Variant = 0, initial: Variant = null) -> Dictionary:
	return {"binding": binding.duplicate(true), "time_q": time_q, "initial_native_phase": initial}

func _sample(binding: Dictionary, time_q: Variant = 0) -> Dictionary:
	return Phase.sample(_source, _config, _request(binding, time_q), binding)

func test_exact_large_cursor_keeps_fraction_and_winding() -> void:
	var result: Dictionary = Phase.coordinate(8.0, 10, 8.0 / 15.0, MAXIMUM, 9, 1, 0)
	assert_true(result.ok)
	# Independent Python Fraction.from_float oracle on frozen binary64 inputs.
	assert_eq(result.phase_numerator, "140738051305281421312")
	assert_eq(result.phase_denominator, "375299968947541328125")
	assert_eq(result.winding, "135107988821114880")
	assert_ne(result.phase, Phase.coordinate(8.0, 10, 8.0 / 15.0, MAXIMUM, 9, 0, 0).phase)

func test_length_prefixed_utf8_sha53_identity() -> void:
	assert_eq(Phase.phase_seed("王军", "12").h, 1326330281534435, "independent hashlib oracle")
	assert_ne(Phase.phase_seed("ab", "12").h, Phase.phase_seed("ab1", "2").h)
	for slot: Variant in ["01", "-1", "1.0", "+1", "", "9007199254740992", 1, null]:
		assert_false(Phase.phase_seed("unit", slot).ok, str(slot))
	assert_false(Phase.phase_seed("", "0").ok)
	assert_true(Phase.phase_seed("unit", str(MAXIMUM)).ok)

func test_hand_phase_seam_and_full_winding() -> void:
	var start: Dictionary = Phase.proof_interval([1, 10], [3, 2], [2, 1])
	assert_eq(start.phase_numerator, "1")
	assert_eq(start.phase_denominator, "10")
	assert_eq(start.winding, "3")
	var end: Dictionary = Phase.proof_interval([1, 10], [3, 2], [9, 4])
	assert_eq(end.phase, .475)
	var seam: Dictionary = Phase.proof_interval([9, 10], [3, 2], [1, 15])
	assert_eq(seam.phase, 0.0, "D=.2 at u=1/3")
	assert_eq(seam.winding, "1")
	var turn: Dictionary = Phase.proof_interval([1, 10], [3, 2], [2, 3])
	assert_eq(turn.phase, .1)
	assert_eq(turn.winding, "1", "equal residues still traverse a whole loop")
	assert_almost_eq(Phase.coordinate(8.0, 10, 8.0 / 15.0, 0, 2, 250000, 900719925474099).phase, .475, 1e-15)

func test_day_seam_full_extrema_and_sampling_order() -> void:
	for day: int in [0, 1, MAXIMUM - 1]:
		var left: Dictionary = Phase.coordinate(8.0, 10, 8.0 / 15.0, day, 9, Q, 19)
		var right: Dictionary = Phase.coordinate(8.0, 10, 8.0 / 15.0, day + 1, 0, 0, 19)
		assert_eq(left, right)
	for n: int in [1, MAXIMUM]:
		for day: int in [0, MAXIMUM]:
			for q: int in [0, 1, Q - 1, Q]:
				assert_true(Phase.coordinate(8.0, n, .5, day, n - 1, q, MAXIMUM).ok)
	var binding: Dictionary = _binding()
	var expected: Dictionary = _sample(binding, 730000)
	for q: int in [0, Q, 730000, 1, 730000, 730000]:
		_sample(binding, q)
	assert_eq(_sample(binding, 730000), expected, "pause/1x/4x/FPS/offscreen cannot alter a copied cursor")
	assert_eq(Phase.sample(_source, _config, JSON.parse_string(JSON.stringify(_request(binding, 730000))), JSON.parse_string(JSON.stringify(binding))), expected)

func test_frozen_values_types_and_ranges_reject() -> void:
	for bad: Variant in [0.0, -1.0, INF, NAN, "8", null, true]:
		assert_false(Phase.coordinate(bad, 10, .5, 0, 0, 0, 0).ok)
		assert_false(Phase.coordinate(8.0, 10, bad, 0, 0, 0, 0).ok)
	for bad: Variant in [0, -1, 1.5, "10", null, true, MAXIMUM + 1]:
		assert_false(Phase.coordinate(8.0, bad, .5, 0, 0, 0, 0).ok)
	for bad: Variant in [-1, .5, MAXIMUM + 1, "1", null, true]:
		assert_false(Phase.coordinate(8.0, 10, .5, bad, 0, 0, 0).ok)
	assert_false(Phase.coordinate(8.0, 10, .5, 0, 10, 0, 0).ok)
	assert_false(Phase.coordinate(8.0, 10, .5, 0, 0, Q + 1, 0).ok)
	assert_false(Phase.coordinate(8.0, 10, .5, 0, 0, 0, MAXIMUM + 1).ok)

func test_stale_source_config_receipt_and_every_binding_field() -> void:
	var binding: Dictionary = _binding()
	for key: String in binding:
		var request: Dictionary = _request(binding)
		request.binding.erase(key)
		assert_false(Phase.sample(_source, _config, request, binding).ok, key)
	for key: String in ["unit", "slot", "receipt", "placement_identity", "law_identity"]:
		var request: Dictionary = _request(binding)
		request.binding[key] += "changed"
		assert_false(Phase.sample(_source, _config, request, binding).ok, key)
	for key: String in ["abs_day", "substep", "substep_count", "op_index"]:
		var request: Dictionary = _request(binding)
		request.binding[key] += 1
		assert_false(Phase.sample(_source, _config, request, binding).ok, key)
	for config: Dictionary in [{"time_day_seconds": 9.0, "battle_substeps": 10, "identity": _config.identity}, {"time_day_seconds": 8.0, "battle_substeps": 9, "identity": _config.identity}]:
		assert_eq(Phase.sample(_source, config, _request(binding), binding).reason, "stale_source_or_config" if config.battle_substeps == 10 else "substep_count")
	var changed: Dictionary = _source.duplicate(true)
	changed.identity.source_sha256 = "changed"
	assert_eq(Phase.sample(changed, _config, _request(binding), binding).reason, "stale_source_or_config")
	changed = _source.duplicate(true)
	changed.length = 12.0
	assert_false(Phase.sample(changed, _config, _request(binding), binding).ok)

func test_adoption_and_endpoint_only_never_replay_or_invent_neighbor() -> void:
	var binding: Dictionary = _binding()
	var phase: float = _sample(binding).phase
	assert_true(Phase.sample(_source, _config, _request(binding, 0, phase), binding).ok)
	assert_eq(Phase.sample(_source, _config, _request(binding, 0, fmod(phase + .5, 1.0)), binding).reason, "initial_native_phase_mismatch")
	binding.classification = "endpoint_only"
	assert_false(_sample(binding, 0).ok)
	var endpoint: Dictionary = _sample(binding, Q)
	assert_true(endpoint.ok)
	assert_eq(endpoint.classification, "endpoint_only")
	assert_false(endpoint.transition_claim)
	assert_eq(endpoint.next_status, "UNAVAILABLE_NEIGHBOR")
	assert_eq(endpoint.phase, endpoint.exit.phase)

func test_proof_domain_never_acquires_production_receipt() -> void:
	for a: float in [0.0, .11, .73, .999999999]:
		for b: float in [0.0, .11, .73, .999999999]:
			var pair: Dictionary = Phase.proof_pair(a, b)
			assert_true(pair.ok)
			assert_eq(pair.classification, "proof_domain_control")
			assert_false(pair.has("receipt"))
	var binding: Dictionary = _binding()
	binding.classification = "proof_domain_control"
	assert_false(_sample(binding).ok)

func test_binary64_exponent_extrema_against_independent_fraction_oracles() -> void:
	var r0: Dictionary = Phase.coordinate(_from_bits(0x7fefffffffffffff), 1, _from_bits(1), 9007199254740991, 0, 999999, 9007199254740991)
	assert_true(r0.ok, str(r0))
	if not r0.ok: return
	assert_eq((r0.phase_numerator + "/" + r0.phase_denominator + "/" + r0.winding).sha256_text(), "359e91f191eed897e7f53285a65fc29bb606bad15bc8b37178702981c78ff6b7")
	assert_eq(Phase._bits(r0.phase), "678313d1afadcf3f")
	assert_eq(Phase._bits(r0.native_time), "0000000000000000")
	var r1: Dictionary = Phase.coordinate(_from_bits(1), 9007199254740991, _from_bits(0x7fefffffffffffff), 9007199254740991, 9007199254740990, 1, 0)
	assert_true(r1.ok, str(r1))
	if not r1.ok: return
	assert_eq((r1.phase_numerator + "/" + r1.phase_denominator + "/" + r1.winding).sha256_text(), "00e79ae599197254244cfb2051965378fdedb3f0f37d53f3a041923baef79647")
	assert_eq(Phase._bits(r1.phase), "0000000000000000")
	assert_eq(Phase._bits(r1.native_time), "0000000000002000")
	var r2: Dictionary = Phase.coordinate(8.0, 10, 0.5333333333333333, 0, 2, 250000, 900719925474099)
	assert_true(r2.ok)
	assert_eq((r2.phase_numerator + "/" + r2.phase_denominator + "/" + r2.winding).sha256_text(), "957855b65f74f9556930223b2625321fe40254941c697448448f6e2515c0a482")
	assert_eq(Phase._bits(r2.phase), "676666666666de3f")
	assert_eq(Phase._bits(r2.native_time), "37d069039d36d03f")
	var r3: Dictionary = Phase.coordinate(1.0, 1, 1.0, 0, 0, 0, 9007199254740991)
	assert_true(r3.ok)
	assert_eq((r3.phase_numerator + "/" + r3.phase_denominator + "/" + r3.winding).sha256_text(), "0c4bb5f508d2fadb75f3c4b1f8d47907247e159323af3b71b2b10497d2683fbb")
	assert_eq(Phase._bits(r3.phase), "ffffffffffffef3f")
	assert_eq(Phase._bits(r3.native_time), "ffffffffffffef3f")

func test_copied_neighbors_receipt_day_and_operation_continuity() -> void:
	var binding: Dictionary = _binding(5, 0)
	var previous: Dictionary = _binding(4, 9)
	for key: String in ["previous", "next", "classification"]: previous.erase(key)
	previous.receipt = "c".repeat(64)
	binding.previous = previous
	assert_true(_sample(binding).ok)
	for key: String in previous:
		var bad: Dictionary = binding.duplicate(true)
		bad.previous.erase(key)
		assert_false(_sample(bad).ok, "missing neighbor " + key)
	var bad: Dictionary = binding.duplicate(true)
	bad.previous.abs_day = 3
	assert_false(_sample(bad).ok)
	bad = binding.duplicate(true)
	bad.previous.op.turn_udeg = 1
	assert_false(_sample(bad).ok)
	var next: Dictionary = _binding(5, 1)
	for key: String in ["previous", "next", "classification"]: next.erase(key)
	next.receipt = "d".repeat(64)
	binding.next = next
	assert_true(_sample(binding, Q).ok)
	bad = binding.duplicate(true)
	bad.next.unit = "foreign"
	assert_false(_sample(bad).ok)
	bad = binding.duplicate(true)
	bad.next.op.a = [1, 0]
	assert_false(_sample(bad).ok)

func test_move_pivot_and_active_hold_use_identical_reference() -> void:
	var binding: Dictionary = _binding()
	var reference: Dictionary = _sample(binding, 730000)
	for kind: String in ["move", "pivot", "hold"]:
		binding.op.kind = kind
		binding.op.b = [1, 0] if kind == "move" else [0, 0]
		binding.op.turn_udeg = -1 if kind == "pivot" else 0
		var result: Dictionary = _sample(binding, 730000)
		assert_true(result.ok)
		assert_eq(result.phase_numerator, reference.phase_numerator)
		assert_eq(result.phase_denominator, reference.phase_denominator)
		assert_eq(result.winding, reference.winding)
		assert_ne(result.entry.phase, result.exit.phase)

func test_real_detached_native_length_identity_and_keys() -> void:
	var calibration: Resource = load("res://assets/3D/units/royal/royal_locomotion_source.tres")
	var extracted: Dictionary = calibration.extract()
	assert_true(extracted.ok)
	if not extracted.ok: return
	var animation: Animation = extracted.source.animation
	var source: Dictionary = {"length": animation.length, "identity": extracted.source.identity.duplicate(true)}
	var config: Dictionary = {"time_day_seconds": animation.length, "battle_substeps": 1, "identity": {"fixture": "native-length"}}
	var binding: Dictionary = _binding(0, 0)
	binding.substep_count = 1
	binding.law_identity = Phase.law(source, config).sha256
	var result: Dictionary = Phase.sample(source, config, _request(binding, 730000), binding)
	assert_true(result.ok)
	assert_eq(result.rate_numerator, "1")
	assert_eq(result.rate_denominator, "1")
	assert_ne(animation.length, 12.0)
	var seen: Dictionary = {}
	for track: int in animation.get_track_count():
		for key: int in animation.track_get_key_count(track):
			var q: int = clampi(roundi(animation.track_get_key_time(track, key) / animation.length * Q), 0, Q)
			for side: int in [-1, 0, 1]:
				var at: int = clampi(q + side, 0, Q)
				if seen.has(at): continue
				seen[at] = true
				var sampled: Dictionary = Phase.sample(source, config, _request(binding, at), binding)
				assert_true(sampled.ok)
				assert_gte(sampled.native_time, 0.0)
				assert_lte(sampled.native_time, animation.length)
	var changed: Dictionary = source.duplicate(true)
	changed.identity.source_sha256 = "stale"
	assert_false(Phase.sample(changed, config, _request(binding), binding).ok)

func test_malformed_admission_operations_law_and_queries_reject_atomically() -> void:
	var binding: Dictionary = _binding()
	for bad: Variant in [null, true, "packet", [], 1]:
		assert_false(Phase.law(bad, _config).ok)
		assert_false(Phase.law(_source, bad).ok)
		assert_false(Phase.sample(_source, _config, bad, binding).ok)
		assert_false(Phase.sample(_source, _config, _request(binding), bad).ok)
		assert_false(Phase.proof_interval(bad, [1, 1], [1, 1]).ok)
	for key: String in binding.op:
		var bad: Dictionary = binding.duplicate(true)
		bad.op.erase(key)
		assert_false(_sample(bad).ok, key)
	for key: String in ["t0_q", "t1_q", "yaw0_udeg", "turn_udeg"]:
		for value: Variant in [null, true, "0", .5, INF]:
			var bad: Dictionary = binding.duplicate(true)
			bad.op[key] = value
			assert_false(_sample(bad).ok, key)
	for bad: Variant in [-1, Q + 1, .5, "0", null, true]: assert_false(_sample(binding, bad).ok)
	var bad_source: Dictionary = _source.duplicate(true)
	bad_source.identity = {"not_json": Vector3.ZERO}
	assert_false(Phase.law(bad_source, _config).ok)
	bad_source.identity = {"nonfinite": NAN}
	assert_false(Phase.law(bad_source, _config).ok)
	var request: Dictionary = _request(binding)
	request.extra = true
	assert_false(Phase.sample(_source, _config, request, binding).ok)
	assert_false(Phase.proof_interval([0, 0], [1, 1], [1, 1]).ok)
	assert_false(Phase.proof_interval([1, 1], [1, 1], [1, 1]).ok)
	assert_false(Phase.proof_pair(0, .5).ok)
	assert_false(Phase.proof_pair(.5, 1.0).ok)

func test_surviving_slot_identity_transfers_and_does_not_renumber() -> void:
	var binding: Dictionary = _binding()
	var before: Dictionary = _sample(binding, 10)
	# A newly admitted owner/receipt does not seed phase; unrelated slots may vanish.
	binding.receipt = "e".repeat(64)
	binding.placement_identity = "f".repeat(64)
	var after: Dictionary = _sample(binding, 10)
	assert_eq(after.phase_seed, before.phase_seed)
	assert_eq(after.phase_numerator, before.phase_numerator)
	assert_eq(after.winding, before.winding)
	var other: Dictionary = binding.duplicate(true)
	other.slot = "13"
	_sample(other, 10)
	assert_eq(_sample(binding, 10), after)

func test_coordinate_controls_are_explicitly_proof_domain_only() -> void:
	var result: Dictionary = Phase.coordinate(8.0, 10, 8.0 / 15.0, 0, 0, 0, 0)
	assert_true(result.ok)
	assert_eq(result.get("classification", ""), "proof_domain_control")
	assert_false(result.has("receipt"))

func test_malformed_move_cannot_claim_admitted_operation() -> void:
	var binding: Dictionary = _binding()
	binding.op.kind = "move"
	assert_false(_sample(binding).ok, "zero-length move is not an admitted move")


func _from_bits(word: int) -> float:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_u64(0, word)
	return bytes.decode_double(0)

func test_rounding_near_seam_preserves_exact_residue_and_winding() -> void:
	var result: Dictionary = Phase.coordinate(.8527477583182907, 1, 1.0000000000000004, 0, 0, Q, 1326330281534435)
	assert_true(result.ok)
	assert_eq(result.phase_numerator, "2253601067072408722852997097355")
	assert_eq(result.phase_denominator, "2253601067072408825682945114112")
	assert_eq(result.winding, "0", "rounding the lookup cannot create a modular seam")
	assert_eq(result.phase, 1.0, "diagnostic approximation only")
	assert_eq(result.native_time, 1.0000000000000004)

func test_lookup_rounds_nearest_even_including_subnormals() -> void:
	assert_eq(Phase._float(Natural.of(9007199254740993), Natural.of(9007199254740992)), 1.0)
	assert_eq(Phase._float(Natural.of(9007199254740995), Natural.of(9007199254740992)), 1.0000000000000004)
	assert_eq(Phase._float(Natural.of(1), Natural.of(1).shift(1075)), 0.0)
	assert_eq(Phase._float(Natural.of(3), Natural.of(1).shift(1075)), _from_bits(2))


func test_cyclic_or_nonstring_source_identity_is_not_serializable() -> void:
	var source: Dictionary = _source.duplicate(true)
	var cyclic: Dictionary = {}
	cyclic["self"] = cyclic
	source.identity = cyclic
	assert_false(Phase.law(source, _config).ok)
	cyclic.clear()
	source.identity = {1: "nonstring-key"}
	assert_false(Phase.law(source, _config).ok)
