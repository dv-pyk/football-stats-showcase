# Pressure index — how it's actually calculated

Reference for `FootballStats/Models/PressureEngine.swift`. This documents the logic as it
exists today, before the half-aware rework — treat it as the baseline to diff against once
that lands, not a design spec.

The pressure index is a **running momentum score**, not a cumulative stat count. It answers
"who's on top right now," decaying older events so a goal from 10 minutes ago stops
dominating the picture. It is not the same thing as possession % or the shot/save
comparison stats — those are separate calculations that happen to live in the same file
(see "Related, but not pressure" at the bottom).

## 1. Events and their weights

`PressureEngine.events(from:)` walks the match's passes, shots, and set pieces once and
turns each into a single `(seconds, delta)` pair. Home events are positive, away events are
negative — the index is one signed number, not two team totals.

| Event | Weight | Notes |
|---|---|---|
| Pass kept (`ourPass`/`theirPass`) | ±1 | `PressureWeight.pass` |
| Interception (explicit tap, or inferred — see §2) | ±5 | `PressureWeight.intercept` |
| Shot off target | ±1 | `PressureWeight.shotOffTarget` |
| Shot on target (save or block) | ±3 | `PressureWeight.shotOnTarget` |
| Goal | ±8 | `PressureWeight.goal` |
| Corner-difficulty shot (legacy, rules v1 data only) | + `PressureWeight.cornerBonus` (1.5) on top of the outcome weight above | `ShotDifficulty.corner` hasn't been tappable since rules v2; this only fires when replaying old data |
| Set piece won: Corner / Free Kick | ±1.5 | `PressureWeight.setPieceWeight(.corner / .freeKick)` — credited the instant it's won, independent of whatever shot follows |
| Set piece won: Penalty | ±6 | `PressureWeight.setPieceWeight(.penalty)` — deliberately much closer to a goal (8) than a corner, since penalties convert far more often |
| Ball out, plain possession change | 0 | No direct weight — see §2, this is what triggers steal inference instead |

A shot difficulty (Easy/Normal/Hard) doesn't change its pressure weight — only the *outcome*
(goal / on target / off target) does. Difficulty affects the Easy/Normal/Hard breakdown
stats and the icon shown, not the index.

## 2. Inferred steals — why the Action Button needs special handling

The Action Button and the Control Center control only ever report "possession changed" — a
neutral event that covers both a genuine steal and a mundane ball-out. Neither of those
should be indistinguishable from a full ±5 interception in the index, but a ball going out
for a throw-in obviously isn't a steal.

`PressureEngine.inferredSteals(in:stealWindowSeconds:)` resolves the ambiguity after the
fact: if the new possessor's **next pass** arrives within the steal window of the
possession-change tap, it's scored as a steal (±5, applied at the moment of the original
tap). If nothing follows quickly enough — a ball-out typically leaves a ~3 second gap before
the restart pass — it's scored as nothing, which is correct: a throw-in isn't pressure
either way.

