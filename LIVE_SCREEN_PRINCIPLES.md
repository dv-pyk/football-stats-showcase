# Live screen design principles

The Live tab (`LiveMatchView.swift`) is the only screen touched *during* a match. Everything
else in the app is reviewed calmly, after the fact, sitting down. This screen is used
standing on a sideline, glancing down for under a second at a time, often one-handed, while
the actual thing being recorded (the match) keeps moving. That constraint is the reason for
every rule below — it is not a general app style guide, it's specifically about the
recording surface.

Reflects the shipped state of the screen as of app 1.4 (build 6). Sections marked
**Confirmed** are settled decisions the code already follows.

## 1. Who this screen is designed for

The user is not reading this screen, they're glancing at it. Most information has to land
peripherally, from shape and colour and position, before it lands from text. Anything that
requires reading a label to be used correctly under pressure is a design failure for this
screen specifically (it's fine on Summary/History, which are read sitting down).

Consequences:
- Colour and icon shape carry meaning; text is a confirmation, not the primary signal.
- Position must stay fixed match-to-match. Muscle memory ("goal button is bottom-left of the
  Hard row") is the actual UI; nothing should reflow based on state in a way that moves a
  button the user is about to tap.
- Taps must be forgiving — big targets, tolerant of a rushed or off-centre tap — because the
  user's eyes are on the pitch, not the phone.
- Time-limited affordances need a literal, glanceable indicator, not just a fading colour.
  The intercept window originally signalled its countdown with an opacity fade alone; that
  didn't read as "quantity remaining" at a glance, so a depleting bar was added alongside it
  (`DiagonalPassSection.interceptCountdownBar`, `LiveMatchView.swift:226-242`). Prefer a
  bar/meter over colour alone any time this screen needs to show a shrinking time budget.

## 2. Two-handed grip: what each thumb is for

The assumed grip while recording: **left hand carries the phone's weight, left thumb rests
on the physical Action Button; right hand comes up from underneath the left hand, right
thumb taps the screen.** The pass/possession button specifically is the right-thumb target —
it's the highest-frequency screen tap (§5) and the one most worth optimising for a thumb
reaching in from the bottom, not held out at arm's length from a one-handed grip.

This is already partly reflected in the app, not just a layout idea: `Shared/MatchIntents.swift`
defines `RecordPossessionChangeIntent` and `RecordBallOutIntent` as `openAppWhenRun = false`
App Intents — exactly the shape of action that can be bound to the Action Button (via
Shortcuts) and fired by the left thumb without looking at the screen or touching glass at
all. That's not incidental: those two are also the two actions on this screen that are safe
to fire coarsely. A misfire just means an extra possession flip or ball-out, both of which
are cheap to undo and don't touch the scoreline — unlike Goal, which must never be reachable
by an imprecise, no-look thumb press.

**Design rule this implies:** anything wired to the Action Button must stay in that "cheap to
misfire, cheap to undo" category. Don't extend Action Button coverage to shot outcomes or
anything score-affecting — the physical button trades precision for speed, and score-affecting
taps need the opposite trade.

**Confirmed:** the on-screen possession/pass panel's current position and hit target are
tuned correctly for a right thumb reaching in from underneath the left hand. Keep the panel
where it is — this is settled, not an open question.

## 3. Colour language: green vs red, home vs away — with one deliberate exception

The baseline rule, everywhere in the app including this screen: **green = us (home), red =
them (away)** — score digits (`LiveMatchView.swift:48,55`), the possession chart, the share
card, and the ball tint in the neon icon set (`NeonKit.swift:8-9`,
`NeonIconPalette.green` / `.red`). Any icon that includes a ball — a shot icon, a set-piece
tile — recolours that ball to green or red to match whoever currently has possession,
never anything else.

**Confirmed exception:** the possession/pass panel deliberately uses **orange**, not red,
for the away team (`MatchViewModel.possessionPanelDisplay()` / `passButtonDisplay()`,
`MatchViewModel.swift:351,371`). This is a choice, not drift — red read as too aggressive/
"angry" for a colour that sits on screen continuously for the away team's entire spell of
possession, rather than flashing briefly to confirm one event. The general principle this
sets: **team-identity red is for momentary confirmations (an icon that appears after one
tap and is gone), not for an ambient colour field the user stares at for a sustained
stretch of the match.** If a future element needs to show "away" as a background wash or
anything held on screen for more than a couple of seconds, default to orange there too
rather than red.

Green/red/orange team-identity colour should never be reused to mean something else on this
screen (e.g. it shouldn't also mean "good outcome") — the outcome columns below are a
deliberately separate palette, even though Goal happens to reuse green (see §4).

## 4. Columns: same three outcomes, same order, every row

Every shot-difficulty row has the same three buttons in the same left-to-right order —
**Goal → Blocked/Saved → Miss** (`LiveMatchView.swift:147-159`) — and each column keeps a
fixed colour regardless of difficulty row:

| Column | Colour | Why this colour |
|---|---|---|
| Goal | Green | Unambiguous good outcome. Same green as "us" is intentional overload here since a goal is only ever good from the perspective of whoever's shooting — the possessing team is what the whole row is scoped to. |
| Saved / Blocked (defends/saves) | Yellow | Contested, not resolved — ball was live and on target, keeper or defender had to act. Yellow reads as warm/"attention" rather than threatening, which is the deliberate reason it beats orange here: orange skews toward alarm, and a save/block isn't a bad thing for the team defending it — it's genuinely neutral, could've gone either way. |
| Miss | Grey / white | Play is over, nothing at stake. Deliberately the least visually active colour so the eye isn't drawn to it — misses are the highest-frequency outcome and shouldn't compete for attention with goals or saves. |

Fixing the column order and colour across every row means the user learns "left = goal"
**once**, not four times. This is the single most load-bearing consistency rule on the
screen — never let a row reorder or recolour these three.

**Note:** `BACKBURNER.md`'s icon-direction notes describe saves/blocks as orange — that was
the plan before this review. Yellow is the confirmed call for this column going forward
(warmer, less threatening than orange); treat the orange reference in `BACKBURNER.md` as
superseded by this doc, not the other way round.

The set-piece row (see below) is a deliberate structural exception: it has three *kinds*
(Corner / Penalty / Free Kick), not three *outcomes*, so it doesn't use this palette at all.
That's fine precisely because it doesn't try to imitate the outcome columns — a set-piece
tile recoloured green/yellow/grey would look like it belonged to the outcome system and
mislead on first glance.

## 5. Rows: one idea each, ordered by how the game actually asks for them

Current top-to-bottom order: **Normal chance → possession/pass → Easy → Hard → Set pieces**
(`LiveMatchView.swift:7-25`).

- **Normal chance** sits directly under the score and pressure chart, alone, in its own
  card, above everything else. It's both the default/no-information-needed case — "a shot
  happened, nothing about it was notable" — and, in practice, the row tapped more often than
  Easy, Hard, or set pieces combined. It gets the prime real estate nearest the score the
  eye is already on **and** is the tallest shot row on the screen, at 80pt (see §6) —
  prominence and frequency agree with each other here, deliberately.
- **Possession / pass** sits in the middle because it's the highest-frequency tap of the
  whole match (every pass, every turnover) and needs to be reachable without the hand
  travelling far from either shot section.
- **Easy** and **Hard** are graded departures from Normal — each carries a coloured top
  banner (`ShotOutcomeIcons.swift:55-61`: green for Easy, burnt-orange/red for Hard) so a
  glance at the row's silhouette alone (before reading which row it is) tells you which
  side of "normal" you're on. They sit below the fold because they require a judgement call
  the Normal row doesn't — the user has decided this shot deserves a qualifier before
  reaching for it. Being reached-for less often than Normal, they stay close to the current
  64pt baseline rather than growing with it.
- **Set pieces** sits last because it's a different kind of event (a setup tap, not a shot
  outcome) — see `BACKBURNER.md` for the capture-only rules-v2 rationale, and for the
  pressure weights (penalty/corner/free-kick) a set-piece setup now carries in its own
  right. Its row started at 104pt, the tallest thing on the screen, which was more vertical
  space than a row this infrequent should claim — see §6 for how it came down to 80pt.

## 6. Vertical sizing — each row's height tracks how often it's used

| Row | Height | Why |
|---|---|---|
| Pressure reasoning lane | **38pt**, fixed, always present (`PressureLaneView.swift`) | Narrates what the index just decided ("Steal — Z won it back") instead of leaving the number to speak for itself — see the new section below. Fixed height and never hidden, per §1: an appearing/disappearing lane would move every row below it. |
| Normal (Goal/Saved/Miss) | **80pt** (`LiveMatchView.swift:104`) | The most frequently tapped shot row — the tallest, easiest target on the screen is the one used most, not the smallest. Visibly bigger than the Easy/Hard rows below it, not just equal to them. |
| Easy / Hard (Goal/Saved/Miss) | 64pt (`LiveMatchView.swift:147`) | Room for the difficulty banner strip plus the icon underneath without either getting cramped — reached for less often than Normal, so this is the baseline rather than growing with it. |
| Set pieces (Corner/Penalty/Free Kick) | **80pt**, down from 104pt (`LiveMatchView.swift:131`) | 104pt was sized to keep the neon artwork (wall of players, net mesh) legible, but claimed more vertical space than a row this infrequent should. Brought down **without touching the artwork's own render size**: the caption moved from a stacked label below the artwork into an overlay pill on top of it (`SetPieceArtIcon`, using `NeonCaption`), so the tile is shorter only because it no longer reserves a separate row for the label — the art itself renders at the same scale it always did. |
| Set-piece weight hint row | **18pt** (`LiveMatchView.swift`, above `setPieceRow`) | "Tap when won — shot is a separate tap" plus the pen/corner/FK weights, read live from `PressureWeight` so it can't drift. Answers a question that used to have no on-screen answer at all: when should this actually be tapped. |
| Possession/pass panel | 196pt | Confirmed correct for the two-handed grip (§2) — untouched. |

Rule of thumb: **row height tracks tap frequency first, then whatever legibility floor the
row's icon needs second.** A row that's reached for constantly (Normal) earns the tallest
target; a row that's reached for rarely (set pieces) gets trimmed back toward the shared
64pt baseline — but by reclaiming layout overhead (a label's own row, in this case), not by
scaling the artwork down, which is what makes fine line art muddy.

A related trap worth naming: `ShotOutcomeButton` scales its icon with `scaleEffect(minHeight
/ 64, anchor: .center)`, which assumed the icon always laid out at a fixed 64pt internally.
That assumption silently broke the first time a row height went *above* 64pt (Normal, here)
— the icon's own `minHeight: 64` let the taller outer frame stretch its layout before the
scale was applied, double-scaling it and clipping the caption. Fixed by pinning the icon to
an exact 64pt frame before scaling (`LiveMatchView.swift:320-326`). Any future row height
change that crosses the 64pt line should re-check this same class of bug.

## 7. Icon system

Documented fully in `FootballStats/Views/NeonKit.swift` and the `neon-icon-style` memory;
summarised here as it applies to row/column identity specifically:

- Figures are anatomical (tapered limb outlines, a head that reads separately from the
  torso) rather than stick figures or emoji — confirmed preference, see
  `NeonKit.swift:1-5`. This was picked specifically because stick figures/emoji looked
  amateurish next to the app icon and share card, which already used this language — icon
  style is a cross-screen consistency question, not a per-icon one.
- The ball always carries the *current possessor's* colour (green/red), never the outcome
  colour — colour-by-team and colour-by-outcome are kept on physically separate elements
  (ball vs. column tint) so they never fight for the same pixels.
- Set pieces are deliberately **white chrome**, not team-coloured artwork, with only the
  ball tinted by possession (`neon-icon-style` memory, last line). This keeps the set-piece
  row visually distinct from the outcome rows at a glance, reinforcing the point in §4 that
  it isn't part of the Goal/Saved/Miss system. Both possession colours now ship as real
  artwork — `SetPieceCornerAway`/`PenaltyAway`/`FreeKickAway` were generated by swapping the
  R/G channels on the green originals (`SetPieceArtIcons.swift:47-50`), which recolours the
  ball to red while leaving the white/black line art untouched, since it's pure grayscale.
- Two-pass glow ("bloom": tight core + wide halo, `NeonKit.swift:16-22`) is what makes a
  thin stroke read as neon instead of as a flat coloured line — apply it to every new icon
  in this family, not just the ones that feel like they need emphasis, or new icons will
  look flatter than the existing set side-by-side.
- **Exception:** `ShotTileIcon` (`ShotTileIcons.swift`), the Normal/Easy/Hard tile artwork,
  draws in dark ink rather than neon glow — it sits on the column's own coloured fill
  (green/yellow/grey), and a two-pass bloom needs a dark ground to read as neon at all. Same
  figure vocabulary (`NeonKeeperFigure`, `NeonWallFigure`, `NeonAnatomy.limb`), different
  render treatment for a light background. Set pieces stay glow-on-black as before — this
  exception is specific to the shot columns, which are the only icons on this screen that
  sit on a bright fill.

## 8. The reasoning lane — states and colour

`PressureLaneView`, directly under the pressure mini chart (§6), narrates what
`PressureEngine.explained` just decided — implements the BACKBURNER entry *"In-app feedback
for what the scoring logic is doing"*. Per §1, the sentence is confirmation; the dot and
border colour carry the state at a glance:

| State | Colour | Meaning |
|---|---|---|
| Steal window open | Blue, depleting bar | Same window, same clock as the Pass button's own countdown (`MatchViewModel.interceptStrength`) — deliberately never two different countdowns for one thing. |
| Resolved as a steal | Blue, ~1.2s then fades to grey | |
| Resolved as nothing (ball out) | Grey | |
| Set piece tapped | Yellow (`ShotTilePalette.onTarget`) | Same yellow as the Saved/Blocked column (§4) — a set piece is contested/neutral in the same way. |
| Shot or goal tapped | Green (home) / **red** (away) | Momentary confirmation, so red is correct here per §3's own exception — this is exactly the "flashes briefly" case, not an ambient field, so it doesn't take the possession panel's orange. |
| Quiet 25s+ | Grey; pressure mini chart dims to 35% opacity | Reuses the existing `possessionIdleGapSeconds` definition (`PressureEngine.idleGapSeconds`) — explicitly does not mean the index has stopped decaying, only that possession % isn't counting the gap (`PRESSURE_INDEX.md`). |
| Otherwise | Grey, same text, no bar | The lane always shows the most recent turning-point event; only the colour/bar say how fresh it is. |

Tapping the lane opens `PressureLedgerView`, the full last-two-minutes history with an undo
on every row — this is where an over-eager inferred steal (see the round-trip case in
`BACKBURNER.md`) gets explained rather than silently trusted.

## 9. App icon consistency

The home-screen app icon was deliberately drawn "from the share card visual language" (see
commit `170761f`), i.e. it's downstream of the same neon palette and figure style as the
in-app icons, not a separate piece of branding. Any time the in-app icon set changes in a
way that shifts the palette or line language (new accent colour, different bloom radius,
etc.), the app icon should be revisited for consistency — it's the user's first impression
of "this is the same visual system," before they've even opened the app.

## 9b. Irreversible controls: End is a hold, not a tap

**Confirmed.** End & Save used to be a bare single-tap `Button` sitting in the same `HStack`
as Pause/Start, with only the score and clock between them — two adjacent targets, one
reversible and one not. On 2026-09-19 a half-time reach for Start landed on End & Save
instead, and that match was recorded as two separate 30:00 and 28:15
files. Nothing in the app can splice those back together; it took a hand-merge of the
backup JSON.

The control is now `HoldToEndButton` (`LiveMatchView.swift`): a one-second press-and-hold
with a fill that sweeps the capsule as the hold progresses. Three rules it follows, each
one a consequence of a principle above rather than a free choice:

- **The label never changes.** It reads "Hold to End" permanently, not "End & Save" that
  swaps to a nudge after a stray tap. Per §1, a label that changes width moves the score and
  clock next to it — the screen may not reflow under the user's thumb, and a self-describing
  label teaches the gesture once rather than at the moment they need it.
- **The time budget is a literal fill, not a colour fade.** Same call §1 makes for the
  intercept countdown bar: a shrinking time budget on this screen gets a bar or meter, never
  colour alone.
- **The fill is neutral grey.** Green/red/orange are team identity (§3) and green/yellow/grey
  are shot outcomes (§4); the app's accent happens to be the same green as "us", so a tinted
  fill would have read as a team colour sweeping the header. Motion carries the meaning here,
  so the fill doesn't need a colour of its own.

Feedback is graded by how the press ended, so an abort and a mistake don't look alike:

| Gesture | What happens |
|---|---|
| Tap, or any release under 0.25s | Nothing is saved; the button shakes once. Someone who meant to tap and expected it to work gets told the gesture exists. |
| Release between 0.25s and 1s | Nothing is saved; the fill drains back. A deliberate abort doesn't deserve an error-flavoured shake — the drain is answer enough. |
| Held past 1s | Match ends and saves, with a success haptic distinct from the `record()` tap haptic. |

One second was picked as the shortest hold no reflex tap survives, while still not feeling
like a penalty at the final whistle. VoiceOver activation ends the match outright rather
than being asked to synthesise a hold — an assistive activation is deliberate by
construction, so the guard has nothing to protect against there.

**The general rule this sets:** anything on this screen that can't be undone gets a hold, not
a tap. Undo-last-shot and undo-last-pass exist precisely because ordinary recording taps are
cheap to get wrong (§2); ending the recording is the one action with no undo behind it, so it
is the one action that should cost a deliberate second.

## 10. Decisions confirmed here

1. Orange for the away side of the possession/pass panel is deliberate — red is reserved
   for momentary confirmations, orange for anything ambient/sustained (§3).
2. The possession/pass panel's position and hit target are correctly tuned for the
   two-handed Action Button grip — leave it alone (§2).
3. Saved/Blocked stays yellow, not orange — warmer and less threatening than orange for a
   contested-but-neutral outcome. `LiveMatchView.swift`'s current `.yellow` button tint is
   already correct; `BACKBURNER.md`'s older "orange" icon-direction note is superseded (§4).
4. Normal grew to 80pt, set pieces came down to 80pt, Easy/Hard held at 64pt — done, see §6
   for exactly how (and the scaling bug it exposed).
5. Away-possession set-piece artwork ships for all three kinds — done, see §7.
6. The reasoning lane ships as a fixed 38pt row, always present, reusing the shot-column
   yellow and the shot/goal green-or-red (not the possession panel's orange) — done, see §8.
7. End & Save is a one-second press-and-hold with a neutral fill, labelled "Hold to End" at
   all times — done, see §9b. Anything else on this screen that can't be undone should follow
   it.
