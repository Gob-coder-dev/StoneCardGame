import json
from typing import Any


class Protocol:
    """Encode requests and decode responses for the local JSON-lines protocol."""

    @staticmethod
    def encode_request(cmd: str, req_id: int, **kwargs: Any) -> str:
        request = {"cmd": cmd, "id": req_id}
        request.update(kwargs)
        return json.dumps(request) + "\n"

    @staticmethod
    def decode_response(line: str) -> dict[str, Any] | None:
        try:
            line = line.strip()
            if not line:
                return None
            value = json.loads(line)
            return value if isinstance(value, dict) else None
        except (json.JSONDecodeError, TypeError):
            return None

