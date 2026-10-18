# Live screen refresh — implementation handoff

Design source: `Live Screen.dc.html` in the design project (turn 3 = final icons, turn 2 = ledger,
turn 1 = the lane in context). Recreation `1a` is the shipped screen, measured from a device
screenshot, so any offset below can be diffed against it.

Read first: `LIVE_SCREEN_PRINCIPLES.md` (§1 glanceability, §3 colour, §4 columns, §6 sizing),
`PRESSURE_INDEX.md` (§1 weights, §2 inferred steals, §3 decay), and the BACKBURNER entry
*"In-app feedback for what the scoring logic is doing"* — this work implements that entry.

Nothing here changes a pressure **weight** or the possession-% calculation. It changes what the
screen *says* about them, plus the shot artwork.

---

## 1. Shot tile artwork — `ShotTileIcons.swift` (written, drop in as-is)

New file, no existing type touched: `FootballStats/Views/ShotTileIcons.swift`.
Defines `ShotTileKind` (`goal` / `onTarget` / `miss`), `ShotTilePalette`, `ShotTileIcon`,
and `NeonBlockerFigure`. Reuses `NeonKeeperFigure`, `NeonDivingKeeperFigure`, `NeonWallFigure`,
`NeonAnatomy.limb` and `NeonCaption` from `NeonKit.swift`.

**The system.** Each row owns a stage, each column owns an event:

| | Goal | On target (denied) | Miss |
|---|---|---|---|
| **Normal** | goal in perspective, ball in the net, net pushed out | keeper standing, planted, ball stopped in front | goal in perspective, dashed path past the post |
| **Easy** | close-up of the net, big ball, net pushed out | keeper at full stretch, fingertips on it | net close-up at the far side, ball rolling wide |
| **Hard** | wall of three, ball in the top corner | defender's leg out, ball squashing on the boot | wall of three, ball off past the post |

Middle column is deliberately one idea in three grades — *an on-target attempt that didn't go in* —
which is what the column has always meant from the shooting team's point of view. Captions:
`Saved` / `Big Save` / `Blocked`.

**Call-site change in `LiveMatchView.shotRow(for:)`.** `ShotTileIcon` draws its own
column-coloured capsule, so the `.borderedProminent` + `.tint(color)` wrapper goes away —
that wrapper is also what forced the old `scaleEffect(minHeight / 64)` hack, so this removes the
double-scaling trap named in `LIVE_SCREEN_PRINCIPLES.md` §6:

```swift
private func shotRow(for difficulty: ShotDifficulty, buttonHeight: CGFloat = 64) -> some View {
    HStack(spacing: 8) {
        shotButton(.goal, difficulty, buttonHeight) { viewModel.addShot(team: viewModel.possessingTeam, difficulty: difficulty, outcome: .goal) }
        shotButton(.onTarget, difficulty, buttonHeight) { viewModel.addShot(team: viewModel.possessingTeam, difficulty: difficulty, outcome: .onTarget) }
        shotButton(.miss, difficulty, buttonHeight) { viewModel.addShot(team: viewModel.possessingTeam, difficulty: difficulty, outcome: .notOnTarget) }
    }
}

private func shotButton(_ kind: ShotTileKind, _ difficulty: ShotDifficulty, _ height: CGFloat, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        ShotTileIcon(kind: kind, difficulty: difficulty, possession: viewModel.possessingTeam)
            .frame(maxWidth: .infinity, minHeight: height)
    }
    .buttonStyle(.plain)
}
```

Keep the existing heights (Normal 80, Easy/Hard 64–78) — the tile scales to whatever it's given
and never restyles the row. Set-piece tiles are untouched: still `SetPieceArtIcon` + the shipped
asset-catalog artwork.

`IconGalleryView` should gain a 3×3 `ShotTileIcon` grid in both possession colours; that's the
fastest way to eyeball the set without starting a match.

---

## 2. `PressureEngine` explains itself

New value type alongside the existing `(seconds, delta)` events. The index maths does not change —
this is a parallel, human-readable record of the same walk.

