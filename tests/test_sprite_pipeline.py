import base64
from concurrent.futures import ThreadPoolExecutor
import io
from pathlib import Path
import tempfile
import threading
import unittest
from unittest.mock import Mock

import sprite_pipeline as sprites


class CatalogTests(unittest.TestCase):
    def test_exact_spanish_gags_skip_speculation(self):
        examples = {
            "rain_cloud": "Invoca una nubecita de lluvia", "banana_peel": "cáscara de plátano",
            "cucumber": "el pepinito", "melted_icecream": "cono derretido",
            "lightning_bolt": "relámpago", "hair_dryer": "secador de pelo",
            "giant_fan": "ventilador gigante", "paint_bucket": "balde de pintura",
            "empanada": "una empanadita", "cardboard_box": "cajita de cartón",
            "robot_vacuum": "aspiradora robot", "giant_anvil": "yunque gigante",
            "soap_bubbles": "burbujas de jabón", "vip_stamp": "¡Sello VIP!",
        }
        generator = Mock(side_effect=AssertionError("cloud called for bundled asset"))
        pipeline = sprites.SpritePipeline(generator)
        self.addCleanup(pipeline.close)
        for asset, prompt in examples.items():
            with self.subTest(asset=asset):
                self.assertEqual(sprites.match_exact_existing_sprite(prompt), asset)
                self.assertIsNone(pipeline.maybe_start_speculative_sprite(prompt))
                bundled = pipeline.get_sprite({"name": prompt})
                self.assertEqual(bundled["existing_sprite"], asset)
                if sprites.IMAGING_AVAILABLE:
                    self.assertTrue(bundled["ok"])
                    for field in ("diff_b64", "norm_b64"):
                        self.assertTrue(base64.b64decode(bundled[field]).startswith(b"\x89PNG"))
        generator.assert_not_called()
        self.assertEqual(sprites.match_exact_existing_sprite("invoca un pingüino"), "fauna_penguin")
        self.assertEqual(sprites.match_exact_existing_sprite("un puente"), "wooden_bridge")
        self.assertIsNone(sprites.match_exact_existing_sprite("una empanada ninja espacial"))

    def test_offline_is_a_normal_result(self):
        with tempfile.TemporaryDirectory() as directory:
            pipeline = sprites.SpritePipeline(None, directory)
            self.addCleanup(pipeline.close)
            self.assertFalse(pipeline.available)
            self.assertIsNone(pipeline.maybe_start_speculative_sprite("ornitorrinco DJ"))
            self.assertFalse(pipeline.get_sprite({"name": "ornitorrinco DJ"})["ok"])


