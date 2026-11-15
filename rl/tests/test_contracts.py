"""Cross-component regressions: real content, official policy, safe persistence."""

import json
import os
from pathlib import Path

import numpy as np
import pytest
import torch
import yaml
from checkpoint_fixtures import certified
from torch.distributions import Categorical

from samstone_rl.bridge.godot_process import GodotProcess
from samstone_rl.decks import DeckCatalog, DeckGenerator
from samstone_rl.envs import ActionCodec, ObservationEncoder
from samstone_rl.evaluation.tournament import run_tournament
from samstone_rl.fast_engine import FastEngineBridge, StoneCatalog
from samstone_rl.models.export import export_policy
from samstone_rl.models.policy import build_policy, policy_spec, restore_policy
from samstone_rl.opponents.checkpoint import CheckpointOpponent
from samstone_rl.tactics import TacticalActionEncoder
from samstone_rl.training.league import SelfPlayLeague
from samstone_rl.training.ppo_cleanrl import PPOTrainer
from samstone_rl.utils.certification import require_certified
from samstone_rl.utils.checkpoints import (
    file_checksum,
    load_checkpoint,
    save_checkpoint,
)
from samstone_rl.utils.optim import DirectMLAdam
from samstone_rl.utils.provenance import game_rules_checksum, provenance
from samstone_rl.utils.statistics import sign_test

CONFIG = Path(__file__).resolve().parents[1] / "configs/ppo_phase4_vectorized.yaml"
SCENARIOS = yaml.safe_load(CONFIG.read_text(encoding="utf-8"))["environment"]["scenarios"]
GODOT = pytest.mark.skipif(not os.environ.get("GODOT_BIN"), reason="GODOT_BIN non defini")


def tiny_config(tmp_path):
    config = yaml.safe_load(CONFIG.read_text(encoding="utf-8"))
    config["device"] = "cpu"
    config["output_dir"] = str(tmp_path / "run")
    config["environment"]["evaluation_backend"] = "python"
    config["model"].update(hidden_dim=16, action_hidden_dim=8)
    config["ppo"].update(
        num_envs=2,
        rollout_steps=8,
        total_timesteps=16,
        minibatches=2,
        min_update_epochs=1,
        max_update_epochs=1,
    )
    config["evaluation"]["every_updates"] = 100
    config["curriculum"]["bootstrap_evaluation"] = {"enabled": False}
    config["monitoring"].update(
        tensorboard=False, checkpoint_every_updates=0, snapshot_every_updates=0
    )
    path = tmp_path / "config.yaml"
    path.write_text(yaml.safe_dump(config), encoding="utf-8")
    return path


def test_catalog_is_deeply_immutable():
    catalog = StoneCatalog()
    with pytest.raises(TypeError):
        catalog.definition("devoracle_n3")["level"] = 99
    with pytest.raises(TypeError):
        catalog.definition("devoracle_n3")["blades"]["top"] = 99


@pytest.mark.parametrize("architecture", ["actor_critic", "tactical_actor_critic"])
def test_frozen_opponent_accepts_directml_device_name(tmp_path, architecture):
    pytest.importorskip("torch_directml")
    config = {"model": {"architecture": architecture, "hidden_dim": 16, "action_hidden_dim": 8}}
    path = tmp_path / "opponent.pt"
    save_checkpoint(path, {"model": build_policy(config).state_dict(), "config": config})
    opponent = CheckpointOpponent(path, device="directml")
    assert opponent.device.type == "privateuseone"
    scenario = SCENARIOS[0]
    bridge = FastEngineBridge()
    try:
        snapshot = bridge.reset(
            {
                "seed": 9851,
                "first_player": 2,
                "blocked": [],
                "human_god": scenario["god"],
                "ai_god": scenario["god"],
                "human_deck": scenario["deck"],
                "ai_deck": scenario["deck"],
            },
            2,
        )
        choice = opponent.choose(bridge, snapshot["legal_actions"], np.random.default_rng(5), 2)
        assert choice in snapshot["legal_actions"]
    finally:
        bridge.close()


def test_large_sign_test_remains_finite_and_exact_for_small_samples():
    assert sign_test(600, 600) == pytest.approx(1.0)
    assert sign_test(10000, 10000) == pytest.approx(1.0)
    assert sign_test(5, 0) == pytest.approx(0.0625)
    assert sign_test(0, 0) == 1.0
    assert sign_test(10000, 0) == 0.0


