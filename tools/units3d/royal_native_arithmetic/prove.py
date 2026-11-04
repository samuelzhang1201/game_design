"""Read-only Godot-process capture and exact scalar-value proof. No numerical fitting."""
import argparse
from fractions import Fraction as F
import hashlib
import json
from math import comb, factorial, isqrt
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys

ROOT = Path(__file__).resolve().parent
SCHEMA = "royal-native-arithmetic/1"
MAC_ID = "a3fb340f3ed530f48b649d5860f64d35"
MAC_PROFILE = {
    "sin": {
        "code_offset": 2368,
        "entry_offset": 2416,
        "code": (
            "182d4454fb21e93f407ae53b0100204183c8c96d305fe43f00004454fb21f93f00004c4c238c863d457370032e8a293b"
            "7f2303d5fd7bbfa9fd0300910820601e01c0601e800a0054c2fdff5cea031faa2020621ea2fdff5c8d3600542020621e"
            "0900f0d2ab0600540000669e0100298a21fc74d321fc0fd13f0010f1a00800540a00098a292d00aadefaff1020fc46d3"
            "211440f2de0f00cba0040054c20fc1a8c41740a9200001d1e00300cba620c19a8520c19a8424c09ac60004aa6420c19a"
            "6324c09a650005aa4224c09a440004aa807cc99ba27c099ba17cc99b000002abc27c099b2100029a22f47ed34a0101ca"
            "430401ca4a01419242fc7f93210002ca21f04092000002ca7f0000f12210c0da430001d1e30303cb2120c29a0324c39a"
            "210003aac43400545f010014c313c1a8c51b40a9e7ffff17c0f6ff100414c16c061c406d0108641e2240641e2000609e"
            "4508651e4108661e4708671e0038651e0638611e0238661e4238611e4738671e1f0040f22af9008a013600546d010014"
            "01106e1efd7bc1a8ff0f5fd62138611e0038601efd7bc1a8ff0f5fd67f2303d5fd7bbfa9fd03009100c0601ea2f2ff5c"
            "ea031faa0020621e82f2ff5cad3300540020621e0900f0d26b0600540000669e01fc74d321fc0fd13f0010f1a0fdff54"
            "292d00aafeefff1020fc46d3211440f2de0f00cba0040054c20fc1a8c41740a9200001d1e00300cba620c19a8520c19a"
            "8424c09ac60004aa6420c19a6324c09a650005aa4224c09a440004aa807cc99ba27c099ba17cc99b000002abc27c099b"
            "2100029a22f47ed32a0401ca430401ca4a01419242fc7f93210002ca21f04092000002ca7f0000f12210c0da430001d1"
            "e30303cb2120c29a0324c39a210003aae529005408010014c313c1a8c51b40a9e7ffff17e0ebff100414c16c061c406d"
            "0108641e2240641e2000609e4508651e4108661e4708671e0038651e0638611e0238661e4238611e4738671e1f0040f2"
            "0a0440ca4a0141d3002b0054150100147f2303d5fd7bbfa9fd0300910820601e01c0601e60f4ff5442e8ff5cea031faa"
            "2020621e22e8ff5c6d0b00542020621e0900f0d2cb0700540000669e0100298a21fc74d321fc0fd13f0010f100f3ff54"
            "0a00098a292d00aa5ee5ff1020fc46d3211440f2de0f00cbc0050054c20fc1a8c41740a9200001d1e00300cba620c19a"
            "8520c19a8424c09ac60004aa6420c19a6324c09a650005aa4224c09a440004aa807cc99ba27c099ba17cc99b000002ab"
            "c27c099b2100029a22f47ed34b0101ca2c0401ca430401ca42fc7f93210002ca21f04092000002ca7f0000f12210c0da"
            "430001d1e30303cb2120c29a0324c39a210003aac40000548a014192f50000940140601e6a014192af0000148a014192"
            "aa0000940140601e6a014192f0000014c313c1a8c51b40a9deffff1720e0ff100414c16c061c406d0108641e2240641e"
            "2000609e4508651e4108661e4708671e0038651e0638611e0238661e4238611e4738671e1f0040f2a10000542af9008a"
            "f40000940140601eb60000140a0440ca4a0141d3ad0000940140601e4a0141d2f2000014e703679e0640601ef5ffff17"
            "7f2303d5fd7bbfa9fd0300910820601e01c0601e00e8ff5442dbff5cea031faa4020611e22dbff5c2c0700542020621e"
            "0900f0d22b0b00540000669e0100298a21fc74d321fc0fd13f0010f120e6ff540a00098a292d00aa5ed8ff1020fc46d3"
            "211440f2de0f00cb20090054c20fc1a8c41740a9200001d1e00300cba620c19a8520c19a8424c09ac60004aa6420c19a"
            "6324c09a650005aa4224c09a440004aa807cc99ba27c099ba17cc99b000002abc27c099b2100029a22f47ed34a0501ca"
            "430401ca4a01419242fc7f93210002ca21f04092000002ca7f0000f12210c0da430001d1e30303cb2120c29a0324c39a"
            "210003aa60070058017cc19b200c439e402c4cd31000679e0084f07ee3060010420f00100108601e620cc16c5044c16c"
            "230c421f3144501f6414c16c524cc16c2410431f3248511f2514441f334c521f620cc16c5044c16c2208451f3040531f"
            "230c421f3144501f2208631e500040fd430d084e3040511f0000421f11106e1e001c236e3144501f214e601e024c711e"
            "2018621efd7bc1a8ff0f5fd6c313c1a8c51b40a9c3ffff17c0cfff100414c16c061c406d0108641e2240641e2000609e"
            "4508651e4108661e4708671e0038651e0638611e0238661e4238611e4738671ec028671eeaff00abcdffff171f2003d5"
            "35c26821a2da0fc9cd9cd11ffdd8e53d5d1f29a9e5e55abea1487d56e31dc73e03dfbf19a0012abfd0f710111111813f"
            "485555555555c5bf7f2303d5fd7bbfa9fd030091e0fdff58047cc19b800c439e402c4cd31000679e0084f07e63fdff10"
            "1f08601e620cc16c803c509284bc4092e30f421f6414c16c060c439ee413431f870c439ee517441f620cc16ce20b451f"
            "c684f07ee30f421fe784f07eff0b631e430d084e001c5f1f0028661e001c236efd7bc1a8ff0f5fd67f2303d5fd7bbfa9"
            "fd030091030000140740601ee603679ec028671ea3f9ff101f08601e620cc16ce30f421f6414c16ce413431fe517441f"
            "620cc16ce20b451fe30f421fff0b631e430d084e001c5f1f0028661e001c236efd7bc1a8ff0f5fd69b1a86a049faa8bd"
            "053f4e7b"
        ),
    },
    "sinf": {
        "code_offset": 12632,
        "entry_offset": 12632,
        "code": (
            "7f2303d5fd7bbfa9fd0300910000261e00780012231600181f00036b23160018620500541f00036b0309005400c0221e"
            "0216005c0208621e4000609e4240641ec415005c4180441f1f0040f200fc41d3000041d30002005481150010220c406d"
            "2108611e2414416d230c421f2514441f2208611e06106e1e4314431f2018431f0100679e001c212e0040621efd7bc1a8"
            "ff0f5fd6a11400103044406d2408611e2508641e320840fd9144501f8608651eb204521fc048511f0100679e001c212e"
            "0040621efd7bc1a8ff0f5fd6431000181f00036b6206005400c0221e007c185300000151211400102010008b0414406d"
            "0408641e0508651e83a8614e8140641e63547f4f8438611e8028651e031c232e0008601e60110010042cdf0c020040fd"
            "0428641e0528651e0618441f071c451f6608661e4708671ec008671e0040621efd7bc1a8ff0f5fd6e30c00181f00036b"
            "c3010054a10e001001c0221e3044406d2408611e2508641e320840fd9144501f8608651eb204521fc048511f0040621e"
            "fd7bc1a8ff0f5fd6220b001ce40a001c0000021f0008241efd7bc1a8ff0f5fd60038201efd7bc1a8ff0f5fd67f2303d5"
            "fd7bbfa9fd0300910000261e00780012c30800181f00036be3080018820400541f00036b6306005400c0221ea208005c"
            "0208621e4000609e4040641e4138601e2008611e0004084e812b001022acdf4c24acdf4c02d4624e03d4634e2108641e"
            "8144186e267c404c05cc624e06cc634e20dc656e00dc666e0068610e1f007ff24000005400f8a02e1f0040f2a0000054"
            "0140211e00040c5efd7bc1a8ff0f5fd601040c5efd7bc1a8ff0f5fd6c30300181f00036b0203005400c0221e0028601e"
            "007c185300000151810700102010008b0414406d0408641e0508651e8000609e8140641e8438611e8128651ed5ffff17"
            "6202001c2402001c01c0201e4138211e2108241e0000021f0008241efd7bc1a8ff0f5fd60038201e0104045efd7bc1a8"
            "ff0f5fd60000807f0000f0420000804cdb0f493f00008039000080320000804c83c8c96d305fe43f182d4454fb21f93f"
            "075c143326a6913c4a8f93fc6991f93ef45d94167fc056bf999689c75355a53f972eb8fcffffdfbf8f81c40f3e9429bf"
            "eb45d1af7310813f2aa068525455c5bf"
        ),
    },
    "acosf": {
        "code_offset": 47920,
        "entry_offset": 47920,
        "code": (
            "7f2303d5fd7bbfa9fd03009101c0201e02102e1e2020221e02102c1ec50600542020221e6208001c2c0100542020221e"
            "ca030054e108005c00c0221e2038601e0040621efd7bc1a8ff0f5fd602102e1e4138211e21c0221e40080010020c406d"
            "0414416d061c426d30c0611e230c421f2514441f271c461f2208611e4514431f471c451f0820201e8c000054e105005c"
            "e084501f02000014e008701e0040621efd7bc1a8ff0f5fd640070010020c406d0414416d061c426d00c0221e0108601e"
            "230c421f2514441f271c461f2208611e4514431f471c451f2108671e0000411f8103005c2038601e0040621efd7bc1a8"
            "ff0f5fd6600000542c010054260100540820201ee103679ec201005c20cc621e0040621efd7bc1a8ff0f5fd68000001c"
            "0038201efd7bc1a8ff0f5fd60000807f0000003b1f2003d51f2003d51f2003d500000044fb210940182d4454fb210940"
            "182d4454fb21f93f0000000000000000537095b23ce95e3f1068a86d1840613f8b5da3a05f7e803f3221e814ec219b3f"
            "9e3f17c38c2bbe3fe1c6c7649ea0f63f"
        ),
    },
}


