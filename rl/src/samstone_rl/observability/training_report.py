from __future__ import annotations

import csv
import html
import json
from collections import defaultdict
from pathlib import Path
from typing import Any

from .tracker import flatten_metrics

DEFAULT_CHARTS = (
    "evaluation/win_rate",
    "evaluation/wilson_lower",
    "training/episode_return_mean",
    "training/training_win_rate",
    "training/normalized_entropy",
    "training/approx_kl",
    "training/explained_variance",
    "training/steps_per_second",
    "training/memory_rss_mb",
    "deck_evolution/generation/fitness_best",
    "deck_evolution/generation/fitness_median",
    "deck_evolution/generation/lineage_diversity",
    "self_play/episode/score",
    "self_play/episode/agent_rating",
    "self_play/episode/margin",
)


def load_json_lines(path: str | Path) -> tuple[dict[str, Any], ...]:
    source = Path(path)
    if not source.is_file():
        return ()
    events = []
    for line in source.read_text(encoding="utf-8", errors="replace").splitlines():
        if not line.strip():
            continue
        try:
            value = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(value, dict):
            events.append(value)
    return tuple(events)


def generate_training_report(run_directory: str | Path,
                             output_directory: str | Path | None = None) -> dict[str, Any]:
    run = Path(run_directory).resolve()
    output = Path(output_directory).resolve() if output_directory else run / "reports" / "training"
    output.mkdir(parents=True, exist_ok=True)
    events = load_json_lines(run / "metrics.jsonl")
    alerts = load_json_lines(run / "alerts.jsonl")
    if not events:
        raise ValueError(f"aucune métrique dans {run / 'metrics.jsonl'}")
    series: dict[str, list[tuple[int, float]]] = defaultdict(list)
    rows = []
    latest: dict[str, dict[str, Any]] = {}
    for event in events:
        stream = str(event.get("stream", "unknown"))
        step = int(event.get("step", 0))
        latest[stream] = event
        for key, value in flatten_metrics(event.get("metrics", {})).items():
            name = f"{stream}/{key}"
            series[name].append((step, value))
            rows.append({
                "timestamp": event.get("timestamp", ""),
                "stream": stream,
                "step": step,
                "metric": key,
                "value": value,
            })
    summary = {
        "schema_version": 1,
        "run_directory": str(run),
        "events": len(events),
        "alerts": len(alerts),
        "critical_alerts": sum(
            alert.get("severity") == "critical" for alert in alerts),
        "latest": {stream: event.get("metrics", {}) for stream, event in latest.items()},
        "best": {
            name: {"step": max(values, key=lambda item: item[1])[0],
                   "value": max(value for _step, value in values)}
            for name, values in series.items() if values
        },
    }
    _atomic_text(output / "training_summary.json",
                 json.dumps(summary, indent=2, ensure_ascii=False))
    _write_metrics_csv(output / "training_metrics.csv", rows)
    _atomic_text(output / "training_report.html", _html(summary, series, alerts))
    return summary


def latest_status(run_directory: str | Path) -> dict[str, Any]:
    run = Path(run_directory).resolve()
    events = load_json_lines(run / "metrics.jsonl")
    alerts = load_json_lines(run / "alerts.jsonl")
    latest: dict[str, dict[str, Any]] = {}
    for event in events:
        latest[str(event.get("stream", "unknown"))] = event
    return {
        "run": str(run),
        "streams": latest,
        "latest_alerts": list(alerts[-10:]),
    }


def _write_metrics_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    with temporary.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(
            stream, fieldnames=["timestamp", "stream", "step", "metric", "value"])
        writer.writeheader()
        writer.writerows(rows)
    temporary.replace(path)


def _html(summary: dict[str, Any], series: dict[str, list[tuple[int, float]]],
          alerts: tuple[dict[str, Any], ...]) -> str:
    charts = []
    selected = [name for name in DEFAULT_CHARTS if name in series]
    if not selected:
        selected = sorted(series)[:12]
    for name in selected:
        charts.append(
            f"<section><h2>{html.escape(name)}</h2>{_svg(series[name])}</section>")
    alert_rows = "".join(
        "<tr>"
        f"<td>{html.escape(str(item.get('timestamp', '')))}</td>"
        f"<td>{html.escape(str(item.get('severity', '')))}</td>"
        f"<td>{html.escape(str(item.get('code', '')))}</td>"
        f"<td>{html.escape(str(item.get('message', '')))}</td>"
        f"<td>{html.escape(str(item.get('recommendation', '')))}</td>"
        "</tr>" for item in alerts[-100:])
    return f"""<!doctype html><html lang="fr"><meta charset="utf-8">
<title>Suivi d'entraînement SamStone</title><style>
body{{font:14px system-ui;margin:32px;max-width:1300px}}.charts{{display:grid;
grid-template-columns:repeat(auto-fit,minmax(480px,1fr));gap:18px}}section{{border:1px solid #ddd;
padding:12px}}svg{{width:100%;height:auto}}table{{border-collapse:collapse;width:100%}}
th,td{{padding:6px;border-bottom:1px solid #ddd;text-align:left}}.critical{{color:#a00}}</style>
<h1>Suivi d'entraînement SamStone</h1><p>{summary['events']} événements —
{summary['alerts']} alertes, dont <b class="critical">{summary['critical_alerts']} critiques</b>.</p>
<div class="charts">{''.join(charts)}</div><h2>Alertes récentes</h2><table><thead><tr>
<th>Date</th><th>Niveau</th><th>Code</th><th>Diagnostic</th><th>Recommandation</th>
</tr></thead><tbody>{alert_rows}</tbody></table></html>"""


def _svg(points: list[tuple[int, float]], width: int = 600, height: int = 220) -> str:
    if not points:
        return "<p>Aucune donnée.</p>"
    x_values = [item[0] for item in points]
    y_values = [item[1] for item in points]
    x_min, x_max = min(x_values), max(x_values)
    y_min, y_max = min(y_values), max(y_values)
    x_span = max(1, x_max - x_min)
    y_span = max(1e-12, y_max - y_min)
    coordinates = " ".join(
        f"{40 + (x - x_min) / x_span * (width - 60):.1f},"
        f"{10 + (y_max - y) / y_span * (height - 40):.1f}"
        for x, y in points)
    return (
        f'<svg viewBox="0 0 {width} {height}" role="img">'
        f'<line x1="40" y1="10" x2="40" y2="{height - 30}" stroke="#999"/>'
        f'<line x1="40" y1="{height - 30}" x2="{width - 20}" y2="{height - 30}" stroke="#999"/>'
        f'<polyline fill="none" stroke="#3b6bd6" stroke-width="2" points="{coordinates}"/>'
        f'<text x="42" y="20" font-size="11">{y_max:.4g}</text>'
        f'<text x="42" y="{height - 34}" font-size="11">{y_min:.4g}</text>'
        f'<text x="{width - 90}" y="{height - 12}" font-size="11">step {x_max}</text></svg>')


def _atomic_text(path: Path, content: str) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(content, encoding="utf-8")
    temporary.replace(path)