def test_league_batches_durable_events_and_recovers_after_snapshot_interruption(tmp_path):
    league = SelfPlayLeague(tmp_path, {"godot": 1.0})
    league.record_result("a", "b", 1.0, 1, persist=False)
    league.record_result("a", "c", 0.5, 2, persist=False)
    assert not league.results_path.exists()
    league.flush_results()
    assert len(league.results_path.read_text(encoding="utf-8").splitlines()) == 2
    expected = dict(league.ratings)
    # Simulate a lost snapshot after the journal was committed.
    league.ratings_path.unlink()
    restored = SelfPlayLeague(tmp_path, {"godot": 1.0})
    assert restored.ratings == expected
    with restored.results_path.open("ab") as stream:
        stream.write(b'{"interrupted":')
    again = SelfPlayLeague(tmp_path, {"godot": 1.0})
    assert again.ratings == expected
    assert again.results_path.read_bytes().endswith(b"\n")


def test_directml_adam_closure_can_build_gradients():
    parameter = torch.nn.Parameter(torch.tensor([2.0]))
    optimizer = DirectMLAdam([parameter], lr=0.1)

    def closure():
        optimizer.zero_grad()
        loss = parameter.square().sum()
        loss.backward()
        return loss

    assert float(optimizer.step(closure)) == 4.0
    assert float(parameter.detach()[0]) < 2.0


def test_certificate_rejects_changed_weights_or_rules(tmp_path):
    from checkpoint_fixtures import certified

    config = {"model": {"architecture": "tactical_actor_critic", "hidden_dim": 16}}
    payload = certified({"config": config, "model": build_policy(config).state_dict()}, "phase4")
    require_certified(payload, "phase4", provenance())
    with pytest.raises(ValueError, match="certification"):
        require_certified(payload, "phase4", {**provenance(), "game_rules": "different"})
    payload["model"]["critic.bias"].add_(1.0)
    with pytest.raises(ValueError, match="certification"):
        require_certified(payload, "phase4", provenance())


def test_factorized_policy_preserves_logits_and_gradients():
    torch.manual_seed(29)
    config = {
        "model": {"architecture": "tactical_actor_critic", "hidden_dim": 16, "action_hidden_dim": 8}
    }
    model = build_policy(config)
    torch.nn.init.normal_(model.action_scorer[2].weight, std=0.1)
    observation = torch.randn(3, 929)
    features = torch.randn(3, 128, 79)
    masks = torch.rand(3, 128) > 0.4
    weights = torch.randn(3, 128)
    actual, _ = model.distribution_and_value(observation, masks, features)
    (actual.logits * weights).sum().backward()
    gradients = {n: p.grad.clone() for n, p in model.named_parameters() if p.grad is not None}
    model.zero_grad(set_to_none=True)
    state = model.backbone(observation)
    expanded = state.unsqueeze(1).expand(-1, 128, -1)
    logits = model.legacy_actor(state) + model.action_scorer(
        torch.cat((expanded, model.action_encoder(features)), dim=-1)
    ).squeeze(-1)
    expected = Categorical(logits=logits.masked_fill(~masks, -1e9))
    assert torch.allclose(actual.logits, expected.logits, atol=1e-6)
    (expected.logits * weights).sum().backward()
    for name, parameter in model.named_parameters():
        if name in gradients:
            assert torch.allclose(parameter.grad, gradients[name], atol=1e-5, rtol=1e-4), name


def test_checkpoint_recovers_interrupted_pair_and_rejects_other_corruption(tmp_path):
    path = tmp_path / "latest.pt"
    config = {"model": {"architecture": "tactical_actor_critic", "hidden_dim": 16}}
    payload = {
        "model": build_policy(config).state_dict(),
        "config": config,
        "policy_spec": policy_spec(config),
    }
    save_checkpoint(path, payload)
    expected = file_checksum(path)
    path.with_suffix(".pt.pending.json").write_text(
        json.dumps({"target": path.name, "sha256": expected}), encoding="utf-8"
    )
    path.with_suffix(".pt.sha256").write_text("stale", encoding="ascii")
    assert restore_policy(load_checkpoint(path)).action_dim == 128
    assert not path.with_suffix(".pt.pending.json").exists()
    with path.open("ab") as stream:
        stream.write(b"corruption")
    with pytest.raises(ValueError, match="checksum"):
        load_checkpoint(path)


def test_run_requires_explicit_resume_and_releases_lock(tmp_path):
    path = tiny_config(tmp_path)
    with PPOTrainer(path) as trainer:
        with pytest.raises(RuntimeError, match="autre processus"):
            PPOTrainer(path, mode="resume")
        trainer.train()
    with pytest.raises(ValueError, match="resume"):
        PPOTrainer(path)
    with PPOTrainer(path, mode="resume") as trainer:
        trainer.load_checkpoint(tmp_path / "run/latest.pt")
        assert trainer._resume_global_step == 16


