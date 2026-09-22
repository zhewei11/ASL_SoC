#!/usr/bin/env python3
import copy
import json
import unittest

import generate_config


class ConfigValidationTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.valid = json.loads(generate_config.CONFIG.read_text())

    def changed(self, *path_and_value):
        cfg = copy.deepcopy(self.valid)
        *path, value = path_and_value
        node = cfg
        for key in path[:-1]:
            node = node[key]
        node[path[-1]] = value
        return cfg

    def rejected(self, cfg, message):
        with self.assertRaisesRegex(ValueError, message):
            generate_config.validate_config(cfg)

    def test_valid_baseline(self):
        values = generate_config.validate_config(copy.deepcopy(self.valid))
        self.assertEqual(values["RT_FRAME_CYCLES"], 100_000)
        self.assertEqual(values["DMA_MAX_BURST_BEATS"], 16)
        self.assertEqual(len(values), 43)

    def test_dma_burst_power_of_two(self):
        self.rejected(self.changed("dma", "max_burst_beats", 17),
                      "power of two")

    def test_non_integer_frame_clock(self):
        self.rejected(self.changed("clock", "rt_frame_hz", 3000),
                      "integer multiple")

    def test_local_memory_overlap(self):
        self.rejected(self.changed("memory", "itcm_base", "0x00001000"),
                      "overlap")

    def test_cached_dma_overlap(self):
        self.rejected(self.changed("memory", "cached_dram_base", "0x20800000"),
                      "overlap")

    def test_duplicate_mmio_page(self):
        self.rejected(self.changed("mmio", "cnn_base", "0x10031000"),
                      "unique")

    def test_frame_buffer_end_outside_dma(self):
        self.rejected(self.changed("ethernet", "frame_buffer_base", "0x20fff000"),
                      "exceeds")

    def test_stream_width_contract(self):
        self.rejected(self.changed("ethernet", "stream_width", 64),
                      "32-bit stream")

    def test_motor_count_contract(self):
        self.rejected(self.changed("hand", "motor_count", 19),
                      "exactly 20")

    def test_protocol_buffer_power_of_two(self):
        self.rejected(self.changed("protocol2", "command_bytes", 1000),
                      "power of two")

    def test_zero_cnn_dimension(self):
        self.rejected(self.changed("cnn", "input_width", 0), "positive")


if __name__ == "__main__":
    unittest.main()
