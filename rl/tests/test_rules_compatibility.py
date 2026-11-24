"""Resume unrelated Godot edits without weakening combat/content guards."""

import hashlib
import json
import subprocess

import pytest
from test_contracts import tiny_config

from samstone_rl.observability import RunTracker
from samstone_rl.training.ppo_cleanrl import PPOTrainer
from samstone_rl.utils.checkpoints import load_checkpoint, save_checkpoint
from samstone_rl.utils.provenance import game_rules_checksum
from samstone_rl.utils.rules_compatibility import (
    fingerprint,
    noncombat_change_proof,
    rules_sources,
    source_hash,
)


def write_source(root, relative, text):
    path = root / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(text.encode("utf-8"))


@pytest.fixture
def game(tmp_path):
    root = tmp_path / "game"
    write_source(root, "scripts/engine/Combat.gd", "extends RefCounted\n")
    write_source(root, "scripts/ai/Bot.gd", "extends RefCounted\n")
    write_source(root, "scripts/data/economy/EconomyConfig.gd", "const PRICE = 10\n")
    return root


def test_snapshot_proves_economy_changes_without_git(game, monkeypatch):
    previous = rules_sources(game)
    checksum = fingerprint(previous)
    assert checksum == game_rules_checksum(game)
    assert source_hash(b"\xef\xbb\xbfextends RefCounted\r\n") == source_hash(
        b"extends RefCounted\n"
    )
    write_source(game, "scripts/data/economy/EconomyConfig.gd", "const PRICE = 20\n")

    def no_git(*_args, **_kwargs):
        pytest.fail("checkpoint snapshots must not depend on Git")

    monkeypatch.setattr(subprocess, "run", no_git)
    proof = noncombat_change_proof(game, checksum, previous)
    assert proof["changed_files"] == ["scripts/data/economy/EconomyConfig.gd"]
    assert proof["rules_checksum"] == game_rules_checksum(game)
    assert proof["evidence"] == "checkpoint_sources"
    assert noncombat_change_proof(game, checksum, {**previous, "tampered": "x"}) is None


@pytest.mark.parametrize(
    "path",
    [
        "scripts/engine/Combat.gd",
        "scripts/ai/Bot.gd",
        "scripts/domain/DeckRules.gd",
        "scripts/data/MonsterLoader.gd",
    ],
)
def test_combat_edits_and_new_combat_sources_are_rejected(game, path):
    previous = rules_sources(game)
    write_source(game, path, "const CHANGED = true\n")
    assert noncombat_change_proof(game, fingerprint(previous), previous) is None


def test_deleted_combat_source_is_rejected(game):
    previous = rules_sources(game)
    (game / "scripts/ai/Bot.gd").unlink()
    assert noncombat_change_proof(game, fingerprint(previous), previous) is None


def test_legacy_git_evidence_must_match_exact_saved_identity(game):
    def git(*args):
        return (
            subprocess.run(["git", *args], cwd=game.parent, capture_output=True, check=True)
            .stdout.decode()
            .strip()
        )

    git("init")
    git("add", "game")
    git("-c", "user.name=RL test", "-c", "user.email=rl@example.invalid", "commit", "-m", "base")
    checksum, commit = game_rules_checksum(game), git("rev-parse", "HEAD")
    write_source(game, "scripts/data/economy/EconomyConfig.gd", "const PRICE = 20\n")
    git("add", "game")
    git("-c", "user.name=RL test", "-c", "user.email=rl@example.invalid", "commit", "-m", "shop")
    proof = noncombat_change_proof(game, checksum)
    assert proof["evidence"] == f"git:{commit}"
    assert proof["changed_files"] == ["scripts/data/economy/EconomyConfig.gd"]
    assert noncombat_change_proof(game, "0" * 64) is None
    write_source(game, "scripts/engine/Combat.gd", "const CHANGED = true\n")
    assert noncombat_change_proof(game, checksum) is None


@pytest.mark.parametrize("checksum", [None, "changed", "f" * 64])
def test_missing_evidence_never_authorizes_resume(game, checksum, monkeypatch):
    def missing_git(*_args, **_kwargs):
        raise FileNotFoundError("git unavailable")

    monkeypatch.setattr(subprocess, "run", missing_git)
    assert noncombat_change_proof(game, checksum) is None


def test_noncombat_resume_preserves_optimizer_stage_and_audits_manifest(tmp_path):
    path = tiny_config(tmp_path)
    with PPOTrainer(path) as trainer:
        trainer.curriculum.stage_index = 3
        trainer.train()
    target = tmp_path / "run/latest.pt"
    payload = load_checkpoint(target)
    current_sources = payload["rules_sources"]
    previous_sources = {**current_sources, "scripts/data/economy/EconomyConfig.gd": "f" * 64}
    old_hash = fingerprint(previous_sources)
    payload["rules_sources"] = previous_sources
    payload["provenance"]["game_rules"] = old_hash
    old_oracle = {**payload["oracle_manifest"], "rules_checksum": old_hash}
    payload["oracle_manifest"] = old_oracle
    save_checkpoint(target, payload)
    with RunTracker(tmp_path / "run", "ppo", tensorboard=False) as tracker:
        manifest = json.loads(tracker.manifest_path.read_text(encoding="utf-8"))
        manifest["extra"]["oracle_manifest"] = old_oracle
        manifest["checksums"]["oracle"] = hashlib.sha256(
            json.dumps(old_oracle, sort_keys=True).encode()
        ).hexdigest()
        tracker.write_manifest(manifest)
    with PPOTrainer(path, mode="resume") as trainer:
        trainer._oracle_manifest = {**old_oracle, "rules_checksum": fingerprint(current_sources)}
        trainer.load_checkpoint(target)
        assert trainer.curriculum.state_dict() == payload["curriculum"]
        assert trainer.curriculum.stage_index == 3
        assert trainer._resume_global_step == 16
        assert trainer.optimizer.state_dict()["state"]
        trainer._record_engine_manifest()
        trainer._save("resumed.pt", 16, {}, 1)
    manifest = json.loads((tmp_path / "run/run_manifest.json").read_text(encoding="utf-8"))
    audit = manifest["extra"]["noncombat_source_migrations"]
    assert audit[-1]["previous_rules_checksum"] == old_hash
    assert audit[-1]["rules_checksum"] == fingerprint(current_sources)
    assert load_checkpoint(tmp_path / "run/resumed.pt")["rules_sources"] == current_sources


@pytest.mark.parametrize("changed_field", ["catalogue_checksum", "godot_version"])
def test_manifest_migration_rejects_other_oracle_changes(tmp_path, changed_field):
    previous = {"rules_checksum": "old", "catalogue_checksum": "catalog", "godot_version": "4"}
    oracle = {**previous, "rules_checksum": "new", changed_field: "changed"}
    with RunTracker(tmp_path, "ppo", tensorboard=False) as tracker:
        original = {
            "checksums": {
                "oracle": hashlib.sha256(json.dumps(previous, sort_keys=True).encode()).hexdigest()
            },
            "extra": {"oracle_manifest": previous},
        }
        tracker.write_manifest(original)
        with pytest.raises(ValueError, match="incompatible"):
            tracker.migrate_noncombat_sources(
                oracle, {"previous_rules_checksum": "old", "rules_checksum": "new"}
            )
        assert json.loads(tracker.manifest_path.read_text(encoding="utf-8")) == original