def test_resume_allows_budget_change_and_explicit_optimizer_reset(tmp_path):
    path = tiny_config(tmp_path)
    with PPOTrainer(path) as trainer:
        trainer.train()
    checkpoint = tmp_path / "run/latest.pt"
    config = yaml.safe_load(path.read_text(encoding="utf-8"))
    config["ppo"]["total_timesteps"] = 32
    config["ppo"]["learning_rate"] *= 2
    path.write_text(yaml.safe_dump(config), encoding="utf-8")
    with PPOTrainer(path, mode="resume") as trainer:
        with pytest.raises(ValueError, match="reset-optimizer"):
            trainer.load_checkpoint(checkpoint)
    with PPOTrainer(path, mode="resume") as trainer:
        trainer.load_checkpoint(checkpoint, load_optimizer=False)
        trainer.train()
    assert load_checkpoint(checkpoint)["global_step"] == 32
    manifest = json.loads((tmp_path / "run/run_manifest.json").read_text(encoding="utf-8"))
    assert manifest["config"]["ppo"]["total_timesteps"] == 32
    assert manifest["config_history"][0]["config"]["ppo"]["total_timesteps"] == 16
    config["ppo"]["gamma"] = 0.5
    path.write_text(yaml.safe_dump(config), encoding="utf-8")
    with pytest.raises(ValueError, match="config_sha256 incompatible"):
        PPOTrainer(path, mode="resume")


def test_tournament_resumes_only_missing_cases_and_invalidates_other_policy(tmp_path):
    calls = []
    cases = [{"seed": i} for i in range(5)]

    def play(_env, case):
        calls.append(case["seed"])
        if case["seed"] == 2:
            raise RuntimeError("simulated crash")
        return {"winner": 1}

    with pytest.raises(RuntimeError, match="crash"):
        run_tournament(cases, [object()], play, tmp_path, {"policy": "a"})
    assert calls == [0, 1, 2]
    calls.clear()

    def healthy(_env, case):
        calls.append(case["seed"])
        return {"winner": 1}

    assert len(run_tournament(cases, [object()], healthy, tmp_path, {"policy": "a"})) == 5
    assert calls == [2, 3, 4]
    calls.clear()
    run_tournament(cases, [object()], healthy, tmp_path, {"policy": "b"})
    assert calls == [0, 1, 2, 3, 4]


@GODOT
@pytest.mark.parametrize("architecture", ["actor_critic", "tactical_actor_critic"])
def test_exported_godot_policy_matches_pytorch_inputs_logits_and_value(tmp_path, architecture):
    torch.manual_seed(413)
    config = {"model": {"architecture": architecture, "hidden_dim": 16, "action_hidden_dim": 8}}
    model = build_policy(config)
    if architecture == "tactical_actor_critic":
        torch.nn.init.normal_(model.action_scorer[2].weight, std=0.1)
    checkpoint, exported = tmp_path / "source.pt", tmp_path / "policy.sspolicy"
    scenario = SCENARIOS[4]
    save_checkpoint(
        checkpoint,
        certified(
            {
                "model": model.state_dict(),
                "config": config,
                "specialization": {"god_id": scenario["god"], "deck": scenario["deck"]},
            },
            "boss",
        ),
    )
    export_policy(checkpoint, exported)
    match = {
        "seed": 1591,
        "portable_rng": True,
        "first_player": 1,
        "blocked": [[1, 1]],
        "human_god": scenario["god"],
        "ai_god": scenario["god"],
        "human_deck": scenario["deck"],
        "ai_deck": scenario["deck"],
    }
    with GodotProcess() as bridge:
        snapshot = bridge.reset(match, 1)
        for turn in range(4):
            observer = snapshot["observation"]["current_player"]
            snapshot = bridge.get_state(observer)
            observation = ObservationEncoder().encode(snapshot["observation"])
            masks = ActionCodec().legal_mask(
                snapshot["legal_actions"], snapshot["observation"]["hand"]
            )
            features = TacticalActionEncoder().encode(
                observation, masks, bridge.tactical_action_scores(observer)
            )
            native = bridge.send_command("evaluate_policy", observer=observer, path=str(exported))
            assert "error" not in native, native
            assert np.array_equal(observation, np.asarray(native["observation"], dtype=np.float32))
            assert native["preparation_slices"] > 1
            for action in np.flatnonzero(masks):
                assert np.array_equal(
                    features[action], np.asarray(native["features"][str(action)], dtype=np.float32)
                )
            args = (
                (torch.as_tensor(features).unsqueeze(0),)
                if architecture == "tactical_actor_critic"
                else ()
            )
            with torch.no_grad():
                distribution, value = model.distribution_and_value(
                    torch.as_tensor(observation).unsqueeze(0),
                    torch.as_tensor(masks).unsqueeze(0),
                    *args,
                )
            normalized = Categorical(logits=torch.tensor(native["logits"]))
            assert torch.allclose(distribution.logits[0], normalized.logits, atol=2e-5)
            assert float(value[0]) == pytest.approx(native["value"], abs=2e-5)
            assert int(distribution.probs.argmax()) == int(normalized.probs.argmax())
            if observer == 2:
                choice = bridge.send_command("choose_neural_action", path=str(exported))
                assert choice["finished"] and choice["slices"] > 0
                assert choice["action"] == ActionCodec().action_to_move(
                    int(distribution.probs.argmax()), snapshot["observation"]["hand"]
                )
            move = snapshot["legal_actions"][(turn * 7) % len(snapshot["legal_actions"])]
            snapshot = bridge.step(move, 1)


