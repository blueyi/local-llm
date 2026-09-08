#!/usr/bin/env python3
"""Unit tests for hw_profiles (no network). Run: python3 scripts/lib/hw_profiles_test.py"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

LIB = Path(__file__).resolve().parent
if str(LIB) not in sys.path:
    sys.path.insert(0, str(LIB))

import hw_profiles as hp  # noqa: E402


class ParseTests(unittest.TestCase):
    def test_parse_chip_m5_max(self) -> None:
        self.assertEqual(hp.parse_chip("Apple M5 Max"), ("m5", "max"))

    def test_parse_chip_m4_base(self) -> None:
        self.assertEqual(hp.parse_chip("Apple M4"), ("m4", "base"))

    def test_parse_chip_m4_pro(self) -> None:
        self.assertEqual(hp.parse_chip("Apple M4 Pro"), ("m4", "pro"))

    def test_parse_chip_m3_ultra(self) -> None:
        self.assertEqual(hp.parse_chip("Apple M3 Ultra"), ("m3", "ultra"))

    def test_parse_chip_unknown(self) -> None:
        self.assertEqual(hp.parse_chip("Intel Core i9"), ("", ""))

    def test_quantize_ram_48(self) -> None:
        self.assertEqual(hp.quantize_ram_gb(48.0), 48)
        self.assertEqual(hp.quantize_ram_gb(47.6), 48)
        self.assertEqual(hp.quantize_ram_gb(36.0), 36)
        self.assertEqual(hp.quantize_ram_gb(18.0), 18)

    def test_quantize_ram_unbucketed(self) -> None:
        # 40GB is not a known SKU bucket; stay at 40 so it will not false-match 36/48
        self.assertEqual(hp.quantize_ram_gb(40.0), 40)


class MatchTests(unittest.TestCase):
    def test_m5_max_48_exact(self) -> None:
        probe = hp.MachineProbe(
            mem_gb=48.0,
            mem_bucket=48,
            chip="Apple M5 Max",
            family="m5",
            variant="max",
        )
        hit = hp.match_profile(probe)
        self.assertIsNotNone(hit)
        assert hit is not None
        self.assertEqual(hit.id, "m5-max-48")
        self.assertEqual(hit.lineup, "full-48")

    def test_m4_pro_48(self) -> None:
        probe = hp.MachineProbe(
            mem_gb=48.0,
            mem_bucket=48,
            chip="Apple M4 Pro",
            family="m4",
            variant="pro",
        )
        hit = hp.match_profile(probe)
        self.assertIsNotNone(hit)
        assert hit is not None
        self.assertEqual(hit.lineup, "full-48")

    def test_m1_no_match(self) -> None:
        probe = hp.MachineProbe(
            mem_gb=16.0,
            mem_bucket=16,
            chip="Apple M1",
            family="m1",
            variant="base",
        )
        self.assertIsNone(hp.match_profile(probe))

    def test_wrong_ram_no_match(self) -> None:
        probe = hp.MachineProbe(
            mem_gb=40.0,
            mem_bucket=40,
            chip="Apple M5 Max",
            family="m5",
            variant="max",
        )
        self.assertIsNone(hp.match_profile(probe))

    def test_m3_base_regex_rejects_pro_chip(self) -> None:
        # family/variant already differ; also chip_regex Apple M3$ would fail
        probe = hp.MachineProbe(
            mem_gb=16.0,
            mem_bucket=16,
            chip="Apple M3 Pro",
            family="m3",
            variant="base",
        )
        self.assertIsNone(hp.match_profile(probe))


class LineupTests(unittest.TestCase):
    def test_full_48_matches_committed_manifests(self) -> None:
        proposed = hp.stacks_from_lineup("full-48")
        current = hp.current_stacks()
        changes = hp.diff_stacks(current, proposed, list(hp.ALL_STACKS))
        self.assertEqual(changes, [], msg=changes)

    def test_lite_16_omits_deep_chat_reason(self) -> None:
        llm = hp.stacks_from_lineup("lite-16")["llm"]
        self.assertIn("main", llm)
        self.assertNotIn("deep", llm)
        self.assertNotIn("chat", llm)
        self.assertNotIn("reason", llm)

    def test_ram_band_mapping(self) -> None:
        self.assertEqual(hp.ram_band_lineup(48), "full-48")
        self.assertEqual(hp.ram_band_lineup(16), "lite-16")
        self.assertEqual(hp.ram_band_lineup(128), "ultra-128")


if __name__ == "__main__":
    unittest.main()
