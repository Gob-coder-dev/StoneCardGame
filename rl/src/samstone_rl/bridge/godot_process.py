from __future__ import annotations

import os
import shutil
import socket
import subprocess
import threading
import time
from collections import deque
from pathlib import Path
from typing import Any, Self

from .protocol import Protocol


class GodotProtocolError(RuntimeError):
    pass


class GodotProcess:
    """Own one Godot simulator and exchange bounded JSON-line requests over TCP."""

    def __init__(self, project_path: str | Path | None = None, godot_path: str | Path | None = None,
                 startup_timeout: float = 15.0, command_timeout: float = 30.0) -> None:
        self.project_path = Path(project_path or Path(__file__).resolve().parents[4] / "game")
        self.godot_path = str(godot_path or os.environ.get("GODOT_BIN") or shutil.which("godot")
                              or shutil.which("godot4") or "godot")
        self.startup_timeout = startup_timeout
        self.command_timeout = command_timeout
        self.process: subprocess.Popen[str] | None = None
        self._socket: socket.socket | None = None
        self._reader = None
        self._request_id = 0
        self._logs: deque[str] = deque(maxlen=80)

    def __enter__(self) -> Self:
        self.start()
        return self

    def __exit__(self, *_exc: object) -> None:
        self.close()

    @property
    def diagnostics(self) -> str:
        return "\n".join(self._logs)

    def start(self) -> None:
        if self.process is not None and self.process.poll() is None:
            return
        port = self._free_port()
        command = [self.godot_path, "--headless", "--path", str(self.project_path),
                   "res://tools/rl_sim/HeadlessSim.tscn", "--", "--rl-port", str(port)]
        self.process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                        text=True, encoding="utf-8", errors="replace")
        for stream, label in ((self.process.stdout, "stdout"), (self.process.stderr, "stderr")):
            if stream is not None:
                threading.Thread(target=self._collect_logs, args=(stream, label), daemon=True).start()
        deadline = time.monotonic() + self.startup_timeout
        last_error: OSError | None = None
        while time.monotonic() < deadline:
            if self.process.poll() is not None:
                raise GodotProtocolError(f"Godot s'est arrete au demarrage.\n{self.diagnostics}")
            try:
                self._socket = socket.create_connection(("127.0.0.1", port), timeout=0.25)
                self._socket.settimeout(self.command_timeout)
                self._reader = self._socket.makefile("r", encoding="utf-8", newline="\n")
                if self.ping():
                    return
            except OSError as exc:
                last_error = exc
                time.sleep(0.05)
        self.close()
        raise GodotProtocolError(f"Timeout au demarrage de Godot: {last_error}\n{self.diagnostics}")

    def send_command(self, command: str, **payload: Any) -> dict[str, Any]:
        if self.process is None or self.process.poll() is not None or self._socket is None:
            raise GodotProtocolError(f"Godot n'est pas actif.\n{self.diagnostics}")
        self._request_id += 1
        request_id = self._request_id
        try:
            self._socket.sendall(Protocol.encode_request(command, request_id, **payload).encode("utf-8"))
            line = self._reader.readline()
        except (OSError, TimeoutError) as exc:
            raise GodotProtocolError(f"Echec de '{command}' (id={request_id}): {exc}\n{self.diagnostics}") from exc
        response = Protocol.decode_response(line)
        if response is None or response.get("id") != request_id:
            raise GodotProtocolError(
                f"Reponse invalide pour '{command}' (id={request_id}): {line!r}\n{self.diagnostics}")
        if not response.get("ok", False):
            raise GodotProtocolError(f"Godot refuse '{command}' (id={request_id}): {response.get('error')}")
        return response.get("result", {})

    def ping(self) -> bool:
        return bool(self.send_command("ping").get("pong"))

    def reset(self, config: dict[str, Any], observer: int) -> dict[str, Any]:
        return self.send_command("reset", config=config, observer=observer)

    def legal_actions(self) -> list[dict[str, Any]]:
        return self.send_command("legal_actions").get("legal_actions", [])

    def step(self, action: dict[str, Any], observer: int) -> dict[str, Any]:
        return self.send_command("step", action=action, observer=observer)

    def get_state(self, observer: int) -> dict[str, Any]:
        return self.send_command("get_state", observer=observer)

    def choose_profile_action(self, precision: float, anticipation: bool) -> dict[str, Any]:
        return self.send_command("choose_profile_action", profile={
            "precision": float(precision), "anticipation": bool(anticipation)})["action"]

    def tactical_action_scores(self, observer: int) -> dict[int, tuple[float, ...]]:
        values = self.send_command(
            "tactical_action_scores", observer=int(observer)).get("scores", {})
        return {int(action): tuple(float(value) for value in score)
                for action, score in values.items()}

    def deck_catalog(self) -> dict[str, Any]:
        return self.send_command("get_deck_catalog")

    def engine_manifest(self) -> dict[str, Any]:
        return self.send_command("get_engine_manifest")

    def validate_deck(self, stone_ids: list[str], god_id: str) -> dict[str, Any]:
        return self.send_command("validate_deck", stone_ids=stone_ids, god_id=god_id)

    def validate_decks(self, decks: list[dict[str, Any]]) -> list[dict[str, Any]]:
        return self.send_command("validate_decks", decks=decks)["results"]

    def batch_reset(self, matches: list[dict[str, Any]]) -> list[dict[str, Any]]:
        return self.send_command("batch_reset", matches=matches)["results"]

    def batch_step(self, matches: list[dict[str, Any]]) -> list[dict[str, Any]]:
        return self.send_command("batch_step", matches=matches)["results"]

    def batch_get_state(self, matches: list[dict[str, Any]]) -> list[dict[str, Any]]:
        return self.send_command("batch_get_state", matches=matches)["results"]

    def batch_choose_profile_action(self, matches: list[dict[str, Any]]) -> list[dict[str, Any]]:
        return self.send_command("batch_choose_profile_action", matches=matches)["results"]

    def release_matches(self, match_ids: list[str]) -> int:
        return int(self.send_command("release_matches", match_ids=match_ids)["remaining"])

    def close(self) -> None:
        if self.process is None:
            return
        if self.process.poll() is None and self._socket is not None:
            try:
                self.send_command("shutdown")
                self.process.wait(timeout=3)
            except (GodotProtocolError, OSError, subprocess.TimeoutExpired) as exc:
                self._logs.append(f"shutdown: {exc}")
        if self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=2)
        if self._reader is not None:
            self._reader.close()
        if self._socket is not None:
            self._socket.close()
        self.process = None
        self._socket = None
        self._reader = None

    @staticmethod
    def _free_port() -> int:
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            return int(sock.getsockname()[1])

    def _collect_logs(self, stream, label: str) -> None:
        for line in stream:
            self._logs.append(f"{label}: {line.rstrip()}")
