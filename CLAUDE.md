# Football Stats

A SwiftUI iOS app for tracking U13 football matches from the sideline. See `README.md` for
what it tracks, how to run it, and the project layout.

## Read these before working on the relevant area

- `LIVE_SCREEN_PRINCIPLES.md` — design principles for the Live tab (`LiveMatchView.swift`),
  the only screen used *during* a match: colour language, row/column ordering, vertical
  sizing rules, and the icon system. Read before changing that screen's layout, colours, or
  icon sizing — several things that look like inconsistencies (e.g. the possession panel's
  orange instead of red) are documented, deliberate exceptions, not bugs.
- `BACKBURNER.md` — deferred feature plans and decisions already made (set-piece capture
  rules, pressure weights, icon direction). Check here before assuming a gap is
  unintentional or before re-deciding something already settled.
- `PRESSURE_INDEX.md` — the pressure index's actual logic (event weights, inferred-steal
  window, time decay, live-bucket vs. full-chart calculations). Read before touching
  `PressureEngine.swift`, especially before adding half-time awareness — it documents the
  pre-rework baseline to diff against.
- `SUMMARY_CHANGELOG.md` — dated log of every change to what the Summary tab shows or how
  it's calculated (renamed bars, new/removed stats, pressure-formula changes). **Append an
  entry here any time you rename a stat label, add/remove a Summary bar, or change how the
  pressure index (or any comparison stat) is calculated** — this is what "what's different
  this week" would eventually be sourced from, so a missed entry is a real gap, not just
  bookkeeping.

Keep these files updated when a decision in them changes — don't let them go stale.

## Workflow rules

- **Never `git push` or open a PR for a UI/UX change right after it builds.** A clean
  build only proves it compiles, not that it looks/works right. Stop after describing the
  change and how to try it on-device, and wait for the owner to confirm on their phone before
  pushing — even in background/worktree sessions where autonomous shipping is otherwise
  expected.
- **Icon style:** use the neon-wireframe look with anatomically drawn figures (tapered
  limbs with real thickness, a head that reads separately from the torso), not thin-stroke
  stick figures or emoji. Build figures from `NeonAnatomy.limb` in
  `FootballStats/Views/NeonKit.swift`; keep arms visibly thinner than legs. Set pieces stay
  white chrome with only the ball carrying possession colour.
- **Whenever you bump `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION`, check `README.md`
  first.** At minimum confirm "What it tracks," "How to use during a match," and the
  project structure tree still match reality — README has gone stale behind real feature
  work before (see the 1.3 doc-catch-up commit). If the version bump includes any
  Summary-visible change, also add a `SUMMARY_CHANGELOG.md` entry (see above).
- **Every build installed on the owner's phone must be Release, not Debug** — this is their
  real match-day app, not a dev sandbox. `run-on-device.sh` defaults to Release (pass
  `--debug` only if you genuinely need a debugger/assertions attached), and the
  `FootballStats.xcscheme` Run action defaults to Release too. Don't reintroduce a Debug
  default in either place.
- **Installs expire after 7 days — tell the owner the expiry date every time.** The app is
  signed with a free Personal Team, so each `run-on-device.sh` install gets a
  fresh provisioning profile that stops working a week later, and the app then won't open
  until it's reinstalled. Because this is their real match-day app, an expired profile on game
  day means they have no app. If they report the app won't open, suspect an expired profile
  before anything else.
- **A launch denial straight after an install is usually not a signing bug.** Right after
  Xcode regenerates a profile, `devicectl device process launch` can fail with "invalid code
  signature, inadequate entitlements or its profile has not been explicitly trusted" while
  the *install itself has already succeeded*. Check whether the app is on the device, then
  re-run only the launch command a few seconds later. Seen 2026-09-18 with Xcode 27.0 and
  iOS 26.6.2 on the owner's iPhone.