The search, per pass:
1. Walk backwards through the match's passes/possession-changes in time order.
2. If a same-team pass is found first, keep walking (it's just this team continuing to
   hold the ball — not what we're looking for).
3. If a possession-change *to this team* is found within the window, claim it as a steal
   and stop. Each possession-change can only be claimed once.
4. If anything else is found first (a possession change to the *other* team, an explicit
   interception, or a ball-out), stop without claiming — someone else's turnover happened
   in between, so this pass isn't continuing the change being tested.

Explicit interception taps (`weIntercepted`/`theyIntercepted`) already carry the ±5 weight
directly in §1 and are never re-inferred.

**The steal window is versioned**, via `MatchRulesVersion` on the match (`MatchModels.swift`):

| Rules version | Window |
|---|---|
| 1, 2 | 2 seconds |
| 3+ | 1 second |

A match keeps being scored against whichever window was live when it was recorded — the
window shortening for new matches must never reclassify a steal (or non-steal) an old match
already locked in. This also drives the intercept button's on-screen countdown in
`MatchViewModel.interceptWindowSeconds` (see `LIVE_SCREEN_PRINCIPLES.md` §1), so what the
button promises always matches what the index actually scores.

## 3. Time decay — why it's "momentum," not a running total

`PressureEngine.value(at:events:)` computes the index at any instant by summing every event
up to that point, each faded by how long ago it happened:

```
fade = 1.0 - (age / lookbackSeconds) * 0.6
value += event.delta * fade
```

- `lookbackSeconds` = 120. Anything older than 2 minutes contributes **nothing** —
  it's dropped from the sum entirely, not just faded to near-zero.
- At age 0 (just happened), `fade` = 1.0 — full weight.
- At age 120s (the cutoff), `fade` = 0.4 — an event fades to 40% of its original weight
  right before it drops out, it never abruptly disappears at full strength.

This is why a goal from 15 minutes ago doesn't still dominate the current reading, and why
the index can swing back toward neutral during a quiet patch even with the scoreline
unchanged — it's answering "who's threatening right now," not "who's done more overall."

## 4. Two different views of the same events

The engine produces the index two different ways depending on where it's shown, and they
are **not** the same calculation:

- **Full chart (Summary tab)** — `PressureEngine.chartPoints(for:)` samples the decayed
  `value(at:events:)` every 15 seconds (`sampleStepSeconds`) across the whole match, plus
  the exact start and end. Each point is a full recompute from event 0, so it reflects
  everything that's happened, decayed.
- **Live mini chart (Live tab)** — `PressureEngine.recentPressureBuckets(for:)` instead
  buckets the last 45 seconds (`liveActivityBucketCount` × `liveActivityBucketSeconds`)
  into 1-second slots and sums the **raw, undecayed** deltas that fall in each bucket. It's
  a bar-per-second of recent activity, not a running score — there is no fade applied here,
  and nothing before the 45s window is represented at all.

Don't expect the live mini chart's shape to match a 45-second slice of the full chart; they
answer different questions ("what just happened" vs. "how does the whole match read").

## 5. Worked example

Home wins a corner at 10:00, nothing comes of it; away scores from an easy chance at 10:20.

- `10:00` → Corner won by home: **+1.5**
- `10:20` → Away goal (easy difficulty, outcome doesn't care about difficulty): **-8**

At `10:20`, `value(at: 620, events: ...)`: the corner is 20s old, `fade = 1 - (20/120)*0.6 ≈
0.90`, contributing `+1.35`. The goal is age 0, contributing the full `-8`. Index ≈ **-6.65**
— away is sharply ahead in the reading despite home having "won" the more recent-ish
situation, because a goal outweighs a corner by more than 5×.

## Related, but not pressure

These live in `PressureEngine.swift` / share its event definitions, but are separate
numbers from the index above:

- **Possession %** (`possessionPercentages`) — built from possession *spells* (contiguous
  stretches between recorded turnovers).

  The first spell starts at 0:00, before anything has been tapped, so it needs a team to
  begin with. That seed is **derived from the first recorded event**
  (`PressureEngine.openingPossession(for:)`), not stored: a pass means the possessor was
  carrying on, so it's whoever gained it; anything else — interception, ball-out,
  possession flip, goal restart — is the moment they *lost* it, so it's the other side.
  It used to read `MatchState.kickoffPossession`, which was wrong, because that field is
  rewritten on every pause and therefore names whoever held the ball at the final whistle
  once a match is saved (the field is now called `currentPossession`, which is what it
  actually holds). See `SUMMARY_CHANGELOG.md`, 2026-09-20, for the measured effect — the
  old seed disagreed with the events in 20 of 33 real matches but moved the displayed
  percentage in only one, because the first tap nearly always lands within a second or two
  of kick-off.

  Two kinds of gap are excluded from both sides' clocks via `idlePossessionSeconds`:
  - Quiet gaps of 25s+ between any tap or shot (`possessionIdleGapSeconds`) — subs,
    injuries, water breaks.
  - **Any** gap after a ball-out (`homeBallOut`/`awayBallOut`) up to the next recorded pass,
    however short — the ball is dead from the moment it goes out until the restart pass, so
    even a normal ~3s throw-in isn't credited to either side, not just ball-outs that happen
    to sit idle for 25s+.

  Both kinds of gap are excluded even while still in progress — if the most recent mark is a
  ball-out, or the most recent mark is 25s+ in the past with nothing since, everything from
  right after that mark up to now is excluded too, not just gaps that have already been
  closed off by a later mark. This matters for viewing Summary mid-match, and for a match
  that ends during a stoppage.

  **This does not touch the pressure index above in any way.** The index has no concept of
  an "idle gap" or a "dead ball" at all — nothing detects a stoppage, nothing pauses or
  resets decay. Events on either side of a gap just keep aging and fading exactly as §3
  describes; both exclusion rules above exist solely for the possession-% calculation, not
  for anything in `events(from:)` or `value(at:)`.
- **Shots on target / Easy Chances Taken / Shots blocked / Saves** (`comparisonStats`) —
  raw counts and rates, not decayed or weighted. Worth knowing: an unscored corner never
  counts as a shot attempt at all (`countsAsShot`) — only a *scored* corner does, since a
  corner is a delivery, not an attempt on goal. "Shots blocked" means defender foot blocks
  specifically (`difficulty == .hard && outcome == .onTarget`); keeper saves are counted
  separately in "Saves" and explicitly exclude blocks, so the two bars never double-count
  the same shot.
