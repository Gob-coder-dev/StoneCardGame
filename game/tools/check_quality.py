"""Run the Godot checks with isolated user data and retain their diagnostics.

No third-party Python packages are needed. GODOT_BIN or --godot selects the
engine; the working directory is independent of the caller's shell.
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import zipfile

PROJECT = Path(__file__).resolve().parents[1]
DEFAULT_SCENES = ("GodSystemChecks", "TouchInputChecks")
SHUTDOWN_ERRORS = re.compile(r"instances were leaked|resources still in use", re.I)
SCRIPT_ERRORS = re.compile(r"SCRIPT ERROR:|Parse Error:|Failed to load script", re.I)


def run_engine(binary: str, name: str, arguments: list[str], output: Path,
               timeout: int) -> subprocess.CompletedProcess | None:
    """Every process gets fresh user data, including import and export processes."""
    with tempfile.TemporaryDirectory(prefix="samstone-check-") as user_dir:
        env = os.environ.copy()
        for key in ("APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CONFIG_HOME",
                    "XDG_CACHE_HOME"):
            env[key] = user_dir
        command = [binary, "--headless", "--verbose", "--fixed-fps", "60", "--path", str(PROJECT),
                   "--log-file", str(output / f"{name}.engine.log"), *arguments]
        try:
            result = subprocess.run(command, env=env, capture_output=True, text=True,
                                    encoding="utf-8", errors="replace", timeout=timeout)
        except subprocess.TimeoutExpired:
            print(f"FAIL {name}: exceeded {timeout} seconds", flush=True)
            return None
        log = result.stdout + "\n" + result.stderr
        (output / f"{name}.log").write_text(log, encoding="utf-8")
        return result


def succeeded(result: subprocess.CompletedProcess | None) -> bool:
    if result is None:
        return False
    log = result.stdout + result.stderr
    return (result.returncode == 0 and not SHUTDOWN_ERRORS.search(log)
            and not SCRIPT_ERRORS.search(log))


def run_check(binary: str, scene: str, output: Path, timeout: int) -> bool:
    result = run_engine(binary, scene, [f"res://tests/{scene}.tscn"], output, timeout)
    summary = [line for line in result.stdout.splitlines()
               if "CHECKS:" in line or "TACTILE :" in line] if result else []
    # A crash or an early exit must not be mistaken for a successful empty test.
    clean = succeeded(result) and bool(summary)
    print(f"{'PASS' if clean else 'FAIL'} {scene}: "
          f"{' | '.join(summary) or 'no summary'}", flush=True)
    if not clean:
        print(f"  diagnostics: {output / (scene + '.log')}", flush=True)
    return clean


def check_export(binary: str, output: Path, timeout: int) -> bool:
    archive = output / "release.zip"
    archive.unlink(missing_ok=True)
    result = run_engine(binary, "export", ["--export-pack", "Android", str(archive)],
                        output, timeout)
    if not succeeded(result) or not zipfile.is_zipfile(archive):
        print(f"FAIL export: see {output / 'export.log'}", flush=True)
        return False
    with zipfile.ZipFile(archive) as package:
        names = package.namelist()
        excluded = ("tests/", "tools/", "data/audio/sources/", "data/campaign/authoring/")
        unwanted = [name for name in names if name.startswith(excluded)
                    or name == "data/campaign/campaign_v1.json"]
        clean = not unwanted and "project.binary" in names
    print(f"{'PASS' if clean else 'FAIL'} export: {archive.stat().st_size / 1024**2:.2f} MiB, "
          f"{len(unwanted)} excluded files found", flush=True)
    return clean


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN") or shutil.which("godot"))
    parser.add_argument("--scene", action="append", dest="scenes")
    parser.add_argument("--timeout", type=int, default=300)
    parser.add_argument("--output", type=Path, default=PROJECT.parent / ".tmp" / "quality")
    parser.add_argument("--import", action="store_true", dest="import_project")
    parser.add_argument("--export", action="store_true", dest="export_project")
    args = parser.parse_args()
    if not args.godot:
        parser.error("provide --godot or set GODOT_BIN")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    if args.import_project:
        result = run_engine(args.godot, "import", ["--editor", "--import"], output, args.timeout)
        if not succeeded(result):
            print(f"FAIL import: see {output / 'import.log'}", flush=True)
            return 1
        print("PASS import", flush=True)
    results = [run_check(args.godot, scene, output, args.timeout)
               for scene in args.scenes or DEFAULT_SCENES]
    if args.export_project:
        results.append(check_export(args.godot, output, args.timeout))
    return 0 if all(results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
