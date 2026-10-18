# Backburner

Ideas worth keeping, not scheduled. Capture here so they don't get lost; implement only when
we deliberately pick one up.

**Convention:** active/idea-only entries stay up top, newest addition at the bottom of that
group. Once an entry ships (or its open questions all get resolved), move the whole entry,
content intact, down into **Shipped / resolved** at the very bottom of the file — that section
is a decision-record archive, not somewhere to keep re-reading while scanning for what's next.

---

## Achievement engine

**Status:** idea only, not designed yet. Shape decided; detection logic and catalogue not
written. Moved to top of the queue 2026-08-23 — next thing to pick up.

A running achievement system that starts at zero for each match and unlocks achievements as
the match progresses (e.g. tied to `StandoutMomentEngine`'s categories — see the shipped
"Standout-moment call-outs" entry in Shipped/resolved — or other patterns — first goal inside
5 minutes, a clean first half, a comeback from 2 down). Decided:

- **Per-match only** — no season-long/cross-match persistence. Each match starts at zero.
- **Catalogue is fixed and hand-authored** ahead of time, not generated or inferred from
  whatever detectors happen to exist — a known, curated list of achievements to check for.
- **Displayed as a dedicated badges row** on the share graphic (not folded into the
  observations text), alongside the existing stats.

### Open

- The actual catalogue — what's the full hand-authored list of achievements?
- `StandoutMomentEngine.swift` already has working, format-aware detection for keeper
  performances, goal bursts, pass streaks, and comebacks — this could reuse that engine
  directly (turning a "moment" into a named "achievement") rather than duplicating detection
  logic, now that it exists and is validated against real matches (most recently against the
  4 matches recorded 2026-08-16 through 2026-08-23 — every one produced at least one
  standout moment, nothing false-positived, thresholds held).

**Captured:** 2026-08-10.

---

## Ball half tracking + pressure index rework

**Status:** idea only, not designed yet.

Track which half of the pitch the ball is currently in, as a new signal alongside
possession. The pressure index (`PRESSURE_INDEX.md`) currently has no sense of *where* the
ball is — a string of home passes pinned in home's own half reads identically to the same
passes deep in the opposition's half, even though the second is obviously more threatening.

Rough shape of the idea, not decided:

- Some kind of tap to record "ball crossed into [team]'s half," similar in spirit to a
  possession-change tap.
- The pressure index would need a way to weight events differently depending on which half
  they happened in — e.g. a pass kept deep in the opponent's half is more threatening than
  the same pass in your own defensive third.
- Interacts with the existing versioning approach (`MatchRulesVersion`): this is a genuine
  scoring-rule change, so old matches without half data would need to keep being read under
  the current (half-blind) formula.
- **Compass-based idea, not evaluated yet:** instead of a manual tap, use the phone's
  compass/heading during Live mode — assume whoever's holding the phone stands roughly at
  mid-court/touchline and always points the phone toward wherever the ball currently is, so
  the heading itself implies which half (and roughly how far forward) play is in, without a
  separate tap at all. Just a raw idea from the owner (2026-08-23) — unevaluated for accuracy
  (would depend heavily on the phone actually being pointed consistently, pitch orientation
  being known/set up front, and how noisy a phone compass really is in practice), not
  designed, not compared against the tap-based approach above.

### Open

- What's the actual input — a single tap per half-change, a three-way (defensive/middle/
  attacking) control, something else, or the compass idea above instead of a tap at all?
- Exact weighting: how much should being in the attacking half amplify a pass/shot's
  pressure contribution?
- Does this replace or sit alongside the existing possession-spell tracking?

**Captured:** 2026-08-02 · compass idea added 2026-08-23.

---

## Team colour accessibility rework

**Status:** idea only, not designed yet.

Rethink team-identity colour away from green/red — reads badly for colour-blind users
(red/green confusion is the most common form). Candidate: **blue vs orange** for team
identity (score digits, possession panel, ball tint in icons, share card), keeping
**green/yellow/grey** for the Live screen's three outcome columns (Goal/Saved/Miss) — which
is already the current, unrelated colour axis documented in `LIVE_SCREEN_PRINCIPLES.md` §4
and wouldn't need to change.

