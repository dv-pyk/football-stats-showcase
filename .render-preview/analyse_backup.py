"""Runs a faithful port of PressureEngine over a real backup export.

Kept alongside the render harness so calibration questions can be answered against
recorded matches instead of synthetic data.
"""

import json
import statistics
import sys
from collections import Counter, defaultdict

PASS = 1.0
INTERCEPT = 5.0
SHOT_OFF = 1.0
SHOT_ON = 3.0
GOAL = 8.0
CORNER_BONUS = 1.5
HOLD = 1.0
TICK_SECONDS = 10
LOOKBACK = 120
SAMPLE_STEP = 15

GAINING = {
    "ourPass": "home",
    "weIntercepted": "home",
    "awayBallOut": "home",
    "possessionToHome": "home",
    "theirPass": "away",
    "theyIntercepted": "away",
    "homeBallOut": "away",
    "possessionToAway": "away",
}

PASS_DELTA = {
    "ourPass": PASS,
    "theirPass": -PASS,
    "weIntercepted": INTERCEPT,
    "theyIntercepted": -INTERCEPT,
}


def possession_spells(match):
    end = max(match["elapsedSeconds"], 1)
    changes = [(p["matchSeconds"], 0, GAINING[p["type"]]) for p in match["passes"]]
    for goal in match["goals"]:
        changes.append((goal["matchSeconds"], 1, "away" if goal["team"] == "home" else "home"))

    spells = []
    current = match["kickoffPossession"]
    start = 0
    for seconds, _kind, team in sorted(changes):
        if not (start < seconds <= end):
            current = team
            continue
        # Mirrors the shipped engine: only close the spell when the ball actually
        # changes hands, so a run of taps for one side stays a single spell.
        if team == current:
            continue
        spells.append((current, start, seconds))
        current = team
        start = seconds

    if end > start:
        spells.append((current, start, end))
    return spells


def events(match, include_hold=True, include_passes=True):
    """Returns (seconds, delta, source) so each mechanic's share can be measured."""
    result = []

    if include_passes:
        for p in match["passes"]:
            delta = PASS_DELTA.get(p["type"])
            if delta is not None:
                result.append((p["matchSeconds"], delta, "pass"))

    for shot in match["shots"]:
        sign = 1 if shot["team"] == "home" else -1
        if shot["outcome"] == "Goal":
            weight = GOAL
        elif shot["outcome"] == "On target":
            weight = SHOT_ON
        else:
            weight = SHOT_OFF
        if shot["difficulty"] == "Corners":
            weight += CORNER_BONUS
        result.append((shot["matchSeconds"], sign * weight, "shot"))

    if include_hold:
        for team, start, end in possession_spells(match):
            sign = 1 if team == "home" else -1
            tick = start + TICK_SECONDS
            while tick <= end:
                result.append((tick, sign * HOLD, "hold"))
                tick += TICK_SECONDS

    return sorted(result)


def value_at(seconds, evs):
    total = 0.0
    for sec, delta, _src in evs:
        if sec > seconds:
            break
        age = seconds - sec
        if age > LOOKBACK:
            continue
        total += delta * (1.0 - (age / LOOKBACK) * 0.6)
    return total


def curve(match, **kwargs):
    evs = events(match, **kwargs)
    end = max(match["elapsedSeconds"], evs[-1][0] if evs else 0)
    return [(t, value_at(t, evs)) for t in range(SAMPLE_STEP, end + 1, SAMPLE_STEP)]


def contribution_by_source(match):
    """Absolute faded contribution each mechanic makes, summed over the sampled curve."""
    evs = events(match)
    end = max(match["elapsedSeconds"], evs[-1][0] if evs else 0)
    totals = defaultdict(float)
    for t in range(SAMPLE_STEP, end + 1, SAMPLE_STEP):
        for sec, delta, src in evs:
            if sec > t:
                break
            age = t - sec
            if age > LOOKBACK:
                continue
            totals[src] += abs(delta * (1.0 - (age / LOOKBACK) * 0.6))
    return totals


