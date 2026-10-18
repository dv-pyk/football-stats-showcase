# Summary screen changelog

A dated log of every change to what the **Summary tab** shows or how it's calculated:
renamed bars, new or removed stats, pressure-formula changes. Two reasons this exists:

1. **Development memory.** "Why does this week's pressure reading look different from last
   week's for a similar match" should have an answer in this file, not just in git blame.
2. **A future "what's different this week" note, maybe.** If a short changelog blurb ever
   ships directly on the Summary screen for coaches/parents, this is the source material —
   nothing in-app surfaces this yet, so treat that as an open idea, not a shipped feature.

Newest first. Entries are grouped by the app version they shipped in where that's known;
earlier same-day work before versioning existed is grouped by date instead. Backfilled from
git history on 2026-08-02 — dates/details for entries before that are as accurate as the
commit log allows, not from memory.

---

## Unreleased — 2026-09-20

- **Possession % — opening spell no longer seeded from the wrong team.** The stretch from
  0:00 to the first recorded tap used to be credited to `MatchState.kickoffPossession`,
  which sounds right and wasn't: `pauseClock()` overwrites that field on every pause so the
  Live screen can restore possession on resume, so on a *saved* match it holds whoever had
  the ball at the **final whistle**. The opening seconds were therefore credited to the
  team that finished with it. It's now derived from the first recorded event instead
  (`PressureEngine.openingPossession(for:)`) — the passer for a pass, the other side for a
  turnover — so it reads back what actually happened. The field itself was renamed to
  `currentPossession`, which is what it has always held; backups written under the old key
  still decode.

  **Effect on existing matches, measured across all 33 in the 2026-09-19 backup:** the old
  seed disagreed with the events in **20 of 33** matches, but because the first tap almost
  always lands within a second or two of kick-off, the displayed percentage moves in only
  **one** — a futsal match (30:45, kick-off 2026-07-25, first tap at
  0:05), home possession **52% → 53%**. Every other match reads exactly as before.

  Not given a `MatchRulesVersion` bump: possession % isn't the pressure index, the old
  value wasn't a deliberate interpretation to preserve, and a one-point shift on one match
  isn't worth freezing a known-wrong seed into old data.

## App 1.9 (build 11) — 2026-08-22

- **Player initials fallback:** a roster player gets an optional "Initials" field
  (auto-derived from their name if left blank, e.g. "Jack Smith" → "JS"). Anywhere a
  player's face would show — the pressure chart's credited row, the WhatsApp share image —
  a player with no photo now shows their initials in a team-tinted badge instead of looking
  identical to an uncredited slot. Purely presentational, like the rest of player credit
  (see App 1.6 below) — no scoring or possession calculation involved.

## App 1.8 (build 10) — 2026-08-16

- **New "Standout Moments" card**, shown between the shot breakdown and Observations:
  detects a standout keeper performance (big-save count or a busy clean sheet), a goal
  burst, a long consecutive-pass streak, or a comeback, and states it in a sentence per
  moment. A quiet match shows no card at all — this isn't trying to find a story in every
  game. Thresholds differ by the match's new **game format** (Outdoor vs Futsal, set at New
  Match — pre-selected per known team, always changeable): Futsal runs shorter and scores
  roughly 3x faster in practice, so a flat threshold either never fired for Outdoor or fired
  on nearly every Futsal match. Thresholds were picked from the actual spread of values
  within each format across every match recorded so far, not guessed. See
  `StandoutMomentEngine.swift` and `BACKBURNER.md`'s "Standout-moment call-outs" entry
  (moved to Shipped/resolved) for the full validation history.
- **WhatsApp share text** now leads with standout moments (when there are any), before
  Observations. The share **image** itself is unchanged — moments are text-only for now.
- Matches recorded before this shipped don't carry a game format on file; it's inferred from
  the home team name on load (`PresetHomeTeam.defaultGameFormat(for:)`), so standout
  detection on old matches uses the correct thresholds automatically, not a flat default.

## App 1.6 (build 8) — 2026-08-16

- **Player credit, shown on the pressure chart:** goals and big saves can now be credited to
  a roster player (set up per team from New Match). The pressure chart's goal ball stays a
  plain centred circle — credited faces show along one row at the bottom instead, one slot
  per home goal and one per away big save your keeper made, each a tappable empty ring until
  credited, a circular cropped face once it is. Tapping works from Summary any time (live
  match or a saved History match); the Live tab also pops the same picker immediately after
  a goal or a big save, with a "Do Later" option. A credited big save's tick line in the
  strip glows down to the axis line so it's easy to spot. Faces show in the WhatsApp share
  image too, not just on-screen. Doesn't touch the pressure index or possession %
  calculations — this is entirely presentational, layered on top of existing shot data
  (`ShotEvent.creditedPlayerID`). See `BACKBURNER.md`'s "Library of player faces next to
  goals" entry for the full design history.

## App 1.5 (build 7) — 2026-08-16