@GODOT
def test_godot_and_python_have_identical_content_and_rules_identities():
    with GodotProcess() as bridge:
        manifest = bridge.engine_manifest()
        assert manifest["catalogue_checksum"] == StoneCatalog().checksum
        assert manifest["rules_checksum"] == game_rules_checksum()


@GODOT
def test_random_legal_cross_god_decks_match_real_godot_rules():
    rng = np.random.default_rng(58137)
    fast = FastEngineBridge()
    try:
        with GodotProcess() as bridge:
            catalog = DeckCatalog(bridge.deck_catalog())
            generator = DeckGenerator(catalog)
            for match_index in range(24):
                own_god = catalog.gods[match_index % 6]
                other_god = catalog.gods[(match_index * 5 + 1) % 6]
                own = generator.random_candidate(own_god, rng)
                other = generator.random_candidate(other_god, rng)
                cells = rng.choice(16, size=match_index % 3, replace=False)
                config = {
                    "seed": 20000 + match_index,
                    "portable_rng": True,
                    "human_god": own_god,
                    "ai_god": other_god,
                    "human_deck": list(own.stone_ids),
                    "ai_deck": list(other.stone_ids),
                    "first_player": 1 + match_index % 2,
                    "blocked": [[int(c) // 4, int(c) % 4] for c in cells],
                }
                actual, expected = fast.reset(config, 1), bridge.reset(config, 1)
                while not actual["observation"]["is_game_over"]:
                    assert actual["observation"] == expected["observation"], config
                    move = actual["legal_actions"][int(rng.integers(len(actual["legal_actions"])))]
                    actual, expected = fast.step(move, 1), bridge.step(move, 1)
                    assert actual.get("captures", []) == expected.get("captures", []), config
                assert actual["observation"] == expected["observation"], config
    finally:
        fast.close()


@GODOT
@pytest.mark.parametrize("scenario", SCENARIOS, ids=lambda s: s["god"])
def test_full_match_and_all_tactical_scores_match_godot(scenario):
    god, deck = scenario["god"], scenario["deck"]
    config = {
        "seed": 8107,
        "portable_rng": True,
        "first_player": 1,
        "blocked": [[0, 3]],
        "human_god": god,
        "ai_god": god,
        "human_deck": deck,
        "ai_deck": deck,
    }
    fast = FastEngineBridge()
    try:
        with GodotProcess() as bridge:
            actual = fast.reset(config, 1)
            expected = bridge.reset(config, 1)
            turn = 0
            while not actual["observation"]["is_game_over"]:
                assert actual["observation"] == expected["observation"]
                observer = actual["observation"]["current_player"]
                scores = fast.tactical_action_scores(observer)
                oracle = bridge.tactical_action_scores(observer)
                assert scores.keys() == oracle.keys()
                for action in scores:
                    assert np.allclose(scores[action], oracle[action], atol=1e-6), (
                        god,
                        turn,
                        action,
                        scores[action],
                        oracle[action],
                    )
                move = actual["legal_actions"][(turn * 11) % len(actual["legal_actions"])]
                actual = fast.step(move, 1)
                expected = bridge.step(move, 1)
                assert actual.get("captures", []) == expected.get("captures", [])
                turn += 1
            assert actual["observation"] == expected["observation"]
    finally:
        fast.close()
