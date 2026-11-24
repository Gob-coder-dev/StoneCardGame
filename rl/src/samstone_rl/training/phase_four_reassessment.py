"""Rescore a frozen Godot tournament under an explicitly revised gate contract.

Recorded matches keep their original policy, engine, schedule and provenance.
Only acceptance thresholds may change; this is not an independent evaluation.
"""

import json
from copy import deepcopy
from datetime import datetime, timezone
from pathlib import Path

import yaml

from samstone_rl.bridge.godot_process import GodotProcess
from samstone_rl.evaluation.tournament import read_completed_tournament
from samstone_rl.models.policy import policy_spec
from samstone_rl.observability.tracker import RunTracker, build_run_manifest
from samstone_rl.training.phase_four_gate import phase_four_cases, phase_four_report
from samstone_rl.utils.certification import certify_checkpoint, require_certified
from samstone_rl.utils.checkpoints import (
    atomic_text,
    file_checksum,
    load_checkpoint,
    save_checkpoint,
    state_checksum,
)
from samstone_rl.utils.provenance import provenance
from samstone_rl.utils.run_lock import RunLock

RATE_SETTINGS = (
    "overall_win_rate",
    "confidence_floor",
    "maximum_loss_rate",
    "non_loss_confidence_floor",
    "minimum_slice_win_rate",
    "maximum_slice_loss_rate",
    "god_thresholds",
    "core_god_thresholds",
)


def _match_configuration(original: dict, revised: dict) -> None:
    contracts = [deepcopy(value) for value in (original, revised)]
    for contract in contracts:
        for key in RATE_SETTINGS:
            contract["evaluation"]["final_gate"].pop(key, None)
        # These runtime choices do not change the recorded match schedule.
        contract.pop("device", None)
        contract.pop("monitoring", None)
        contract["environment"].pop("godot_path", None)
    if contracts[0] != contracts[1]:
        raise ValueError(
            "seuls les seuils de validation peuvent changer pour reutiliser les parties"
        )


def reassess_phase_four(
    config_path: Path,
    checkpoint_path: Path,
    *,
    allow_python_source_change: bool = False,
    commit: bool = True,
) -> dict:
    config_path, checkpoint_path = Path(config_path).resolve(), Path(checkpoint_path).resolve()
    config = yaml.safe_load(config_path.read_text(encoding="utf-8"))
    output = (config_path.parent.parent / config["output_dir"]).resolve()
    if not checkpoint_path.is_relative_to(output):
        raise ValueError("checkpoint hors du dossier du run")
    lease = RunLock(output)
    try:
        return _reassess_locked(
            config_path, checkpoint_path, output, config, allow_python_source_change, commit
        )
    finally:
        lease.close()