- **Possession % calculation fix:** a ball-out is a dead ball until the restart pass, so the
  gap between a `homeBallOut`/`awayBallOut` tap and the next recorded pass is now excluded
  from both sides' possession clocks, however short that gap is — previously only gaps of
  25s+ (the generic quiet-period threshold) were excluded, so a normal ~3s throw-in restart
  was silently credited to the receiving team. Also fixed: an in-progress quiet period or
  dead ball with no follow-up mark recorded yet (viewing Summary mid-match, or a match ending
  during a stoppage) now gets excluded live/retroactively too, instead of only being excluded
  once a later mark happened to close the gap. See `PRESSURE_INDEX.md`'s "Related, but not
  pressure" section. Does not touch the pressure index itself — decay/weights are unchanged.

## App 1.3 (build 5) — 2026-08-02

- **Stat label rename:** "Big Chances Created" → **"Easy Chances Taken."** Same number
  (count of Easy-difficulty attempts) — the old label implied the team *created* the
  chances, when what's actually being counted is chances *taken* at Easy difficulty,
  regardless of who created them.
- **Stat label rename:** "Defended" → **"Shots blocked."** Same number (on-target Hard
  attempts, i.e. defender foot-blocks) — clearer about what's actually being counted.

## App 1.2 (build 4) — 2026-08-01

- **Pressure index — new contribution:** winning a set piece (Corner, Penalty, Free Kick)
  now adds pressure the instant it's won, independent of whatever shot follows it. Penalty
  +6, Corner/Free Kick +1.5 each. Before this, set-piece taps were capture-only and
  contributed nothing to the index.
- **Pressure index — steal window shortened:** the inferred-steal window dropped from 2s to
  1s for matches recorded from this version on. Matches recorded earlier keep being scored
  against the 2s window that was live when they happened — this is why two matches a week
  apart can score a similar-looking passage of play differently (see `PRESSURE_INDEX.md`
  §2 for the versioning mechanism).
- **New bar: "Defended"** (renamed to "Shots blocked" the next version, above) — counts
  on-target Hard attempts specifically. Introduced because Hard-difficulty on-target
  attempts stopped being counted as keeper saves this version (see next point).
- **Stat definition change: "Saves"** no longer includes defender blocks. An on-target Hard
  attempt is now scored as a defender's foot-block, not a keeper save — so "keeper faced"
  dropped to mean goals conceded + Normal/Easy on-target stops only. A given shot now
  appears in exactly one of Saves or Shots Blocked, never both.
- **Removed: "Corners" bar.** Corner is no longer a shot difficulty a player can tap
  (replaced by the Corner/Penalty/Free Kick set-piece capture taps on the Live tab), so
  there was nothing left for a dedicated Corners bar to count going forward. Old matches
  recorded before this version can still have corner-difficulty shots in their data and are
  still scored correctly (see the legacy `cornerBonus` handling in `PRESSURE_INDEX.md` §1) —
  they just don't get a bar of their own in the current UI.

## App 1.1 (build 3) — 2026-07-31

- Introduced match rules versioning (`MatchRulesVersion` on `MatchState`). No calculation
  changed in this release by itself — this is the infrastructure that made every versioned
  change listed above possible without silently reinterpreting matches recorded earlier.
  Matches saved before this version decode as rules v1.

## Share-card rework — 2026-07-26 (several same-day commits, pre-1.1)

- **Possession % change:** long quiet gaps (25s or more between any recorded tap or shot)
  are now excluded from both teams' possession clocks, so a water break, injury stoppage,
  substitution, or a slow throw-in/corner/penalty restart no longer gets silently credited
  to whoever happened to be "in possession" when the gap started. Possession % only —
  the pressure index has no idea a gap happened at all and isn't affected by this in any
  way (see `PRESSURE_INDEX.md`, "Related, but not pressure").
- **Bars merged:** the separate "Save Rate" row and a "big saves and total saves" row folded
  into one **"Saves"** bar — save rate leads the text, the bar itself shows shots faced
  (saves in team colour, goals conceded in grey), and big saves show as a glowing subset.
- **Stat label rename:** "Shots" → **"Attempts"** on the main comparison bar, paired with a
  new rule: an unscored corner counts as a delivery, not an attempt — only a *scored*
  corner counts as a shot on the Attempts bar (this rule is what `countsAsShot` in
  `PressureEngine.swift` still enforces today).
- **Layout:** Possession moved to lead the share card, ahead of the pressure chart, since
  score and possession are the two figures people read first. Card widened to 450pt so
  shared text isn't shrunk unreadably small in a chat. Away goal markers changed from amber
  to red.
- **Observations:** unscored corners excluded from the observation text's attempt counts,
  to stay consistent with what the image now shows.

## App 1.0 (build 2) — 2026-07-25 — first tracked release

Summary tab shipped with: goal timeline, a shots comparison chart, a save-rate stat, and
possession, alongside the WhatsApp share image and observations text. Nothing to diff
against before this — it's the baseline.