def main(path):
    records = json.load(open(path))
    print(f"{len(records)} matches\n")

    print("=== possession spell lengths (seconds the ball is held before a change) ===")
    print(f"{'opponent':22} {'style':10} {'spells':>6} {'median':>7} {'mean':>6} {'>=10s':>7} {'>=20s':>7}")
    for r in records:
        m = r["match"]
        style = "possChg" if any(p["type"].startswith("possessionTo") for p in m["passes"]) else "intercept"
        lengths = [e - s for _t, s, e in possession_spells(m)]
        over10 = sum(1 for x in lengths if x >= TICK_SECONDS) / len(lengths) * 100
        over20 = sum(1 for x in lengths if x >= 20) / len(lengths) * 100
        print(f"{m['awayTeamName'][:22]:22} {style:10} {len(lengths):>6} "
              f"{statistics.median(lengths):>7.1f} {statistics.mean(lengths):>6.1f} "
              f"{over10:>6.1f}% {over20:>6.1f}%")

    print("\n=== how much each mechanic actually drives the curve ===")
    print(f"{'opponent':22} {'style':10} {'pass':>8} {'shot':>8} {'hold':>8}   hold share")
    for r in records:
        m = r["match"]
        style = "possChg" if any(p["type"].startswith("possessionTo") for p in m["passes"]) else "intercept"
        t = contribution_by_source(m)
        total = sum(t.values()) or 1
        print(f"{m['awayTeamName'][:22]:22} {style:10} {t['pass']:>8.0f} {t['shot']:>8.0f} "
              f"{t['hold']:>8.0f}   {t['hold'] / total * 100:>5.1f}%")

    print("\n=== curve range, and home bias ===")
    print(f"{'opponent':22} {'style':10} {'min':>7} {'max':>7} {'mean':>7} {'%time home+':>11}  score")
    for r in records:
        m = r["match"]
        style = "possChg" if any(p["type"].startswith("possessionTo") for p in m["passes"]) else "intercept"
        vals = [v for _t, v in curve(m)]
        pos = sum(1 for v in vals if v > 0) / len(vals) * 100
        hg = sum(1 for g in m["goals"] if g["team"] == "home")
        ag = len(m["goals"]) - hg
        print(f"{m['awayTeamName'][:22]:22} {style:10} {min(vals):>7.1f} {max(vals):>7.1f} "
              f"{statistics.mean(vals):>7.1f} {pos:>10.1f}%  {hg}-{ag}")

    print("\n=== pass-tap symmetry (does the recorder favour their own team?) ===")
    print(f"{'opponent':22} {'ourPass':>8} {'theirPass':>10} {'ratio':>6}   possession%  goals")
    for r in records:
        m = r["match"]
        c = Counter(p["type"] for p in m["passes"])
        hs = as_ = 0
        for team, s, e in possession_spells(m):
            if team == "home":
                hs += e - s
            else:
                as_ += e - s
        tot = max(hs + as_, 1)
        home_pct = round(hs / tot * 100)
        ratio = c["ourPass"] / max(c["theirPass"], 1)
        hg = sum(1 for g in m["goals"] if g["team"] == "home")
        print(f"{m['awayTeamName'][:22]:22} {c['ourPass']:>8} {c['theirPass']:>10} {ratio:>6.2f}   "
              f"{home_pct:>3}/{100 - home_pct:<3}      {hg}-{len(m['goals']) - hg}")

    print("\n=== data integrity ===")
    seen = defaultdict(list)
    for r in records:
        m = r["match"]
        seen[(m["awayTeamName"].replace(" ", ""), m["elapsedSeconds"], len(m["shots"]))].append(r["savedAt"][:10])
        late = [s["matchSeconds"] for s in m["shots"] if s["matchSeconds"] > m["elapsedSeconds"]]
        late += [p["matchSeconds"] for p in m["passes"] if p["matchSeconds"] > m["elapsedSeconds"]]
        shot_goals = sum(1 for s in m["shots"] if s["outcome"] == "Goal")
        # saves + conceded should equal opponent shots on target under countsAsShot
        issues = []
        if shot_goals != len(m["goals"]):
            issues.append(f"goals[]={len(m['goals'])} but shots with Goal outcome={shot_goals}")
        if late:
            issues.append(f"{len(late)} events past final whistle (max {max(late)} vs {m['elapsedSeconds']})")
        if m["kickoffPossession"] != m["possessionBaseline"]:
            issues.append(f"kickoff={m['kickoffPossession']} baseline={m['possessionBaseline']}")
        print(f"  {m['awayTeamName'][:24]:24} {'; '.join(issues) if issues else 'ok'}")

    print("\n  duplicate candidates:")
    for key, dates in seen.items():
        if len(dates) > 1:
            print(f"    {key} saved on {dates}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "Football-Stats-Backup-2026-07-25.json")