def _reassess_locked(config_path, checkpoint_path, output, config, allow_source_change, commit):
    source = load_checkpoint(checkpoint_path)
    current = provenance()
    if source.get("certification", {}).get("phase") == "phase4" and source.get("config") == config:
        require_certified(source, "phase4", current)
        return source["certification"]["report"]
    state = source.get("phase4_automation", {})
    frozen = state.get("candidate")
    snapshot_path = (
        Path(frozen["path"])
        if frozen is not None
        else output
        / f"evaluations/phase4/candidates/attempt_{int(state.get('attempts', 0)):04d}.pt"
    ).resolve()
    if not snapshot_path.is_relative_to((output / "evaluations/phase4/candidates").resolve()):
        raise ValueError("candidat hors du dossier des snapshots")
    if not snapshot_path.with_suffix(".pt.sha256").is_file():
        raise ValueError("empreinte du candidat fige absente")
    snapshot = load_checkpoint(snapshot_path)
    candidate = snapshot["phase4_automation"]["candidate"]
    identity = candidate["identity"]
    policy = state_checksum(snapshot["model"])
    if (
        policy != identity["policy"]
        or state_checksum(source["model"]) != policy
        or snapshot["provenance"] != identity["provenance"]
        or snapshot["config"] != identity["config"]
        or snapshot.get("oracle_manifest") != identity["oracle"]
        or snapshot.get("policy_spec") != policy_spec(config)
        or not snapshot["curriculum"].get("awaiting_final_validation")
    ):
        raise ValueError("poids, contrats ou identite du candidat incompatibles avec le tournoi")
    changed = {
        key
        for key in current.keys() | identity["provenance"].keys()
        if current.get(key) != identity["provenance"].get(key)
    }
    if changed and not (changed == {"python_source"} and allow_source_change):
        raise ValueError(
            "provenance incompatible; un changement Python exige --allow-python-source-change"
        )
    _match_configuration(identity["config"], config)
    if config["environment"].get("evaluation_backend") != "godot":
        raise ValueError("la certification exige un tournoi Godot")
    with GodotProcess(godot_path=config["environment"].get("godot_path")) as bridge:
        oracle = bridge.engine_manifest()
    if oracle != identity["oracle"]:
        raise ValueError("moteur Godot different du tournoi enregistre")
    cases = phase_four_cases(identity["config"], int(candidate["seed_offset"]))
    ledger, outcomes = read_completed_tournament(cases, output / "evaluations/phase4", identity)
    report = phase_four_report(config, cases, outcomes).to_dict()
    report["reassessment"] = dict(
        schema=1,
        retrospective=True,
        independent_evaluation=False,
        timestamp=datetime.now(timezone.utc).isoformat(),
        source_checkpoint=str(checkpoint_path),
        source_checkpoint_sha256=file_checksum(checkpoint_path),
        frozen_candidate=str(snapshot_path),
        frozen_candidate_sha256=file_checksum(snapshot_path),
        policy=policy,
        ledger=str(ledger),
        ledger_sha256=file_checksum(ledger),
        recorded_games=len(outcomes),
        previous_criteria=identity["config"]["evaluation"]["final_gate"],
        revised_criteria=config["evaluation"]["final_gate"],
        recorded_provenance=identity["provenance"],
        reassessment_provenance=current,
    )
    if not commit:
        return report
    # Never replace a newer model when the user rescored an older snapshot.
    latest_path = output / "latest.pt"
    latest = load_checkpoint(latest_path)
    if state_checksum(latest["model"]) != policy:
        raise ValueError("latest.pt a des poids differents; aucune certification ecrite")
    with RunTracker(
        output, "ppo", tensorboard=bool(config.get("monitoring", {}).get("tensorboard", True))
    ) as tracker:
        tracker.initialize_manifest(
            build_run_manifest("ppo", config, config_path, int(config["seed"])),
            mutable_config_paths=(
                ("evaluation", "final_gate"),
                ("device",),
                ("monitoring",),
                ("environment", "godot_path"),
            ),
        )
        if report["passed"]:
            archive = snapshot_path.with_suffix(".before_reassessment.pt")
            if not archive.exists():
                save_checkpoint(archive, latest)
            report["reassessment"]["previous_latest_archive"] = str(archive)
            report["reassessment"]["previous_latest_archive_sha256"] = file_checksum(archive)
            payload = deepcopy(latest)
            payload.update(
                config=config, provenance=current, oracle_manifest=oracle, evaluation=report
            )
            payload["curriculum"].update(
                completed=True, awaiting_final_validation=False, bootstrap_evaluation_completed=True
            )
            payload["phase4_automation"].update(status="completed", candidate=None)
            certify_checkpoint(payload, "phase4", report, oracle)
            require_certified(payload, "phase4", current)
            save_checkpoint(output / "phase4_validated.pt", payload)
            save_checkpoint(latest_path, payload)
            status = dict(
                phase="completed",
                checkpoint="phase4_validated.pt",
                step=payload["global_step"],
                update=payload["update"],
                reassessment=True,
                recorded_games=len(outcomes),
            )
            atomic_text(output / "phase4_status.json", json.dumps(status, indent=2))
        atomic_text(snapshot_path.with_suffix(".reassessment.json"), json.dumps(report, indent=2))
        atomic_text(output / "phase4_gate.json", json.dumps(report, indent=2))
        tracker.update_manifest(extra={"phase4_reassessment": report["reassessment"]})
        tracker.log(
            "final_gate_reassessment",
            int(source["global_step"]),
            report,
            {"retrospective": True, "update": int(source["update"])},
        )
    return report