```swift
extension PressureEngine {
    enum ExplainedKind {
        case pass(count: Int)          // rolled up per spell, see §4
        case steal(inferred: Bool)
        case turnoverNoSteal(gap: TimeInterval)
        case shot(ShotDifficulty, ShotOutcome)
        case setPiece(SetPieceKind)
        case goal
    }

    struct Explained: Identifiable {
        let id = UUID()
        let seconds: TimeInterval      // match clock, for the row's timestamp
        let team: TeamSide
        let kind: ExplainedKind
        let delta: Double              // signed, exactly as fed to value(at:)
        let reason: String?            // nil where the weight is self-evident (a pass)
    }

    /// Same single walk as `events(from:)`, emitting an `Explained` per event.
    /// Cheap enough to recompute on demand — do NOT cache it on the match.
    static func explained(for match: MatchState, endingAt: TimeInterval) -> [Explained]
}
```

`reason` strings, written once here so the lane and the sheet can't drift apart:

| Case | Reason |
|---|---|
| inferred steal | `"<Team> passed 0.6s after the turnover, inside the <window>s window"` — real measured gap and the match's own `MatchRulesVersion` window |
| turnover, no steal | `"No pass for 2.4s — read as ball out, not a steal"` |
| explicit intercept | `"Tapped as an interception"` |
| set piece | `"Credited when you tapped it, not when it's taken"` |
| penalty | `"Penalties convert far more often than a corner"` |
| goal / shot | fade state: `"Faded to 82% by now"`, or `"Drops out of the index at 25:12"` when within 20s of the 120s cutoff |

Two behaviours the engine must expose for the lane (§3):

- `pendingSteal(at:)` → the open possession-change whose steal window hasn't closed yet, with its
  remaining fraction. Same clock as `MatchViewModel.interceptStrength(at:)` so the lane's bar and
  the Pass button's bar deplete together — they're the same window, and showing two different
  countdowns would be worse than showing none.
- `idleGapSeconds(at:)` → seconds since the last tap of any kind, so the lane can say when the
  25s+ possession-% exclusion (`possessionIdleGapSeconds`) has kicked in.

**Do not** make the idle gap touch pressure. `PRESSURE_INDEX.md` is explicit that the index has no
stoppage concept; the lane's job here is to *say* that, not to change it.

---

## 3. The reasoning lane

New `PressureLaneView`, placed in `LiveMatchView` directly under `PressureMiniChartView`,
above the Normal card. **Fixed height, always present** — an appearing/disappearing lane would
move every button below it, which §1 forbids.

Geometry (design offsets from a 440×956 device, `1b`):

| Element | y | height |
| --- | --- | --- |
| pressure mini chart | 124 | 39 |
| **reasoning lane** | 167 | **38** |
| Normal card | 213 | 119 |
| possession card | 340 | 242 |
| Easy/Hard/set-piece card | 590 | 280 |

8pt between every card; the slack for the lane comes out of the old `Spacer` gaps, so nothing else
shrinks. Lane style: `#1C1C1E` fill, 11pt corner radius, 1pt border that carries the state colour.

Contents, left to right: state dot → one line of text (+ a depleting bar when a window is open) →
provisional delta → hairline → `INDEX` label with the current value.

| State | Border / dot | Line | Right |
|---|---|---|---|
| steal window open | `.blue` | `"Opp won it — watching for a steal"` + bar depleting over the rules-version window | `−5?` then the live index |
| resolved as a steal | `.blue`, 1.2s then fades to idle | `"Steal — Z won it back"` | `+5` |
| resolved as nothing | grey | `"Ball out — no steal credited"` | `0` |
| set piece tapped | column yellow | `"Corner won — +1.5 now, shot counts separately"` | `+1.5` |
| shot/goal tapped | green or red | `"Goal — Opp"` / `"On target — Z"` | `−8` / `+3` |
| quiet 25s+ | grey, mini chart to 35% opacity | `"Quiet 0:31 — not counting toward possession"`, sub-line `"Pressure keeps fading"` | live index |
| otherwise | grey | last event, no bar | live index |

