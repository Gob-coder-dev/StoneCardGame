"""Bind a successful authoritative evaluation to exact weights and contracts."""

from __future__ import annotations

import hashlib
import json
from typing import Any

from samstone_rl.models.policy import policy_spec

from .checkpoints import state_checksum


def certify_checkpoint(
    payload: dict[str, Any], phase: str, report: dict[str, Any], oracle: dict[str, Any]
) -> None:
    if not report.get("passed") or oracle.get("godot_version") in (None, "in-process"):
        raise ValueError("une certification exige une validation Godot reussie")
    payload["certification"] = {
        "schema": 1,
        "phase": phase,
        "weights": state_checksum(payload["model"]),
        "report": report,
        "report_sha256": _report_checksum(report),
        "oracle": oracle,
    }


def require_certified(payload: dict[str, Any], phase: str, current: dict[str, Any]) -> None:
    certificate = payload.get("certification", {})
    report = certificate.get("report", {})
    oracle = certificate.get("oracle", {})
    if (
        certificate.get("schema") != 1
        or certificate.get("phase") != phase
        or not report.get("passed")
        or certificate.get("report_sha256") != _report_checksum(report)
        or certificate.get("weights") != state_checksum(payload["model"])
        or payload.get("provenance") != current
        or payload.get("policy_spec") != policy_spec(payload.get("config", {}))
        or oracle.get("catalogue_checksum") != current["content"]
        or oracle.get("rules_checksum") != current["game_rules"]
        or oracle.get("action_feature_schema") != current["feature_schema"]
    ):
        raise ValueError(
            f"certification {phase} absente, perimee ou incompatible; reevaluer les poids"
        )


def _report_checksum(report: dict[str, Any]) -> str:
    return hashlib.sha256(
        json.dumps(report, sort_keys=True, separators=(",", ":")).encode()
    ).hexdigest()
