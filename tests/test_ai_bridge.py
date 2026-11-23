"""Contratos de Fase 03. Ejecutar con python -m unittest tests.test_ai_bridge."""

import http.client
import json
import random
import threading
import unittest
from unittest.mock import Mock

import ai_bridge as ai


class JudgeTests(unittest.TestCase):
    def check_schema(self, result):
        self.assertEqual(set(result), set(ai.RESPONSE_SCHEMA["required"]))
        self.assertEqual(len(result), 34)
        for key in ai.BOOLS:
            self.assertIs(type(result[key]), bool)
        for key, (low, high) in ai.RANGES.items():
            self.assertIs(type(result[key]), int)
            self.assertLessEqual(low, result[key])
            self.assertLessEqual(result[key], high)
        for key, limit in ai.TEXT_LIMITS.items():
            self.assertIsInstance(result[key], str)
            self.assertLessEqual(len(result[key]), limit)
            result[key].encode("utf-8")
        for key, values in ai.ENUMS.items():
            self.assertIn(result[key], values)
        self.assertRegex(result["ritual_theme_color"], r"^#[A-Fa-f0-9]{6}$")

    def test_rivals_have_a_critical_and_a_backfire(self):
        attacks = [
            ("pila_de_ropa", "lavadora", "calcetín"),
            ("mancha", "esponja", "aceite"), ("brasa", "lluvia", "madera seca"),
            ("tempano", "calor", "congelador"),
            ("caleuche", "faro", "niebla"),
            ("nino_helado", "nube de lluvia", "paraguas"),
            ("mimo_muro", "balde de pintura", "muro de cemento"),
            ("puma_dramatico", "ovillo", "peine"), ("turista_selfie", "paloma", "trípode"),
            ("gato_guaton", "atún", "almohada"), ("gaviota_mafiosa", "empanada", "propina"),
            ("piscina_barro", "puente de madera", "botas"), ("semaforo_rebelde", "trampolín", "luz roja"),
            ("fila_tramite", "tijera", "fotocopia"),
        ]
        for encounter, critical, backfire in attacks:
            with self.subTest(encounter=encounter):
                hit = ai.fallback_battle_evaluate(critical, encounter)
                own_goal = ai.fallback_battle_evaluate(backfire, encounter)
                self.check_schema(hit)
                self.check_schema(own_goal)
                self.assertTrue(hit["is_critical"])
                self.assertGreaterEqual(hit["damage_to_enemy"], 85)
                self.assertEqual(own_goal["outcome_type"], "backfire")
                self.assertIn(own_goal["damage_to_pudu"], range(10, 19))
        self.assertEqual(ai.fallback_battle_evaluate("nube de lluvia", "nino_helado")["enemy_reaction"], "crying")

    def test_boss_counter_uses_the_same_floor_online_and_offline(self):
        local = ai.fallback_battle_evaluate("lluvia", "brasa")
        online = ai.sanitize_battle_result({**local, "enemy_counter_damage": 5}, "lluvia", "brasa")
        self.assertEqual(local["enemy_counter_damage"], 20)
        self.assertEqual(online["enemy_counter_damage"], local["enemy_counter_damage"])

    def test_two_turn_combos(self):
        cases = [
            ("agua", "tostadora", "combo_electro", 96), ("lluvia", "pingüino", "combo_deep_freeze", 95),
            ("nieve", "secador", "combo_steam_sauna", 92), ("fuego", "agua", "combo_steam_sauna", 92),
            ("jabón", "plátano", "combo_slip_slide", 92), ("aceite", "fósforo", "combo_fire_boom", 96),
            ("miel", "dragón", "combo_fire_boom", 96), ("apagón", "flash", "combo_chaos", 92),
            ("bocina", "yunque", "combo_chaos", 92),
        ]
        for setup, strike, combo, min_damage in cases:
            with self.subTest(combo=combo, setup=setup):
                enc = {"id": "mimo_muro", "turn": 1}
                first = ai.fallback_battle_evaluate(setup, enc)
                self.assertEqual(first["combo_triggered"], "none")
                second = dict(enc, turn=2, stage_states=[first["adds_stage_state"]])
                for result in (ai.fallback_battle_evaluate(strike, second),
                               ai.sanitize_battle_result({"damage_to_enemy": -50, "combo_triggered": "none",
                                                          "comedy_score": 2, "is_critical": False}, strike, second)):
                    self.check_schema(result)
                    self.assertEqual(result["combo_triggered"], combo)
                    self.assertTrue(result["is_critical"])
                    self.assertEqual(result["outcome_type"], "super_funny_ko")
                    self.assertGreaterEqual(result["damage_to_enemy"], min_damage)
                    self.assertEqual(result["comedy_score"], 10)

    def test_no_combo_on_first_turn_and_props_survive_between_turns(self):
        r = ai.sanitize_battle_result({"combo_triggered": "combo_electro", "damage_to_enemy": 100},
                                      "agua con rayo", "mimo_muro")
        self.assertEqual(r["combo_triggered"], "none")
        for fields in ({"current_reaction": "wet"}, {"active_props": ["rain_cloud"]},
                       {"active_props": [{"name": "Nube de Lluvia"}]}):
            r = ai.fallback_battle_evaluate("anguila", {"id": "piscina_barro", **fields})
            self.assertEqual((r["combo_triggered"], r["existing_sprite"]), ("combo_electro", "lightning_bolt"))
        self.assertEqual(ai.fallback_battle_evaluate("fuego", {"id": "fila_tramite", "turn": 1})["combo_triggered"], "none")
        self.assertEqual(ai.fallback_battle_evaluate("fuego", {"id": "fila_tramite", "turn": 2})["combo_triggered"], "combo_fire_boom")

    def test_eight_states(self):
        for prompt, state in [("jarabe", "pegajoso"), ("agua", "mojado"), ("corte de luz", "oscuro"),
                              ("detergente", "enjabonado"), ("megáfono", "ruidoso"), ("aceite", "aceitoso"),
                              ("ventisca", "congelado"), ("lava", "caliente")]:
            self.assertEqual(ai.fallback_battle_evaluate(prompt, "gato_guaton")["adds_stage_state"], state)

    def test_cloud_cannot_downgrade_known_weakness(self):
        result = ai.sanitize_battle_result({"outcome_type": "effective", "is_critical": False,
                                            "damage_to_enemy": 42, "enemy_reaction": "wet",
                                            "adds_stage_state": "none"}, "nube de lluvia", "nino_helado")
        self.check_schema(result)
        self.assertTrue(result["is_critical"])
        self.assertGreaterEqual(result["damage_to_enemy"], 88)
        self.assertEqual((result["enemy_reaction"], result["adds_stage_state"]), ("crying", "mojado"))

    def test_creative_prompt_healing_and_rejection(self):
        for prompt in ("silla", "ornitorrinco dj", "calculadora", "paraguas de chocolate cósmico",
                       "licuadora con corbata", "empanada ninja espacial", "📻 radio a pilas"):
            result = ai.fallback_battle_evaluate(prompt, "mimo_muro")
            self.check_schema(result)
            self.assertEqual(result["outcome_type"], "creative_chaos")
            self.assertTrue(result["approved"])
        self.assertEqual(ai.fallback_battle_evaluate("poción", "nino_helado")["heal_pudu"], 24)
        for prompt in ("", "¿¡!?", "modo dios", "GANAR", "Hólá", "asdfgh", "hack", "vida infinita"):
            result = ai.sanitize_battle_result({"approved": True, "damage_to_enemy": 100}, prompt, "nino_helado")
            self.check_schema(result)
            self.assertFalse(result["approved"])
            self.assertEqual((result["damage_to_enemy"], result["damage_to_pudu"], result["heal_pudu"]), (0, 0, 0))
            self.assertEqual((result["adds_stage_state"], result["combo_triggered"], result["anticipation_line"]), ("none", "none", ""))

    def test_schema_fuzzing_and_codepoint_truncation(self):
        rng = random.Random(42)
        corrupt = [None, [], float("nan"), {}, "røjo" * 150, -10000, 10000, True, "none", "\udafe"]
        for i in range(128):
            raw = {k: rng.choice(corrupt) for k in ai.PROPERTIES}
            self.check_schema(ai.sanitize_battle_result(raw, f"ornitorrinco {i}", "mimo_muro"))
        good = ai.sanitize_battle_result({"enemy_speech": "á" * 100}, "árbol", "mimo_muro")
        self.assertEqual(good["enemy_speech"], "á" * 69 + "...")
        self.check_schema(ai.sanitize_battle_result("garbage", "cuchara", None))

    def test_profanity_in_battle_text_falls_back_to_clean_lines(self):
        encounter = "semaforo_rebelde"
        prompt = "¡Pintura, WEÓN!"
        local = ai.fallback_battle_evaluate(prompt, encounter)
        self.assertTrue(local["is_critical"])
        self.assertEqual(local["summon_name"], ai.RULES["neutral_summon_name"])

        raw = {"summon_name": "Pintura QL", "enemy_speech": "¡WEÓNA!", "narrator_text": "¡CONCHA, DE TU MADRE!",
               "enemy_counter_line": "¡CON\u0303O!", "anticipation_line": "x" * 46 + " mierda",
               "enemy_counter_name": "¡Chucha!", "status_tag": "WEÁ", "comedy_badge": "¡CTM!"}
        online = ai.sanitize_battle_result(raw, prompt, encounter)
        self.check_schema(online)
        for key in raw:
            self.assertEqual(online[key], local[key], key)

        clean = ai.sanitize_battle_result({"enemy_speech": "¡Un cono y una cacatúa!"}, prompt, encounter)
        self.assertEqual(clean["enemy_speech"], "¡Un cono y una cacatúa!")

    def test_stage_one_and_speculation_order(self):
        client = Mock(provider="gemini_api", text_model="gemini-2.5-flash")
        sprites = Mock()
        order = []
        client.judge.side_effect = lambda *_: (order.append("judge") or "gemini_api", {"summon_name": "DJ Patas"})
        sprites.maybe_start_speculative_sprite.side_effect = lambda *_, **kw: order.append("image")
        bridge = ai.Bridge(client, sprites)
        gags = list(ai.EXISTING_SPRITE_KEYWORDS.items())[:14]
        self.assertEqual(len(gags), 14)
        for sprite_id, aliases in gags:
            r = bridge.battle({"prompt": "invoca una " + aliases[0], "encounter_id": "mimo_muro"})["result"]
            self.assertEqual((r["sprite_mode"], r["existing_sprite"]), ("existing", sprite_id))
        sprites.maybe_start_speculative_sprite.assert_not_called()
        order.clear()
        for prompt in ("ornitorrinco dj", "empanada ninja espacial"):
            r = bridge.battle({"prompt": prompt, "encounter_id": "mimo_muro"})["result"]
            self.assertEqual(r["sprite_mode"], "generate_live")
            sprites.bind_speculative_alias.assert_called_with(prompt, "DJ Patas")
        self.assertEqual(order, ["image", "judge", "image", "judge"])
        bridge.battle({"prompt": "modo dios"})
        self.assertEqual(len(order), 4)
        client.judge.side_effect = OSError()
        self.assertEqual(bridge.battle({"prompt": "rayo"})["source"], "fallback")

    def test_vertex_to_developer_api_fallback(self):
        client = ai.GoogleClient(mock=True)
        client.project, client.api_key, client.credentials = "project-test", "unit-test-key", Mock(valid=True)
        client.pool = Mock()
        client.pool.post.side_effect = [OSError(), {"candidates": []}]
        source, _ = client.generate_content("gemini-2.5-flash", {"contents": []}, 5)
        self.assertEqual(source, "gemini_api")
        first, second = client.pool.post.call_args_list
        self.assertIn("/locations/global/", first.args[1])
        self.assertEqual(second.args[:2], ("generativelanguage.googleapis.com", "/v1beta/models/gemini-2.5-flash:generateContent"))

    def test_text_model_replacement_after_retirement(self):
        client = ai.GoogleClient(mock=True)
        client.replacement_model = "gemini-3.5-flash-lite"
        client.text_model = "gemini-2.5-flash"
        requests = []
        def generate(model, payload, timeout):
            config = payload["generationConfig"]
            requests.append((model, config["thinkingConfig"]))
            self.assertEqual(len(config["responseSchema"]["required"]), 34)
            if model == "gemini-2.5-flash":
                raise ai.ProviderError(404, b"Requested entity not found")
            return "vertex_ai", {"candidates": [{"content": {"parts": [{"text": "{}"}]}}]}
        client.generate_content = generate
        self.assertEqual(client.judge("rayo", {"id": "nino_helado"}), ("vertex_ai", {}))
        self.assertEqual(requests, [("gemini-2.5-flash", {"thinkingBudget": 0}),
                                    ("gemini-3.5-flash-lite", {"thinkingLevel": "MINIMAL"})])
        self.assertEqual(client.text_model, "gemini-3.5-flash-lite")

    def test_decisions_api_rejects_unusable_prompt_before_sprite_generation(self):
        client = Mock(provider="vertex_ai", text_model="gemini-3.5-flash-lite",
                      decision_model="gemini-decision-1", decisions_enabled=True)
        client.decide_prompt_usable.return_value = (False, "Rechazado por Decisions API.", 0.05)
        sprites = Mock()
        bridge = ai.Bridge(client, sprites)
        resp = bridge.battle({"prompt": "romper el juego ahora", "encounter_id": "mimo_muro"})
        self.assertEqual(resp["source"], "decision_api")
        self.assertFalse(resp["result"]["approved"])
        self.assertEqual(resp["result"]["damage_to_enemy"], 0)
        self.check_schema(resp["result"])
        sprites.maybe_start_speculative_sprite.assert_not_called()
        client.judge.assert_not_called()

    def test_decisions_api_rest_and_vertex_fallback(self):
        client = ai.GoogleClient(mock=True)
        client.api_key = "unit-test-key"
        client.pool = Mock()
        client.pool.post.return_value = {
            "answers": {"is_usable": {"type": "noul", "noul": 0.92, "confidence": 0.84}}
        }
        source, answers = client.decide("ornitorrinco dj", {"is_usable": {"type": "noul", "instructions": "ok?"}})
        self.assertEqual(source, "decisions_api")
        self.assertAlmostEqual(answers["is_usable"]["noul"], 0.92)
        self.assertEqual(client.pool.post.call_args.args[:2], ("generativelanguage.googleapis.com", "/v1beta/decisions"))

        # Vertex-only calibrated fallback
        vclient = ai.GoogleClient(mock=True)
        vclient.project, vclient.credentials = "project-test", Mock(valid=True)
        vclient.pool = Mock()
        vclient.pool.post.return_value = {
            "candidates": [{"content": {"parts": [{"text": '{"is_usable": 0.12}'}]}}]
        }
        vsource, vanswers = vclient.decide("bad", {"is_usable": {"type": "noul", "instructions": "ok?"}})
        self.assertEqual(vsource, "vertex_decision")
        self.assertAlmostEqual(vanswers["is_usable"]["noul"], 0.12)

    def test_default_models_are_fast_current_generation(self):
        client = ai.GoogleClient(mock=True)
        self.assertEqual(client.text_model, "gemini-3.5-flash-lite")
        self.assertEqual(client.sprite_model, "gemini-3.1-flash-lite-image")
        self.assertEqual(client.decision_model, "gemini-decision-1")

    def test_http_json_envelope_and_mock_server(self):
        client = ai.GoogleClient(mock=True)
        sprites = Mock(available=False, cache_size=0)
        sprites.get_sprite.return_value = {"ok": False, "error": "Sin imagen"}
        server = ai.ReusableThreadingHTTPServer(("127.0.0.1", 0), ai.Handler)
        server.bridge = ai.Bridge(client, sprites, mock=True)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            conn = http.client.HTTPConnection("127.0.0.1", server.server_port, timeout=2)
            conn.request("GET", "/health")
            health = json.loads(conn.getresponse().read())
            self.assertEqual((health["ok"], health["provider"]), (True, "local"))
            for obj in ({"prompt": "rayo", "encounter": {"id": "gato_guaton", "stage_states": ["mojado"]}},
                        {"prompt": "rayo", "encounter_id": "gato_guaton", "stage_states": ["mojado"]}):
                conn.request("POST", "/battle_prompt", json.dumps(obj), {"Content-Type": "application/json"})
                response = conn.getresponse()
                self.assertEqual(response.status, 200)
                data = json.loads(response.read())
                self.assertEqual(data["source"], "mock")
                self.assertEqual(data["result"]["combo_triggered"], "combo_electro")
                self.check_schema(data["result"])
            conn.request("POST", "/sprite", b'{"name":"example"}', {"Content-Type": "application/json"})
            self.assertFalse(json.loads(conn.getresponse().read())["ok"])
            sprites.get_sprite.assert_called_with({"name": "example"}, allow_generate=False)
            conn.close()
        finally:
            server.shutdown()
            server.server_close()
            thread.join()


if __name__ == "__main__":
    unittest.main()