class Rejected(ValueError):
    pass


def require(condition, witness):
    if not condition:
        raise Rejected(witness)


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()


def digest(value):
    return hashlib.sha256(value).hexdigest()


def file_hash(path):
    with open(path, "rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def binary_image_ids(path):
    """Read UUID/build IDs from the selected file, independently of the collector."""
    raw = Path(path).read_bytes()
    images = []
    if raw[:4] == b"\xca\xfe\xba\xbe":
        count = struct.unpack_from(">I", raw, 4)[0]
        require(count <= 32, "malformed_fat_binary")
        for i in range(count):
            _, _, offset, size, _ = struct.unpack_from(">IIIII", raw, 8 + 20 * i)
            images.append(raw[offset:offset + size])
    else:
        images.append(raw)
    ids = []
    for image in images:
        if image[:4] == b"\xcf\xfa\xed\xfe":
            count = struct.unpack_from("<I", image, 16)[0]
            offset = 32
            for _ in range(count):
                command, size = struct.unpack_from("<II", image, offset)
                require(size >= 8 and offset + size <= len(image), "malformed_macho_command")
                if command == 0x1b:
                    ids.append(image[offset + 8:offset + 24].hex())
                offset += size
        elif image[:6] == b"\x7fELF\x02\x01":
            offset = struct.unpack_from("<Q", image, 32)[0]
            entry_size, count = struct.unpack_from("<HH", image, 54)
            for i in range(count):
                kind, _, fileoff, _, _, size = struct.unpack_from("<IIQQQQ", image, offset + i * entry_size)
                if kind != 4:
                    continue
                cursor, end = fileoff, fileoff + size
                while cursor + 12 <= end:
                    ns, ds, kind = struct.unpack_from("<III", image, cursor)
                    name = image[cursor + 12:cursor + 12 + ns]
                    start = cursor + 12 + ((ns + 3) & ~3)
                    require(start + ds <= end, "malformed_elf_note")
                    if name == b"GNU\x00" and kind == 3:
                        ids.append(image[start:start + ds].hex())
                    cursor = start + ((ds + 3) & ~3)
    require(bool(ids), "missing_selected_binary_image_id")
    return ids


def floor_log2(x):
    require(x > 0, "nonpositive_log2")
    exponent = x.numerator.bit_length() - x.denominator.bit_length()
    return exponent - (x < F(2) ** exponent)


def up(x):
    require(x >= 0, "negative_error")
    if not x:
        return x
    scale = F(2) ** (95 - floor_log2(x))
    q = x * scale
    return F(-(-q.numerator // q.denominator), 1) / scale


def minnormal(bits):
    require(bits in (24, 53), "unsupported_precision")
    return F(2) ** (-126 if bits == 24 else -1022)


def rnd(bound, bits=53):
    require(0 <= bound < F(2) ** 100, "intermediate_outside_finite_range")
    # Every IEEE direction; an absolute allowance also covers result flushing.
    return up(bound * F(2) ** (1 - bits) + minnormal(bits))


def add_poly(a, b):
    out = [F(0)] * max(len(a), len(b))
    for i, x in enumerate(a):
        out[i] += x
    for i, x in enumerate(b):
        out[i] += x
    return out


def mul_poly(a, b):
    out = [F(0)] * (len(a) + len(b) - 1)
    for i, x in enumerate(a):
        for j, y in enumerate(b):
            out[i + j] += x * y
    return out


class Ball:
    """Exact polynomial plus a uniform absolute error on [-radius,radius]."""
    def __init__(self, poly, error=F(0), radius=F(1, 2)):
        self.p = list(map(F, poly))
        self.e = up(error)
        self.r = radius

    def norm(self):
        return sum(abs(c) * self.r ** i for i, c in enumerate(self.p))

    def mul(self, other, bits=53):
        return self.fma(other, Ball([0], radius=self.r), bits)

    def fma(self, other, addend, bits=53):
        require(self.r == other.r == addend.r, "different_ball_domains")
        poly = add_poly(mul_poly(self.p, other.p), addend.p)
        error = self.norm() * other.e + other.norm() * self.e + self.e * other.e + addend.e
        tiny = minnormal(bits)
        error += tiny * (self.norm() + self.e + other.norm() + other.e) + tiny * tiny + tiny
        value = Ball(poly, error, self.r)
        return Ball(poly, error + rnd(value.norm() + error, bits), self.r)

    def convert(self, bits):
        error = self.e + minnormal(53)
        return Ball(self.p, error + rnd(self.norm() + error, bits), self.r)


def constant(value, radius=F(1, 2)):
    return Ball([value], radius=radius)


def read_memory(profile, offset, count):
    raw = bytes.fromhex(profile["code"])
    start = offset - profile["code_offset"]
    require(0 <= start and start + count <= len(raw), "operand_outside_capture")
    return raw[start:start + count]


def coefficients(profile, offset, count):
    # Binary floats are decoded exactly; no host transcendental is used.
    return [F(x) for x in struct.unpack("<" + "d" * count, read_memory(profile, offset, count * 8))]


def mac_bounds(profiles):
    radius = F(1, 2)
    original = Ball([0, 1])
    x = original.fma(constant(1), constant(0))
    z = x.mul(x)
    cs = coefficients(profiles["sin"], 0xfa8, 6)
    h = constant(cs[0])
    for a in cs[1:]:
        h = z.fma(h, constant(a))
    y = x.fma(z.mul(h), original).fma(constant(1), constant(0))
    ideal = [F(0)] * 14
    for k in range(7):
        ideal[2 * k + 1] = F((-1) ** k, factorial(2 * k + 1))
    approx = sum(abs(a - b) * radius ** i for i, (a, b) in enumerate(zip(y.p, ideal)))
    sin_bound = up(y.e + approx + radius ** 15 / factorial(15))

    cs = coefficients(profiles["sinf"], 0x3480, 3)
    x = Ball([0, 1], F(2) ** -126)
    z = x.mul(x)
    x3 = x.mul(z)
    h = z.fma(constant(cs[0]), constant(cs[1]))
    y = z.mul(x3).fma(h, x3.fma(constant(cs[2]), x)).convert(24)
    ideal = [F(0)] * 8
    for k in range(4):
        ideal[2 * k + 1] = F((-1) ** k, factorial(2 * k + 1))
    approx = sum(abs(a - b) * radius ** i for i, (a, b) in enumerate(zip(y.p, ideal)))
    polynomial_bound = up(y.e + approx + radius ** 9 / factorial(9))
    tiny_radius = F(1, 4096)
    x = Ball([0, 1], F(2) ** -126, tiny_radius)
    y = x.fma(constant(F(2) ** 26, tiny_radius), x, 24).mul(constant(F(2) ** -26, tiny_radius), 24)
    tiny_bound = up(y.e + tiny_radius / 2 ** 26 + tiny_radius ** 3 / 6)

    radius = F(1, 10)
    t = Ball([0, 1], radius=radius)
    cs = coefficients(profiles["acosf"], 0xbc90, 6)
    t2 = t.mul(t)
    a = t.fma(constant(cs[0], radius), constant(cs[1], radius))
    b = t.fma(constant(cs[2], radius), constant(cs[3], radius))
    d = t.fma(constant(cs[4], radius), constant(cs[5], radius))
    h = t2.fma(t2.fma(a, b), d)
    sqrt_max = F(1, 3)
    sqrt_error = rnd(sqrt_max)
    error = up(h.norm() * sqrt_error + sqrt_max * h.e + sqrt_error * h.e)
    product_max = h.norm() * sqrt_max
    error = up(error + rnd(product_max + error))
    error = up(error + rnd(product_max + error, 24))
    scale = 1 << 120
    n = isqrt(2 * scale * scale)
    sqrt2_lo, sqrt2_hi = F(n, scale), F(n + 1, scale)
    require(sqrt2_lo ** 2 <= 2 <= sqrt2_hi ** 2, "sqrt2_bracket")
    approx = F(0)
    for k, a in enumerate(h.p):
        factor = F(comb(2 * k, k), 8 ** k * (2 * k + 1))
        approx += max(abs(a - sqrt2_lo * factor), abs(a - sqrt2_hi * factor)) * radius ** k
    require(len(h.p) == 6, "acosf_polynomial_degree")
    remainder = sqrt2_hi * (radius / 2) ** 6 / (13 * (1 - radius / 2))
    acosf_bound = up(error + sqrt_max * (approx + remainder))
    require(product_max + error < F(12, 25), "acosf_output_range")
    require(F(12, 25) * F(513, 512) < F(1, 2), "sine_argument_range")
    return {"sin": sin_bound, "sinf": max(polynomial_bound, tiny_bound), "acosf": acosf_bound}


def prove(capture):
    require(capture.get("native", {}).get("platform") == "macos-arm64", "unknown_profile")
    require(capture.get("schema") == SCHEMA, "capture_schema")
    native, engine, acquisition = capture["native"], capture["engine"], capture["acquisition"]
    require(native.get("schema") == 1, "native_schema")
    require(native.get("pid") == engine.get("pid") and type(native.get("pid")) is int, "process_identity")
    require(native.get("engine_path") == engine.get("executable"), "engine_path_identity")
    require(engine.get("architecture") == "arm64", "engine_architecture")
    require(native.get("engine_version_components") == [engine.get("version", {}).get(key) for key in ("major", "minor", "patch")], "engine_version_identity")
    require(native.get("engine_image_id") == acquisition.get("engine_image_id"), "engine_image_identity")
    require(native.get("engine_image_id") in acquisition.get("selected_binary_image_ids", []), "selected_engine_image_identity")
    require(engine.get("executable_sha256") == acquisition.get("engine_sha256"), "engine_hash_identity")
    for field in ("header_sha256", "collector_sha256", "source_sha256", "script_sha256", "engine_sha256"):
        value = acquisition.get(field)
        require(isinstance(value, str) and len(value) == 64 and all(c in "0123456789abcdef" for c in value), "missing_acquisition_" + field)
    require(acquisition["source_sha256"] == file_hash(ROOT / "capture.c"), "collector_source_identity")
    require(acquisition["script_sha256"] == file_hash(ROOT / "capture.gd"), "script_identity")
    require(isinstance(native.get("imports"), list) and len(native["imports"]) == 3, "missing_imports")
    profiles = {}
    for name, slots in zip(("sin", "sinf", "acosf"), native["imports"]):
        require(isinstance(slots, list) and len(slots) >= 1, "missing_import_" + name)
        for record in slots:
            require(record.get("symbol") == name, "import_symbol_" + name)
            require(record.get("image_id") == MAC_ID, "unknown_profile_" + name)
            require(record.get("image_path") == "/usr/lib/system/libsystem_m.dylib", "import_image_" + name)
            require(record.get("dlsym_equal") is True, "unresolved_import_" + name)
            require(int(record["target"], 16) - int(record["image_base"], 16) == record.get("entry_offset"), "import_address_" + name)
            expected = MAC_PROFILE[name]
            for field in ("entry_offset", "code_offset", "code"):
                require(record.get(field) == expected[field], "instruction_or_constant_mismatch_" + name + "_" + field)
            profiles[name] = record
    bounds = mac_bounds(profiles)
    claimed = {"sin": F(2) ** -48, "sinf": F(2) ** -22, "acosf": F(2) ** -22}
    require(all(0 < bounds[name] <= claimed[name] for name in bounds), "derived_error_exceeds_claim")
    theorem = {name: {"domain": ["9/10", "1"] if name == "acosf" else ["-1/2", "1/2"],
                      "input_format": "binary64" if name == "sin" else "binary32",
                      "derived_absolute_error": str(bound), "outward_absolute_error": str(claimed[name])}
               for name, bound in bounds.items()}
    receipt = {"schema": SCHEMA, "status": "closed_scalar_value_proof", "profile": "macos-arm64/" + MAC_ID,
               "capture_sha256": digest(canonical(capture)), "verifier_sha256": file_hash(__file__),
               "theorems": theorem, "engine_sha256": acquisition["engine_sha256"],
               "scope": "scalar values only; no derivative, source-domain, JETS or physical E acceptance",
               "assumptions": "IEEE binary32/binary64 basic operations/FMA/sqrt; all rounding directions; explicit FTZ allowances; intermediates below 2^100"}
    receipt["sha256"] = digest(canonical(receipt))
    return receipt


def verify_receipt(receipt, capture):
    require(receipt == prove(capture), "receipt_mismatch")


def run(command, directory, env=None):
    result = subprocess.run(command, cwd=directory, env=env, capture_output=True, text=True, timeout=60)
    require(result.returncode == 0, "command_failed: " + repr(command) + "\n" + result.stdout + result.stderr)
    require("SCRIPT ERROR:" not in result.stdout + result.stderr, "godot_script_error: " + result.stdout + result.stderr)
    return result.stdout


def acquire(engine, scratch):
    engine = str(Path(engine).resolve(strict=True))
    engine_hash = file_hash(engine)
    engine_ids = binary_image_ids(engine)
    scratch = scratch.resolve()
    scratch.mkdir(parents=True, exist_ok=False)
    (scratch / "project.godot").write_text('config_version=5\n[application]\nconfig/name="Native arithmetic diagnostic"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
    shutil.copyfile(ROOT / "capture.gd", scratch / "capture.gd")
    run([engine, "--headless", "--path", str(scratch), "--dump-gdextension-interface"], scratch)
    header = scratch / "gdextension_interface.h"
    require(header.is_file(), "missing_selected_engine_abi_header")
    compiler = shutil.which("cc")
    require(compiler is not None, "missing_existing_system_c_compiler")
    library = scratch / ("capture.dylib" if sys.platform == "darwin" else "capture.so")
    command = [compiler, "-std=c11", "-Wall", "-Wextra", "-Werror", "-fPIC", "-I", str(scratch), str(ROOT / "capture.c")]
    command += ["-dynamiclib"] if sys.platform == "darwin" else ["-shared", "-ldl"]
    run(command + ["-o", str(library)], scratch)
    descriptor = scratch / "capture.gdextension"
    descriptor.write_text('[configuration]\nentry_symbol="royal_native_arithmetic_init"\ncompatibility_minimum="4.7"\n[libraries]\n' + ('macos.arm64' if sys.platform == "darwin" else 'linux.x86_64') + '="' + str(library) + '"\n')
    native_path = scratch / "native.json"
    env = dict(os.environ, ROYAL_NATIVE_CAPTURE=str(native_path), ROYAL_NATIVE_EXTENSION=str(descriptor))
    log = run([engine, "--headless", "--path", str(scratch), "--script", "res://capture.gd"], scratch, env)
    (scratch / "capture.log").write_text(log)
    require(file_hash(engine) == engine_hash, "engine_changed_during_capture")
    native = json.loads(native_path.read_text())
    require(native.get("engine_image_id") in engine_ids, "loaded_engine_not_selected_binary")
    capture = {"schema": SCHEMA, "native": native,
               "engine": json.loads(Path(str(native_path) + ".engine.json").read_text()),
               "acquisition": {"engine_sha256": engine_hash,
                   "engine_image_id": native["engine_image_id"],
                   "selected_binary_image_ids": engine_ids,
                   "header_sha256": file_hash(header), "collector_sha256": file_hash(library),
                   "source_sha256": file_hash(ROOT / "capture.c"), "script_sha256": file_hash(ROOT / "capture.gd")}}
    (scratch / "capture.json").write_text(json.dumps(capture, indent=2) + "\n")
    return capture


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--verify", type=Path)
    mode.add_argument("--capture", metavar="GODOT")
    parser.add_argument("--scratch", type=Path)
    parser.add_argument("--receipt", type=Path, required=True)
    args = parser.parse_args()
    capture = None
    try:
        require(not args.receipt.exists(), "receipt_already_exists")
        if args.capture:
            require(args.scratch is not None, "explicit_ignored_scratch_required")
            capture = acquire(args.capture, args.scratch)
        else:
            capture = json.loads(args.verify.read_text())
        receipt = prove(capture)
        args.receipt.write_text(json.dumps(receipt, indent=2) + "\n")
        print(json.dumps(receipt, sort_keys=True))
        return 0
    except (Rejected, OSError, ValueError, KeyError, TypeError, subprocess.TimeoutExpired) as error:
        print(json.dumps({"status": "rejected", "witness": str(error), "capture": capture}, sort_keys=True))
        return 1


if __name__ == "__main__":
    sys.exit(main())
