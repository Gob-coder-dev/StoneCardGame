import json
from typing import Dict, Any, Optional


class Protocol:
    """Simple JSON line-based protocol for Godot <-> Python communication"""
    
    @staticmethod
    def encode_request(cmd: str, req_id: int, **kwargs) -> str:
        request = {"cmd": cmd, "id": req_id}
        request.update(kwargs)
        return json.dumps(request) + "\n"
    
    @staticmethod
    def decode_response(line: str) -> Optional[Dict[str, Any]]:
        try:
            line = line.strip()
            if not line:
                return None
            return json.loads(line)
        except json.JSONDecodeError:
            return None

