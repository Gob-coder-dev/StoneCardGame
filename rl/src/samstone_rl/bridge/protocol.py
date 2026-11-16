import json
from typing import Any


def translate_keys(value: Any, mapping: dict[str, str]) -> Any:
    """Keep historical RL/checkpoint names behind the renamed Godot wire API."""
    if isinstance(value, dict):
        return {mapping.get(key, key): translate_keys(item, mapping) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [translate_keys(item, mapping) for item in value]
    return value


class Protocol:
    """Encode requests and decode responses for the local JSON-lines protocol."""

    @staticmethod
    def encode_request(cmd: str, req_id: int, **kwargs: Any) -> str:
        request = {"cmd": cmd, "id": req_id}
        request.update(kwargs)
        return (
            json.dumps(
                translate_keys(
                    request,
                    {"stone_id": "monster_id", "stone_ids": "monster_ids", "stone": "monster"},
                )
            )
            + "\n"
        )

    @staticmethod
    def decode_response(line: str) -> dict[str, Any] | None:
        try:
            line = line.strip()
            if not line:
                return None
            value = json.loads(line)
            return (
                translate_keys(
                    value,
                    {"monster_id": "stone_id", "monster_ids": "stone_ids", "monster": "stone"},
                )
                if isinstance(value, dict)
                else None
            )
        except (json.JSONDecodeError, TypeError):
            return None
