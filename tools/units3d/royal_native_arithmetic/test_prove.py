"""Independent exact bounds and tamper controls for the native receipt."""
import json
import copy
from fractions import Fraction as F
import importlib.util
from pathlib import Path
import subprocess
import sys
import struct
import tempfile
import unittest

TOOL = Path(__file__).with_name("prove.py")
SPEC = importlib.util.spec_from_file_location("native_arithmetic", TOOL)
proof = importlib.util.module_from_spec(SPEC)
if TOOL.exists():
    SPEC.loader.exec_module(proof)


def fixture(platform="macos-arm64"):
    """Synthetic identity envelope; native integration supplies the actual process."""
    records = []
    linux = platform == "linux-x86_64"
    profiles = proof.LINUX_PROFILE if linux else proof.MAC_PROFILE
    image_id = "" if linux else "01" * 16
    for name, profile in profiles.items():
        records.append([dict(profile, symbol=name, image_id=proof.LINUX_ID if linux else proof.MAC_ID,
                             image_path="/usr/lib/x86_64-linux-gnu/libm.so.6" if linux else "/usr/lib/system/libsystem_m.dylib",
                             dlsym_equal=not (linux and name == "acosf"),
                             image_base="0x100000", slot="0x200000",
                             target=hex(0x100000 + profile["entry_offset"]))])
    return {"schema": proof.SCHEMA,
            "native": {"schema": 1, "platform": platform, "pid": 17,
                       "engine_path": "/fixture/Godot", "engine_version": "Godot Engine v4.7.2.stable.official",
                       "engine_version_components": [4, 7, 2],
                       "engine_image_id": image_id, "imports": records,
                       "header_sha256": "02" * 32, "selected_engine_sha256": "01" * 32},
            "engine": {"pid": 17, "executable": "/fixture/Godot", "architecture": "x86_64" if linux else "arm64",
                       "version": {"string": "4.7.2-stable (official)", "major": 4, "minor": 7, "patch": 2},
                       "executable_sha256": "01" * 32, "collector_sha256": "03" * 32},
            "acquisition": {"engine_sha256": "01" * 32, "engine_image_id": image_id,
                            "selected_binary_image_ids": [] if linux else [image_id],
                            "header_sha256": "02" * 32, "collector_sha256": "03" * 32,
                            "source_sha256": proof.file_hash(TOOL.with_name("capture.c")),
                            "script_sha256": proof.file_hash(TOOL.with_name("capture.gd"))}}


