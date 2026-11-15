"""Export a certified boss (or an explicitly unvalidated diagnostic fixture)."""

import argparse
from pathlib import Path

from samstone_rl.models.export import export_policy


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("checkpoint", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument(
        "--allow-unvalidated",
        action="store_true",
        help="diagnostic uniquement, refuse par NeuralAI en jeu",
    )
    args = parser.parse_args()
    metadata = export_policy(args.checkpoint, args.output, allow_unvalidated=args.allow_unvalidated)
    print(
        f"Export: {args.output} ({args.output.stat().st_size} octets), "
        f"validation={metadata['validated']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
