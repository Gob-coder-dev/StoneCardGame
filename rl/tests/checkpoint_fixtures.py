"""Small, explicitly synthetic certifications for component integration tests."""

from samstone_rl.models.policy import policy_spec
from samstone_rl.utils.certification import certify_checkpoint
from samstone_rl.utils.provenance import provenance


def certified(payload, phase):
    current = provenance()
    payload["provenance"] = current
    payload["policy_spec"] = policy_spec(payload["config"])
    oracle = {
        "godot_version": "test fixture",
        "action_feature_schema": 2,
        "catalogue_checksum": current["content"],
        "rules_checksum": current["game_rules"],
    }
    certify_checkpoint(payload, phase, {"passed": True, "fixture": True}, oracle)
    return payload