This would touch a lot of surface area: `LiveMatchView.swift` score digits and possession
panel, the neon icon ball tint (`NeonIconPalette.green`/`.red`), the share card / possession
chart, and `MatchViewModel.possessionPanelDisplay()`'s existing orange-for-away exception —
which would need rethinking once orange *is* a team colour rather than a deliberate
deviation from one. `LIVE_SCREEN_PRINCIPLES.md` §3 documents the current green/red(/orange)
scheme in full; this would supersede most of it, not just patch it.

### Open

- Full replacement of green/red everywhere, or just the places most likely to be
  misread (score, possession panel)?
- Once away = orange is the *normal* team colour rather than a deliberate ambient
  exception, does the momentary-vs-ambient distinction in §3 still need to exist at all?
- Goal-outcome green (column colour) and home-team blue will both be on screen at once on
  the Normal/Easy/Hard rows — confirm they're visually distinct enough at a glance.

**Captured:** 2026-08-02.

---

## Show set-piece conversion, subtly

**Status:** idea only, not designed yet.

A set-piece capture (Corner/Penalty/Free Kick) and the shot that eventually converts it are
two unlinked taps today — nothing in the data or the UI shows that a given Normal/Easy/Hard
attempt *was* the conversion of an earlier set piece. The existing "Conversion window
length after a set-piece setup?" open question (see the shipped set-pieces entry in
**Shipped / resolved** below) is about the data side of this; this idea is about the
**visual** side once/if that exists — some minimal, non-shouty way to show "this shot came
from that set piece" without adding a new column or a busy new element to a screen that's
already tuned for one-glance reads (see `LIVE_SCREEN_PRINCIPLES.md` §1).

### Open

- Depends on the conversion-window question being answered first — can't visually link two
  events that aren't formally linked in the data.
- What does "subtle" look like here — a small badge on the shot icon, a line in the
  observations, something in the set-piece tile itself after it's tapped?

**Captured:** 2026-08-02.

---

## Pressure chart colour hides swing magnitude

**Status:** idea only, not designed yet.

`PossessionChartView` currently colours the pressure line by the sign of the value at each
point alone — green above zero, red below (`segment.isPositive ? .green : .red`). That loses
information: a swing of +10 immediately followed by -10 nets out to roughly even, but if the
value stayed just barely on the positive side throughout, the whole stretch renders solid
green — reading as sustained home dominance when the truth is a sharp swing that mostly
cancelled out. The colour only encodes which side of zero the index is on, not how volatile
it's been getting there.

### Open

- Encode magnitude somehow — line thickness or colour intensity scaling with `|value|`,
  rather than a flat colour once past zero either way?
- A separate swing/volatility indicator alongside the line, rather than trying to cram it
  into the same colour channel?
- Does this want to change the full chart (`PressureEngine.chartPoints`), the live mini
  chart (`recentPressureBuckets`), or both — they're different calculations (see
  `PRESSURE_INDEX.md` §4) and may want different treatments.

**Captured:** 2026-08-02.

---

## "What's different this week" note on the Summary screen

**Status:** idea only, not designed yet.

A short, in-app blurb on the Summary tab telling coaches/parents what changed since they
last used the app — a renamed bar, a new stat, a different pressure calculation — rather
than them just noticing a number looks different and wondering why. `SUMMARY_CHANGELOG.md`
already tracks exactly this, dated and versioned; this idea is surfacing some subset of it
in the app itself instead of leaving it as a file only developers read.

### Open

- Surfaced how — a dismissible banner, a "what's new" sheet behind a button, something in
  the History tab instead of Summary?
- Shown once per version, or always available to re-open?
- Needs a way to know which version the *reader* last saw vs. what's in the changelog now —
  some persisted "last seen version" state.

**Captured:** 2026-08-02.

