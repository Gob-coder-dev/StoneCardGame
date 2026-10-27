import subprocess
import json
import time
import os
import shutil
from pathlib import Path
from typing import Dict, Any, Optional
from .protocol import Protocol


class GodotProcess:
    """Manage Godot headless process for RL simulation"""
    
    def __init__(self, project_path: str = None, godot_path: str = None):
        if project_path is None:
            # bridge/ -> samstone_rl/ -> src/ -> rl/ -> dépôt -> game/
            project_path = str(Path(__file__).resolve().parents[4] / "game")
        
        self.project_path = project_path
        self.sim_scene = "res://tools/rl_sim/HeadlessSim.tscn"
        self.process = None
        self.req_id = 0
        
        # CLI explicite, variable d'environnement, puis PATH.
        if godot_path is None:
            godot_path = (
                os.environ.get("GODOT_BIN")
                or shutil.which("godot")
                or shutil.which("godot4")
                or "godot"
            )
        
        self.godot_path = godot_path
    
    def start(self):
        """Start Godot headless process"""
        godot_exec = self.godot_path
        cmd = [
            godot_exec,
            "--headless",
            "--path", self.project_path,
            self.sim_scene
        ]
        self.process = subprocess.Popen(
            cmd,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1
        )
        # Wait for ready signal
        time.sleep(3)
        self._read_ready()
    
    def _read_ready(self):
        """Read initial ready message"""
        try:
            if self.process.stdout:
                # Read a few lines to consume startup messages
                for _ in range(5):
                    try:
                        line = self.process.stdout.readline()
                        if not line:
                            break
                        if line.strip():
                            print(f"Godot: {line.strip()}")
                        if "RL_SIM_READY" in line:
                            break
                    except:
                        break
        except:
            pass
    
    def send_command(self, cmd: str, **kwargs) -> Dict[str, Any]:
        """Send command to Godot and get response"""
        if self.process is None or self.process.poll() is not None:
            raise RuntimeError("Godot process not running")
        
        self.req_id += 1
        request = Protocol.encode_request(cmd, self.req_id, **kwargs)
        
        try:
            self.process.stdin.write(request)
            self.process.stdin.flush()
            
            # Read response
            response_line = self.process.stdout.readline()
            if not response_line:
                raise RuntimeError("No response from Godot")
            
            response = Protocol.decode_response(response_line)
            if response is None:
                raise RuntimeError(f"Invalid response: {response_line}")
            
            return response
        except Exception as e:
            raise RuntimeError(f"Communication error: {e}")
    
    def ping(self) -> bool:
        resp = self.send_command("ping")
        return resp.get("ok", False) and resp.get("result", {}).get("pong", False)
    
    def reset(self, config: Dict[str, Any]) -> Dict[str, Any]:
        resp = self.send_command("reset", config=config)
        return resp.get("result", {}) if resp.get("ok") else {}
    
    def get_legal_moves(self) -> list:
        resp = self.send_command("get_legal_moves")
        if resp.get("ok"):
            return resp.get("result", {}).get("legal_moves", [])
        return []
    
    def step(self, action: Dict[str, Any]) -> Dict[str, Any]:
        resp = self.send_command("step", action=action)
        return resp.get("result", {}) if resp.get("ok") else {"reward": 0.0, "done": True}
    
    def close(self):
        if self.process:
            try:
                self.process.terminate()
                self.process.wait(timeout=2)
            except:
                self.process.kill()
            self.process = None