Text is 13pt semibold; the whole lane is one tap target that opens the sheet (§4). The dot and the
border colour carry the state — the sentence is confirmation, per §1.

**Haptics:** none for lane state changes. `HapticFeedback` fires on taps the user made; a haptic for
something the *app* inferred would read as a mis-tap.

---

## 4. Ledger sheet — `PressureLedgerView`

Presented as a sheet from the lane, `.presentationDetents([.large])`. Design: `2b`.

Header `"What the index is doing"`, sub-line `"Last 2 minutes — everything older has dropped out."`
(true by `PRESSURE_INDEX.md` §3: 120s lookback, then dropped entirely).

**Passes never get their own row.** A real two-minute window is ~60 taps and almost all of them are
passes; unrolled it's unreadable and unscrollable mid-match. Roll contiguous same-team passes within
one spell into a single row: a bar per pass, `"7 passes — Z · 15s spell"`, summed delta `+7`,
rendered at lower contrast (`#242426` vs `#2C2C2E`) so the turning points stay dominant. That takes
the window to 6–9 rows. A `Turning points / Every tap (63)` segmented control exposes the raw stream
for anyone who wants it; default is `Turning points`.

Row: `time · title + reason · signed delta`, delta in the same green/red/grey the columns use.
Footer card pins `"Index now"` + value + `"Events fade to 40% over 2 minutes, then drop out"`.

**Undo from a row.** Tapping a pass group expands it to its individual taps first, so one tap can
never remove seven events; tapping a single row removes that event and recomputes. Route it through
the same `applyMatchChange` path as `undoLastShot` / `undoLastPass` so the App Group store and the
widget stay in sync — do not mutate `match` directly from the sheet.

---

## 5. Weights on the screen, and the set-piece hint

Small dim captions (11pt, `#48484A`) on the trailing edge of each section's existing footer row, so
they cost no vertical space:

- Normal card, opposite *Undo last shot*: `on target +3 · goal +8`
- Possession card, opposite *Undo last pass*: `pass +1 · steal +5`
- Above the set-piece row, a dedicated 18pt row: `Tap when won — shot is a separate tap`
  (leading, `#8E8E93`) and `pen +6 · corner/FK +1.5` (trailing, `#48484A`)

Single-line, `lineLimit(1)`, `fixedSize` — in the web mock these wrapped to two lines and pushed the
set-piece row under the tab bar. Keep them nowrap and the Easy/Hard card grows by exactly 18pt.

Numbers must be read from `PressureWeight`, not typed as literals, or they'll drift the first time a
weight changes.

---

## 6. Docs to update when this lands

Per `CLAUDE.md`:

- `LIVE_SCREEN_PRINCIPLES.md` — §6 sizing table gains the lane (38pt) and the set-piece hint row
  (18pt); §7 gains a note that the shot columns are now drawn by `ShotTileIcon` in dark ink on the
  column fill, and why (bloom needs a dark ground); a new section for the lane's state/colour rules.
- `BACKBURNER.md` — mark *"In-app feedback for what the scoring logic is doing"* shipped, and record
  the two open questions it answers by explaining rather than changing: the round-trip steal case is
  **explained, not re-scored**, and the idle gap is **surfaced, not made pressure-aware**.
- `SUMMARY_CHANGELOG.md` — only if the ledger's undo path changes any Summary number. Adding the
  lane alone doesn't.
- `README.md` — the Live tab bullet list gains the lane and the ledger.

## 7. Suggested order

1. `ShotTileIcons.swift` + the `shotRow` swap + gallery grid — self-contained, verifiable on device
   in one run, no engine changes.
2. Weights captions + set-piece hint — pure layout, +18pt.
3. `PressureEngine.explained` + `pendingSteal` / `idleGapSeconds` — no UI, unit-testable against the
   worked example in `PRESSURE_INDEX.md` §5.
4. `PressureLaneView`.
5. `PressureLedgerView`, undo last.

Per `CLAUDE.md`, stop after each step and check it on the phone before pushing — a clean build
proves it compiles, not that it reads at a glance from the sideline.