@unittest.skipUnless(sprites.IMAGING_AVAILABLE, "Stage 2 needs Pillow and NumPy")
class LiveSpriteTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.directory = Path(directory.name)
        self.cache = self.directory / "cache"
        self.hero = self.directory / "hero.png"
        picture = sprites.Image.new("RGB", (48, 48), "#FF00FF")
        draw = sprites.ImageDraw.Draw(picture)
        draw.rectangle((14, 8, 33, 39), fill=(108, 36, 156))
        draw.rectangle((18, 12, 24, 16), fill=(200, 160, 65))
        self.image = sprites._png(picture)

    def pipeline(self, generate):
        pipeline = sprites.SpritePipeline(generate, self.cache, self.hero)
        self.addCleanup(pipeline.close)
        return pipeline

    @staticmethod
    def decode(result, field):
        return sprites.Image.open(io.BytesIO(base64.b64decode(result[field]))).convert("RGBA")

    def test_speculation_overlaps_judging_and_alias_reuses_single_call(self):
        started, release = threading.Event(), threading.Event()
        responses = []
        sprites.Image.new("RGBA", (18, 24), "red").save(self.hero)

        def generate(instruction, ref):
            self.assertIn("facing right", instruction)
            self.assertIn("ornitorrinco dj", instruction)
            with sprites.Image.open(io.BytesIO(ref)) as style:
                self.assertEqual(style.size, (128, 128))
                self.assertEqual(style.getpixel((0, 0)), (255, 0, 255))
            started.set()
            self.assertTrue(release.wait(3))
            return self.image

        generator = Mock(side_effect=generate)
        pipeline = self.pipeline(generator)
        stage_two = pipeline.maybe_start_speculative_sprite("ornitorrinco dj")
        try:
            self.assertTrue(started.wait(2))
            pipeline.bind_speculative_alias("ornitorrinco dj", "¡Maestro del vinilo!")
            payload = {"name": "¡Maestro del vinilo!", "sprite_prompt": "platypus DJ facing right"}
            with ThreadPoolExecutor(max_workers=4) as clients:
                futures = [clients.submit(pipeline.get_sprite, payload) for _ in range(4)]
                release.set()
                responses = [future.result(timeout=5) for future in futures]
        finally:
            release.set()
        self.assertEqual(generator.call_count, 1)
        self.assertTrue(all(response["ok"] for response in responses))
        self.assertEqual(len({response["diff_b64"] for response in responses}), 1)
        stage_two.result(timeout=5)
        self.assertTrue(pipeline.get_sprite(payload)["cached"])
        self.assertEqual(len(list(self.cache.glob("*.png"))), 2)
        disk_only = self.pipeline(None)
        self.assertTrue(disk_only.get_sprite({**payload, "original_prompt": "ornitorrinco dj"})["cached"])

    def test_clean_bottom_anchor_matching_normals_and_variant(self):
        generator = Mock(return_value=self.image)
        pipeline = self.pipeline(generator)
        pipeline.maybe_start_speculative_sprite("berenjena DJ")
        result = pipeline.get_sprite({"name": "berenjena DJ", "keep_purple": True, "target_dim": 76})
        self.assertTrue(result["ok"])
        diffuse = self.decode(result, "diff_b64")
        normal = self.decode(result, "norm_b64")
        self.assertEqual(diffuse.size, (76, 76))
        self.assertEqual(normal.size, diffuse.size)
        self.assertEqual(diffuse.getchannel("A").tobytes(), normal.getchannel("A").tobytes())
        left, top, right, bottom = diffuse.getchannel("A").getbbox()
        self.assertLessEqual(abs(left - (76 - right)), 1)
        self.assertEqual(bottom, 76)
        self.assertGreater(top, 0)
        self.assertIn((108, 36, 156, 255), diffuse.getdata())
        self.assertNotIn((255, 0, 255, 255), diffuse.getdata())
        self.assertEqual(normal.getpixel((0, 0)), (128, 128, 255, 0))
        self.assertGreater(len(set(normal.getdata())), 4)
        generator.assert_called_once()
        self.assertIsNone(generator.call_args.args[1])

    def test_connected_fringe_does_not_erase_enclosed_highlight(self):
        pixels = sprites.np.empty((7, 7, 4), dtype="uint8")
        pixels[:] = (255, 0, 255, 255)
        pixels[1:6, 1:6] = (117, 100, 40, 255)
        pixels[3, 3] = pixels[1, 1] = (200, 56, 196, 255)
        protected = pixels.copy()
        sprites._clean_corner_bg_floodfill(pixels, False)
        self.assertEqual(pixels[1, 1, 3], 0)
        self.assertEqual(pixels[3, 3, 3], 255)
        sprites._clean_corner_bg_floodfill(protected, True)
        self.assertEqual(protected[1, 1, 3], 255)
        self.assertEqual(protected[0, 0, 3], 0)

    def test_provider_failure_can_retry(self):
        generator = Mock(side_effect=[RuntimeError("test provider"), self.image])
        pipeline = self.pipeline(generator)
        self.assertFalse(pipeline.get_sprite({"name": "chirimoya voladora"})["ok"])
        self.assertTrue(pipeline.get_sprite({"name": "chirimoya voladora"})["ok"])
        self.assertEqual(generator.call_count, 2)

    def test_memory_evicts_oldest_and_disk_works_without_cloud(self):
        generator = Mock(return_value=self.image)
        pipeline = self.pipeline(generator)
        for i in range(14):
            self.assertTrue(pipeline.get_sprite({"name": f"guitarra sideral {i}"})["ok"])
        self.assertEqual(pipeline.cache_size, 12)
        self.assertEqual(len(list(self.cache.glob("*_n.png"))), 14)
        self.assertTrue(pipeline.get_sprite({"name": "guitarra sideral 0"}, allow_generate=False)["cached"])
        self.assertFalse(pipeline.get_sprite({"name": "pomelo nuevo"}, allow_generate=False)["ok"])
        self.assertEqual(generator.call_count, 14)

    def test_incomplete_disk_pair_falls_back(self):
        generator = Mock(return_value=self.image)
        pipeline = self.pipeline(generator)
        payload = {"name": "flan con patines"}
        self.assertTrue(pipeline.get_sprite(payload)["ok"])
        next(self.cache.glob("*_n.png")).write_bytes(b"broken")
        new_pipeline = self.pipeline(generator)
        self.assertTrue(new_pipeline.get_sprite(payload)["ok"])
        self.assertEqual(generator.call_count, 2)

    def test_decision_api_sprite_quality_gate_retries_and_rejects_bad_assets(self):
        generator = Mock(side_effect=[self.image, self.image])
        validator = Mock(side_effect=[(False, "imagen borrosa"), (True, "")])
        pipeline = sprites.SpritePipeline(generator, self.cache, self.hero, validate_sprite=validator)
        self.addCleanup(pipeline.close)
        res = pipeline.get_sprite({"name": "tostadora cosmica"})
        self.assertTrue(res["ok"])
        self.assertEqual(generator.call_count, 2)
        self.assertEqual(validator.call_count, 2)

        bad_gen = Mock(side_effect=[self.image, self.image])
        always_reject = Mock(return_value=(False, "rechazado"))
        bad_pipe = sprites.SpritePipeline(bad_gen, self.cache, self.hero, validate_sprite=always_reject)
        self.addCleanup(bad_pipe.close)
        bad_res = bad_pipe.get_sprite({"name": "artefacto roto"})
        self.assertFalse(bad_res["ok"])
        self.assertEqual(bad_gen.call_count, 2)
        self.assertFalse(bad_pipe.get_sprite({"name": "artefacto roto"}, allow_generate=False)["ok"])


if __name__ == "__main__":
    unittest.main()