---

## Distribute via TestFlight

**Status:** idea only, not set up.

Move off the "run from Xcode, reinstall every 7 days" cycle (`README.md` Option A) and onto
TestFlight instead — installs last far longer without a cable, updates push without the owner
plugging the phone into the Mac, and it's the only way for anyone other than the owner (an
assistant coach, another parent) to run the app without their own Xcode setup.

Requires enrolling in the paid Apple Developer Program ($99/year — `README.md` already
notes this as the blocker for Option B) — everything else is process, not code: archive the
app in Xcode, upload to App Store Connect, wait for the build to finish processing, then
add testers.

### Open

- Internal testing (up to 100 testers, no App Review, available almost immediately) is
  probably the right starting point rather than external testing (needs a beta App Review
  pass, but scales to thousands) — confirm that's actually enough for who'd use this.
- `CURRENT_PROJECT_VERSION` already gets bumped by hand for every release (see
  `CLAUDE.md`'s version-bump rule) — TestFlight requires a strictly increasing build number
  per upload too, so this should slot into the existing habit rather than need a new one.
- Does the widget extension (`FootballStatsWidgetExtension`) need any separate
  provisioning/signing attention for TestFlight specifically, or does it just ride along
  with the main app archive?

**Captured:** 2026-08-02.

---

## Goal Map follow-ups

**Status:** built 2026-10-18 (Goal Map section inside the Pressure Index card + placement sheet
— see `SUMMARY_CHANGELOG.md`), **not yet confirmed on-device**. Everything below was left out
on purpose to keep the first version to what was asked for.

Decided in the first version:

- **One entry point:** tap a goal's ⚽ on the Pressure Index chart. No capture on the Live
  tab — that screen is for the match, not for plotting (`LIVE_SCREEN_PRINCIPLES.md`).
- **Goals only.** `placement` lives on `ShotEvent` so it *could* hold any attempt, but only
  goals can be placed and drawn.
- **All three details are required to save** (origin, goal-mouth point, flight), so a placed
  goal is always drawable. Flight defaults to Straight.
- **Stored normalised, in the scorer's attacking frame** — never metres, since pitch sizes
  vary. Pitches drawn are a standard 105×68 (outdoor) or 32×20 (futsal — a bar shorter at each
  end than regulation, because the courts played on are short), not the real ground.
- **Camera angle is a half-turn, not a mirror.** Flip rotates the map 180° (camera on the
  other touchline); a left-right mirror would swap every shooter's left and right. It is a
  per-match setting (`MatchState.goalMapFlipped`), not a global one.
- **Surface is grass or indoor court — never blue** (the navy first tried read as a
  screenshot of someone else's court). Per match (`goalMapSurface`), defaulting by format.
- **The map travels with the Pressure Index card's image** (copy and WhatsApp), but only when
  at least one goal is placed, so unplaced matches share the image they always did.
- **Away goals are placeable too** (red); only home goals can carry a name, because only the
  home team has a roster.

### Open

- Plot non-goal attempts (saves, misses) as a shot map? Data model already allows it; the
  open question is whether sideline taps can cope with placing every attempt.
- A Live-tab shortcut straight after a goal, if tapping the ball later proves too easy to forget.
- The basketball reference's **Replay** (animate arcs in match order) and **Half court**
  (zoom to one end) — not built.
- Outdoor games with half times: the map always draws home attacking one way, so a second-half
  goal at the other end is drawn as if attacked the same way. Fine for a flat picture; a
  per-half flip would need half-time to be recorded.
- Flight shapes are three fixed curves scaled by distance; a keeper-facing "dip" or swerve
  would need a fourth option.

**Captured:** 2026-10-18.

---

## Shipped / resolved

Archive of entries whose status resolved to shipped, or whose open questions all got
answered. Kept for the decision record; not something to scan when picking up next work.

---

### Library of player faces next to goals

**Status:** Shipped in app 1.6 (build 8). A per-team roster (photo, name, jersey number),
set up from New Match, credits goals and big saves to a player — live on the Live tab via an
immediate popup ("Do Later" to skip), or any time afterward from Summary. Implementation
plan: see the `misty-greeting-turtle` plan referenced in this session's history for the
design/build breakdown (roster model, crop UI, the two Live-tab triggers, Summary catch-up).

What actually shipped diverged from the original decided shape in a few ways, worked out
during implementation and review:

- **Faces don't pair onto the goal ball on the pressure line.** The original plan put the
  credited face right on the chart marker; in practice two circles on one marker didn't
  read well, and it broke the ball staying a single centred circle where the goal actually
  happened. Faces instead show in **one row along the bottom of the chart** — a slot per
  home goal and per away big save, empty-dashed-ring until credited, a circular cropped face
  once it is.
- **Tapping moved from the ball to that bottom row.** The ball is purely visual again;
  the bottom-row slot is the tap target, for both goals and big saves (see next point).
- **Big-save catch-up crediting was added beyond the original scope** — originally only
  the Live tab's immediate popup could credit a save; Summary's bottom row now lets you
  credit or reassign a big save after the fact too, same as goals.
- **A credited big save's tick line glows down to the axis line**, so the eye follows the
  attempt mark straight through to the face and the time it happened — a late addition once
  the bottom row existed and the tick strip needed a visual link down to it.
- **Faces show in the WhatsApp share image too** — the export path renders its own copy of
  the chart, which almost got left disconnected from the roster (as originally scoped, faces
  were on-screen-only); wired up before shipping once it came up in review.
- **Both original open questions resolved by behaviour, not by decision:** a team with no
  roster set up shows goals/saves exactly as before (roster presence gates everything, checked
  at each trigger site); retroactive crediting has no expiry — Summary's bottom row is always
  tappable, live match or old History entry alike.
- **Follow-up, resolved:** rosters (including avatar photos) are now part of the same
  backup file as match history — `MatchHistoryBackup`'s export/import bundles avatar bytes
  as base64 alongside the roster metadata, so a device restore/reinstall no longer loses
  roster faces. Backups written before this shipped are a bare array of matches with no
  roster wrapper at all; import still reads those fine, just with no rosters to merge in.
  Importing a roster never overwrites a player that already exists locally (matched by id)
  — it only fills in what's missing, so re-importing an old backup can't clobber edits made
  since.

**Captured:** 2026-08-02 · refined 2026-08-16 · shipped 2026-08-16 · roster backup added 2026-08-16.

---

### Standout-moment call-outs on the share graphic

**Status:** Shipped in app 1.8 (build 10), as a Summary-tab card (not the share **image** —
that's still deferred, see below). Detects a standout keeper performance, a goal burst, a
long consecutive-pass streak, or a comeback. Implementation: `StandoutMomentEngine.swift`,
mirroring `MatchObservationEngine`'s existing pattern.

Validated before writing any code — every match in a real backup export was run through the
candidate rules first (an in-chat analysis, then a draft artifact for review), which is how
the thresholds below were picked and how the comeback category got added.

What changed from the original idea, and why:

- **Comeback added as a fourth category**, not in the original three candidates — only 2 of
  20 real matches had a team overcome a 2+ goal deficit to finish level or ahead, genuinely
  rare, and the analysis surfaced it unprompted.
- **Format-aware thresholds, not one flat rule** — a late but material correction: the owner's
  four teams split evenly into Outdoor and Futsal, and Futsal scores roughly 3x faster in
  practice. A flat threshold either never fired for Outdoor or fired on nearly every Futsal
  match. This needed a new `GameFormat` field on `MatchState`, set at New Match (pre-selected
  per known team via `PresetHomeTeam.defaultGameFormat(for:)`, always overridable) — and,
  for the 20 already-recorded matches with no format on file, the same team-name mapping
  infers it correctly on load rather than falling back to a flat default.
- **Both teams get checked, not just "ours."** Unlike `MatchObservationEngine` (coaching
  feedback framed around "our" team), a standout moment from the opposition — their keeper's
  big night, their comeback — is still part of the match's story, so `StandoutMomentEngine`
  has no `ourTeam` framing at all.
- **The original open questions resolved by the validation pass, not by decision:**
  thresholds came from the actual spread of values within each format across real matches
  (aiming for roughly the rarest 15-20%), not a guessed fixed number or a per-match-relative
  scheme; rendering landed on a Summary-tab card (mirroring the existing Observations card)
  plus the WhatsApp share **text**, not annotations on the share image itself — that's an
  explicit, deliberate deferral, not an oversight.
- **Overlap with the achievement-engine idea is now concrete, not speculative** — that entry
  (still active, up top) can reuse this engine's detectors directly once picked up.

**Captured:** 2026-08-10 · refined and shipped 2026-08-16.

---

### Set pieces + defended attempts (rules v2)

**Status:** Shipped in app 1.2 (build 4). Kept here as the decision record; icon **colours**
below are superseded by `LIVE_SCREEN_PRINCIPLES.md` §4 — Saves/Blocks is **yellow**, not
orange (warmer, less threatening than orange for a contested-but-neutral outcome).

#### Capture

Replace the **Corners** shot-difficulty row with three **setup** taps:

- Setup Corner
- Setup Penalty
- Opportunistic Free Kick

A later Easy/Normal/Hard attempt shortly after is how conversion is inferred. No “Corner Goal” difficulty.

#### Block / save meanings (on-target only for the middle column)

| Control | Meaning |
|---------|---------|
| Hard Blocked | Defender foot block — **always on target**, **never a keeper event**. If it wasn’t on target, record Hard Miss instead. |
| Normal “save” | Keeper prevented an on-target attempt (standing, both hands). Consequences of missing it = goal. |
| Easy “big save” | Same as normal save, but standout keeper action (in air, one-hand flick). |

Grey / team-colour / glow on the Saves bar still means: goals conceded / saves / big saves. Defender blocks leave that bar and feed a new **Defended** bar (both teams; all on-target).

#### Summary

- **Corners** bar removed (set pieces are capture-only until a conversion row exists).
- **Shots blocked** bar (shipped label; `defended(by:)` internally): hard blocks only (attributed to the defending team).
- **Saves** excludes defender blocks — keeper faced = goals conceded + normal/easy on-target stops.

#### Pressure

No special hard-block weight: hard + on-target already uses on-target (+3), which fits an on-target attempt that was denied. Set-piece setup taps generate pressure the moment they're won, scaled by danger: Penalty +6, Corner/Free Kick +1.5 each (the old flat corner bonus) — independent of whatever shot outcome follows.

#### Icon direction (preview: `.render-preview/shot-icons-preview-home.png` / `-away.png`)

Grid: rows **Normal → Easy → Hard → Set pieces**; columns **Goal | Blocked | Miss**.

- Possession recolour: our ball → green accents; theirs → red (Hard Goal ball stays classic black/white for contrast against scored chrome). Superseded if the team-colour accessibility rework below goes ahead.
- Column themes: Goals = green/red posts; Saves/Blocks = ~~orange~~ **yellow** (see status note above); Misses = grey.
- Easy Goal: angled 3D, net pushed; Easy Miss: ground roll wide; Big Save: keeper facing shot, ball on target between posts.
- Hard Goal: B&W ball in top corner; defenders in front; keeper diving but not reaching.
- Hard Block: green/red attacker foot + orange defender foot intercepting.
- Set pieces: white chrome; possession-coloured ball; free-kick wall = hollow outlines only.
- Individual refs: `icon-big-save.png`, `icon-hard-goal.png`, `icon-hard-block.png`, `setpiece-freekick-home.png`.

#### Open

- Conversion window length after a set-piece setup? (No formal window is tracked today — a
  later shot only reads as "conversion" by proximity in the UI, not by any recorded link.)

**Captured:** 2026-07-26 · refined 2026-07-31 (setup buttons, block meanings, icon themes) ·
marked shipped and reconciled with `LIVE_SCREEN_PRINCIPLES.md` 2026-08-02.

---

### In-app feedback for what the scoring logic is doing

**Status:** Shipped in app 1.4 (build 6) — `PressureLaneView` (the reasoning lane under the
pressure mini chart) plus `PressureLedgerView` (the full last-two-minutes ledger, opened by
tapping the lane). Implementation plan: `HANDOFF-live-screen.md`. Kept here as the decision
record; the two open questions below are answered, not still open.

Several parts of the app quietly infer things behind the scenes (steals, pressure, set-piece
conversions), and right now none of that reasoning is visible on screen — the person tapping
just sees the raw controls and has to trust the numbers work out. A few concrete cases that
prompted this:

- **Inferred-steal pressure can look wrong in the moment.** Example: team X has the ball,
  team Y intercepts, the ball goes straight back out and returns to X shortly after. Under
  today's logic (`PRESSURE_INDEX.md` §2), Y's tap can still score as an inferred steal (±5)
  even though X clearly kept the run of play — because the inference only looks at whether
  *a pass from Y* follows within the steal window, not whether the ball round-trips straight
  back to X. Whether that's a genuine scoring gap or just a case the user needs to understand
  is itself an open question — but either way, nothing on screen today explains *why* the
  index moved the way it did.
- **No on-screen sign that a quiet stretch is being treated specially.** Worth checking
  against current behaviour before designing anything: today the 25s+ idle-gap logic
  (`possessionIdleGapSeconds`) only excludes a gap from the **possession %** calculation —
  it does not pause or blank pressure decay at all (`PRESSURE_INDEX.md`, "Related, but not
  pressure"). If pressure ever gains its own notion of a stoppage (see the ball-half-tracking
  idea above, or a dedicated stoppage concept), or even under today's possession-only
  behaviour, there's no indicator telling the user "we've stopped counting this toward
  possession" — it just silently doesn't move.
- **Set-piece tap timing is ambiguous.** It's not obvious from the Live screen whether a
  Corner/Penalty/Free Kick tap should happen the moment it's *won*, or when the resulting
  *shot* is taken (it's the former — see the shipped set-pieces entry above — but nothing
  on screen says so). More generally, the person tapping has no visibility into what's being
  assembled behind that tap (pressure credit, a conversion window once that exists, etc.).

The common thread: the app makes several inferences from simple taps, and could use some
lightweight, in-the-moment explanation of what it thinks just happened, rather than leaving
the user to reverse-engineer it from the numbers afterward.

#### Resolved

- **Surfaced as the reasoning lane** (`PressureLaneView`, `LIVE_SCREEN_PRINCIPLES.md` §8),
  fixed 38pt, always present, tap to open the ledger — not a tooltip or a separate help sheet.
- **The round-trip steal case is explained, not re-scored.** `inferredSteals`/`events(from:)`
  are unchanged — `PressureEngine.explained` narrates the *same* result instead
  (`"Y passed 1s after the turnover, inside the 1s window"`), and the ledger's undo lets you
  remove that specific tap if a given round-trip genuinely wasn't a steal. Whether the scoring
  itself should change remains open, but is now a separate decision from "does the user know
  what happened" — they no longer have to be the same conversation.
- **The idle gap is surfaced, not made pressure-aware.** The lane's "Quiet 0:31 — not counting
  toward possession" state reads `PressureEngine.idleGapSeconds`, which mirrors the existing
  possession-only definition exactly — pressure decay still runs through a quiet stretch
  unchanged, and the lane says as much ("Pressure keeps fading" sub-line). A real stoppage
  concept that pauses decay is still a separate, undecided idea (see ball-half tracking above).
- Set-piece tap timing is answered on-screen by the weight-hint row shipped alongside this
  ("Tap when won — shot is a separate tap", `LIVE_SCREEN_PRINCIPLES.md` §6).

**Captured:** 2026-08-10 · shipped 2026-08-11.
