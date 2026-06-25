#!/usr/bin/env python3
"""Summarize verify-panel.py stats logs for accuracy/drift tracking.

verify-panel.py appends one JSON line per run to a stats log when
--stats-log <path> (or VERIFY_STATS_LOG env) is set. This script reads
those JSONL files and prints aggregate behavior: per-check pass-rate,
mean latency, finding counts, override counts, and drift signals
(week-over-week comparisons, model-version splits).

Usage:
    tools/panel-stats.py <stats.jsonl> [<stats.jsonl> ...]
    tools/panel-stats.py --since 2026-06-20 path/to/stats.jsonl
    tools/panel-stats.py --by-fixture path/to/stats.jsonl
    tools/panel-stats.py --by-model path/to/stats.jsonl

Designed to be cheap and read-only — no fancy chart libs, no DB. JSONL is
the simplest format that survives months of runs and stays git-friendly.
"""
import argparse
import json
import os
import sys
from collections import Counter, defaultdict


def load(paths: list[str], since: str | None = None) -> list[dict]:
    rows = []
    for p in paths:
        if not os.path.exists(p):
            print(f"  (skip — missing: {p})", file=sys.stderr)
            continue
        with open(p) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    row = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if since and row.get("ts", "") < since:
                    continue
                rows.append(row)
    return rows


def overall_summary(rows: list[dict]) -> None:
    if not rows:
        print("  (no rows)")
        return
    n = len(rows)
    pass_rate = sum(1 for r in rows if r.get("verdict") == "pass") / n * 100
    mean_ms = sum(r.get("total_ms", 0) for r in rows) / n
    print(f"  runs:       {n}")
    print(f"  ts range:   {min(r.get('ts','') for r in rows)} → {max(r.get('ts','') for r in rows)}")
    print(f"  panel pass: {pass_rate:.1f}%   ({sum(1 for r in rows if r.get('verdict')=='pass')}/{n})")
    print(f"  panel mean: {mean_ms/1000:.1f}s")


def per_check_summary(rows: list[dict]) -> None:
    print()
    print("  per check")
    print(f"    {'name':17s}  {'pass%':>6s}  {'runs':>5s}  {'mean_ms':>8s}  {'mean_findings':>13s}  {'failing':>7s}  {'overrides':>9s}")
    by_check: dict[str, list[dict]] = defaultdict(list)
    for r in rows:
        for c in r.get("checks", []):
            if c.get("name"):
                by_check[c["name"]].append(c)
    for name in sorted(by_check):
        cs = by_check[name]
        n = len(cs)
        pass_n = sum(1 for c in cs if c.get("verdict") == "pass")
        mean_ms = sum(c.get("ms", 0) for c in cs) / n if n else 0
        mean_find = sum(c.get("n_findings", 0) for c in cs) / n if n else 0
        mean_fail = sum(c.get("n_failing_findings", 0) for c in cs) / n if n else 0
        total_overrides = sum(c.get("overrides", 0) for c in cs)
        print(f"    {name:17s}  {pass_n/n*100:>5.1f}%  {n:>5d}  {mean_ms:>8.0f}  {mean_find:>13.2f}  {mean_fail:>7.2f}  {total_overrides:>9d}")


def per_fixture_summary(rows: list[dict]) -> None:
    print()
    print("  per fixture")
    print(f"    {'fixture':45s}  {'runs':>4s}  {'pass%':>6s}  {'mean_s':>6s}")
    by_fix: dict[str, list[dict]] = defaultdict(list)
    for r in rows:
        by_fix[r.get("fixture_base", r.get("fixture", "?"))].append(r)
    for fix in sorted(by_fix):
        rs = by_fix[fix]
        n = len(rs)
        pass_pct = sum(1 for r in rs if r.get("verdict") == "pass") / n * 100
        mean_ms = sum(r.get("total_ms", 0) for r in rs) / n
        print(f"    {fix[:45]:45s}  {n:>4d}  {pass_pct:>5.1f}%  {mean_ms/1000:>5.1f}")


def per_model_summary(rows: list[dict]) -> None:
    print()
    print("  per model / backend")
    print(f"    {'model':38s}  {'backend':14s}  {'votes':>5s}  {'runs':>4s}  {'pass%':>6s}  {'mean_s':>6s}")
    by_cfg: dict[tuple[str, str, int], list[dict]] = defaultdict(list)
    for r in rows:
        cfg = r.get("config") or {}
        key = (cfg.get("model", "?"), cfg.get("backend", "?"), int(cfg.get("votes", 1)))
        by_cfg[key].append(r)
    for (model, backend, votes), rs in sorted(by_cfg.items()):
        n = len(rs)
        pass_pct = sum(1 for r in rs if r.get("verdict") == "pass") / n * 100
        mean_ms = sum(r.get("total_ms", 0) for r in rs) / n
        print(f"    {model[:38]:38s}  {backend:14s}  {votes:>5d}  {n:>4d}  {pass_pct:>5.1f}%  {mean_ms/1000:>5.1f}")


def drift_check(rows: list[dict]) -> None:
    """Compare first half of runs vs second half — surface signals of behavior change."""
    if len(rows) < 4:
        return
    print()
    print("  drift signal (first half vs second half of run history)")
    mid = len(rows) // 2
    first, second = rows[:mid], rows[mid:]
    def pct(rs):
        if not rs: return 0.0
        return sum(1 for r in rs if r.get("verdict") == "pass") / len(rs) * 100
    p1, p2 = pct(first), pct(second)
    sign = "↑" if p2 > p1 else ("↓" if p2 < p1 else "·")
    print(f"    panel pass: {p1:.1f}% → {p2:.1f}%  ({sign} {abs(p2-p1):.1f}pp)")
    # per-check drift
    by_check_1: dict[str, list[dict]] = defaultdict(list)
    by_check_2: dict[str, list[dict]] = defaultdict(list)
    for r in first:
        for c in r.get("checks", []):
            if c.get("name"):
                by_check_1[c["name"]].append(c)
    for r in second:
        for c in r.get("checks", []):
            if c.get("name"):
                by_check_2[c["name"]].append(c)
    for name in sorted(set(by_check_1) | set(by_check_2)):
        c1, c2 = by_check_1.get(name, []), by_check_2.get(name, [])
        if not c1 or not c2: continue
        p1 = sum(1 for c in c1 if c.get("verdict") == "pass") / len(c1) * 100
        p2 = sum(1 for c in c2 if c.get("verdict") == "pass") / len(c2) * 100
        if abs(p2 - p1) < 1: continue
        sign = "↑" if p2 > p1 else "↓"
        print(f"    {name:17s} pass: {p1:.1f}% → {p2:.1f}%  ({sign} {abs(p2-p1):.1f}pp)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("paths", nargs="+", help="one or more JSONL stats logs")
    ap.add_argument("--since", help="filter to rows with ts >= this (ISO 8601 date or datetime)")
    ap.add_argument("--by-fixture", action="store_true", help="show per-fixture breakdown")
    ap.add_argument("--by-model",   action="store_true", help="show per-model/backend breakdown")
    args = ap.parse_args()

    rows = load(args.paths, since=args.since)
    print("=== overall ===")
    overall_summary(rows)
    per_check_summary(rows)
    if args.by_fixture:
        per_fixture_summary(rows)
    if args.by_model:
        per_model_summary(rows)
    drift_check(rows)


if __name__ == "__main__":
    main()