class NativeArithmeticTests(unittest.TestCase):
    def test_generated_output_must_be_ignored_scratch(self):
        proof.require_ignored(proof.ROOT.parents[2] / ".superpowers/royal-native-arithmetic/test-output")
        with self.assertRaisesRegex(proof.Rejected, "output_not_ignored"):
            proof.require_ignored(TOOL.with_name("unignored-output"))

    def test_rip_reference_uses_instruction_end_and_signed_displacement(self):
        code = {"code_offset": 0x100, "code": "c5fb100500000000"}
        self.assertEqual(proof.rip_target(code, 0x100, 4, 8), 0x108)
        code = {"code_offset": 0x200, "code": "c4e2f1a905fcffffff"}
        self.assertEqual(proof.rip_target(code, 0x200, 5, 9), 0x205)

    def test_native_disjoint_code_and_constant_reads_have_exact_extent(self):
        profile = {"code_offset": 0x100, "code": "00010203",
                   "extra_code": [{"offset": 0x200, "bytes": "11223344"}],
                   "operands": [{"offset": 0x400, "count": 8, "bytes": "000000000000f03f"}]}
        self.assertEqual(proof.read_memory(profile, 0x201, 2), bytes.fromhex("2233"))
        self.assertEqual(proof.coefficients(profile, 0x400, 1), [1])
        with self.assertRaisesRegex(proof.Rejected, "outside_capture"):
            proof.read_memory(profile, 0x203, 2)

    def test_selected_disk_uuid_and_build_id_are_independent_of_process_claim(self):
        macho = bytearray(56)
        struct.pack_into("<I", macho, 0, 0xfeedfacf)
        struct.pack_into("<I", macho, 16, 1)
        struct.pack_into("<II", macho, 32, 0x1b, 24)
        macho[40:56] = bytes(range(16))
        elf = bytearray(64 + 56 + 32)
        elf[:6] = b"\x7fELF\x02\x01"
        struct.pack_into("<Q", elf, 32, 64)
        struct.pack_into("<HH", elf, 54, 56, 1)
        struct.pack_into("<IIQQQQ", elf, 64, 4, 0, 120, 0, 0, 32)
        struct.pack_into("<III", elf, 120, 4, 16, 3)
        elf[132:136] = b"GNU\0"
        elf[136:152] = bytes(range(16))
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "selected"
            for raw in (macho, elf):
                path.write_bytes(raw)
                self.assertEqual(proof.binary_image_ids(path), [bytes(range(16)).hex()])
            # Official Linux editor builds can have no GNU build-ID note.
            struct.pack_into("<H", elf, 56, 0)
            path.write_bytes(elf)
            self.assertEqual(proof.binary_image_ids(path), [])
            path.write_bytes(b"unknown binary")
            with self.assertRaisesRegex(proof.Rejected, "missing_selected_binary"):
                proof.binary_image_ids(path)

    def test_hand_polynomial_and_uniform_rounding_bounds(self):
        # (1+2x)(3-x)+4 = 7+5x-2x²; norm at |x|<=1/2 is 10.
        a, b = proof.Ball([1, 2]), proof.Ball([3, -1])
        result = a.fma(b, proof.constant(4))
        self.assertEqual(result.p, [7, 5, -2])
        self.assertEqual(result.norm(), 10)
        self.assertGreaterEqual(result.e, F(10, 2 ** 52))
        self.assertLess(result.e, F(11, 2 ** 52))
        self.assertGreaterEqual(proof.rnd(F(1), 24), F(1, 2 ** 23))
        self.assertEqual(proof.up(F(0)), 0)
        self.assertGreaterEqual(proof.rnd(F(2) ** -1074), F(2) ** -1022)
        with self.assertRaisesRegex(proof.Rejected, "finite_range"):
            proof.rnd(F(2) ** 100)

    def test_positive_acos_tail_has_hand_bounded_constant_polynomial_case(self):
        error, output = proof.positive_acos_bound(proof.Ball([1], radius=F(1, 10)))
        self.assertGreater(error, F(2, 15))
        self.assertLess(error, F(1, 6))
        self.assertGreater(output, F(1, 3))

    def test_linux_sine_equations_bound_all_native_table_indices(self):
        # Arithmetic equations on captured bits; public Linux authority remains gated.
        bounds = proof.linux_sine_bounds(proof.LINUX_PROFILE)
        self.assertGreater(bounds["sin"], 0)
        self.assertLessEqual(bounds["sin"], F(2) ** -48)
        self.assertGreater(bounds["sinf"], 0)
        self.assertLessEqual(bounds["sinf"], F(2) ** -22)

    def test_linux_acos_equations_refuse_unobserved_positive_addend(self):
        profile = copy.deepcopy(proof.LINUX_PROFILE["acosf"])
        profile["operands"] = [record for record in profile["operands"] if record["offset"] != 0x9c7b0]
        with self.assertRaisesRegex(proof.Rejected, "outside_capture"):
            proof.linux_acos_bound(profile)

    def test_linux_closed_receipt_includes_wrapper_endpoint_and_rounding_paths(self):
        capture = fixture("linux-x86_64")
        receipt = proof.prove(capture)
        self.assertEqual(receipt["profile"], "linux-x86_64/" + proof.LINUX_ID)
        for name, upper in [("sin", F(2) ** -48), ("sinf", F(2) ** -22), ("acosf", F(2) ** -22)]:
            self.assertGreater(F(receipt["theorems"][name]["derived_absolute_error"]), 0)
            self.assertLessEqual(F(receipt["theorems"][name]["derived_absolute_error"]), upper)
        proof.verify_receipt(receipt, capture)

    def test_linux_control_table_coefficient_and_resolution_mutations_reject(self):
        original = fixture("linux-x86_64")
        for index, field, offset in [(0, "extra_code", 0x6e0c0), (2, "extra_code", 0x78160),
                                     (0, "operands", 0xd2be0), (2, "operands", 0xd3de0),
                                     (2, "operands", 0x9c7b0)]:
            bad = copy.deepcopy(original)
            record = bad["native"]["imports"][index][0]
            item = next(v for v in record[field] if v["offset"] <= offset < v["offset"] + len(v["bytes"]) // 2)
            data = bytearray.fromhex(item["bytes"])
            data[offset - item["offset"]] ^= 1
            item["bytes"] = data.hex()
            with self.assertRaisesRegex(proof.Rejected, "instruction_or_constant"):
                proof.prove(bad)
        bad = copy.deepcopy(original)
        bad["native"]["imports"][2][0]["dlsym_equal"] = True
        with self.assertRaisesRegex(proof.Rejected, "unresolved_import"):
            proof.prove(bad)

    def test_exact_short_path_theorems_cover_original_declared_domains(self):
        receipt = proof.prove(fixture())
        self.assertEqual(receipt["status"], "closed_scalar_value_proof")
        for name, upper in [("sin", F(2) ** -48), ("sinf", F(2) ** -22), ("acosf", F(2) ** -22)]:
            theorem = receipt["theorems"][name]
            self.assertGreater(F(theorem["derived_absolute_error"]), 0)
            self.assertLessEqual(F(theorem["derived_absolute_error"]), upper)
            self.assertEqual(F(theorem["outward_absolute_error"]), upper)
        self.assertEqual(receipt["theorems"]["acosf"]["domain"], ["9/10", "1"])

    def test_malformed_envelopes_are_atomic_rejections(self):
        for section, value in [("native", []), ("engine", None), ("acquisition", "untrusted")]:
            bad = fixture()
            bad[section] = value
            with self.assertRaises(proof.Rejected, msg=section):
                proof.prove(bad)
        for field, value in [("imports", []), ("schema", True), ("pid", -1),
                             ("engine_version_components", [4, 7, 99])]:
            bad = fixture()
            bad["native"][field] = value
            with self.assertRaises(proof.Rejected, msg=field):
                proof.prove(bad)
        for native_key, engine_key in [("engine_image_id", "engine_image_id"), ("engine_path", "executable")]:
            bad = fixture("linux-x86_64")
            bad["native"][native_key] = None
            bad["acquisition" if native_key == "engine_image_id" else "engine"][engine_key] = None
            with self.assertRaises(proof.Rejected, msg=native_key):
                proof.prove(bad)

    def test_each_instruction_constant_and_import_identity_mutation_rejected(self):
        original = fixture()
        # Alter actual coefficient bits, a branch opcode, entry identity and resolution.
        for index, relative in [(0, 0x998), (0, 0xfa8), (1, 0x32e8), (1, 0x3480),
                                (2, 0xbb58), (2, 0xbc90)]:
            bad = copy.deepcopy(original)
            record = bad["native"]["imports"][index][0]
            code = bytearray.fromhex(record["code"])
            code[relative - record["code_offset"]] ^= 1
            record["code"] = code.hex()
            with self.assertRaisesRegex(proof.Rejected, "instruction_or_constant"):
                proof.prove(bad)
        for field, value in [("image_id", "00" * 16), ("dlsym_equal", False),
                             ("target", "0x12345"), ("symbol", "cos"),
                             ("image_path", "/different/libm")]:
            bad = copy.deepcopy(original)
            bad["native"]["imports"][0][0][field] = value
            with self.assertRaises(proof.Rejected, msg=field):
                proof.prove(bad)

    def test_process_header_source_and_engine_identity_mutation_rejected(self):
        for section, field, value in [("native", "pid", 18), ("native", "engine_path", "/other"),
                                      ("native", "engine_image_id", "00" * 16),
                                      ("engine", "architecture", "x86_64"),
                                      ("engine", "executable_sha256", "ff" * 32),
                                      ("acquisition", "header_sha256", "ff" * 32),
                                      ("acquisition", "collector_sha256", "ff" * 32),
                                      ("acquisition", "source_sha256", "ff" * 32),
                                      ("acquisition", "script_sha256", "ff" * 32)]:
            bad = fixture()
            bad[section][field] = value
            with self.assertRaises(proof.Rejected, msg=field):
                proof.prove(bad)

    def test_receipt_mutations_are_recomputed_instead_of_trusted(self):
        capture = fixture()
        receipt = proof.prove(capture)
        proof.verify_receipt(receipt, capture)
        for key, value in [("status", "accepted_JETS"), ("capture_sha256", "ff" * 32),
                           ("engine_sha256", "ff" * 32), ("sha256", "ff" * 32)]:
            bad = copy.deepcopy(receipt)
            bad[key] = value
            with self.assertRaisesRegex(proof.Rejected, "receipt_mismatch"):
                proof.verify_receipt(bad, capture)
        receipt["theorems"]["sin"]["outward_absolute_error"] = "0"
        with self.assertRaisesRegex(proof.Rejected, "receipt_mismatch"):
            proof.verify_receipt(receipt, capture)

    def test_unknown_profile_emits_witness_and_never_receipt(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            capture = root / "capture.json"
            receipt = root / "receipt.json"
            capture.write_text(json.dumps({"schema": 1, "platform": "unknown"}))
            run = subprocess.run([sys.executable, str(TOOL), "--verify", str(capture),
                                  "--receipt", str(receipt)], text=True, capture_output=True)
            self.assertNotEqual(run.returncode, 0)
            self.assertIn("unknown_profile", run.stdout)
            self.assertFalse(receipt.exists())


if __name__ == "__main__":
    unittest.main()
