<div align="center">

<img src="docs/images/icon.png" alt="DayPlan app icon" width="128">

# DayPlan

**A macOS todo app built on one idea: A daily plan for your todos.**

<a href="#install"><img src="https://img.shields.io/badge/macOS-15%2B-555555?style=flat-square&logo=apple&logoColor=white" alt="macOS 15+"></a>
<a href="https://swift.org"><img src="https://img.shields.io/badge/Swift-6-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift 6"></a>
<a href="Package.swift"><img src="https://img.shields.io/badge/dependencies-none-2EA043?style=flat-square&logo=swift&logoColor=white" alt="No dependencies"></a>
<a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-0969DA?style=flat-square&logo=opensourceinitiative&logoColor=white" alt="MIT license"></a>

<img src="docs/images/hero.png" alt="DayPlan main window" width="880">

<br><br>

[Overview](#overview) · [Why I built it](#why-i-built-it) · [Install](#install) · [Languages](#languages) · [How it works](#how-it-works) · [Your data](#your-data) · [License](#license)

</div>

## Overview

- **A day you decide on:** Todos due today turn up on their own, but you can also pin   something into today or push it out again.
- **A Today pane with a day arc:** Fills as you finish things, so where you are is one glance.
- **A menu bar popover:** Showing what's still open. Same process, easy overview anytime.
- **Lists with colours, priorities, due dates and notes:** Add custom lists (e.g. per project), organize with colors, leave notes, priorities, due dates and more.
- **Local and yours:** One SwiftData store on your disk, no account, no network, no telemetry.
- **No third-party dependencies:** Plain SwiftUI and SwiftData on macOS.

## Why I built it

I used Microsoft Teams Planner at work for a long time and at some point it frustrated me more than it gave me any benefit. Besides critical bugs I encountered (todo items dissapeared/were not saved, app crashes with data loss), I also felt like the concept was not thought through. I don't need much to track my todos, but e.g. a seperation by project or topic was missing from the Planner. A simple way to get started in the morning by checking my most relevant todos for the day and adding them to the today-view was a annoying chore. All todos were inside a single list which was quite large and I had to add the project name to the todo item, making titles uneccessary long.

<div align="center">
  <img src="docs/images/menubar.png" alt="Menu bar popover" width="300">
  <br><br>
  <img src="docs/images/detail.png" alt="Detail pane" width="880">
</div>

## Install

Needs macOS 15 or newer and a Swift 6 toolchain (Xcode 16).

```bash
git clone https://github.com/benedom/DayPlan.git
cd DayPlan
./build.sh
open DayPlan.app
```

`build.sh` does a release build, renders the icon, assembles the bundle and signs it ad-hoc.

### Gatekeeper

Ad-hoc signing is fine when you build it yourself. A copy that came through a download will be
quarantined and won't open. Right-click it and choose Open, or clear the flag:

```bash
xattr -dr com.apple.quarantine DayPlan.app
```

## Languages

The interface is English only. There are no localization files yet, so every string in the UI is
hardcoded English.

Adding a language means pulling the UI strings into a String Catalog. Roughly 120 of them, mostly
in `RootView.swift`, `TodoListPane.swift`, `TodoDetailPane.swift` and `MenuBarView.swift`. Pull
requests welcome.

## How it works

**The daily plan.** `Todo` carries a `pinnedDay` and an `excludedDay`. Either one overrides the
due-date rule, for that day only. The whole thing is about fifteen lines in
[`Models.swift`](Sources/DayPlan/Models.swift), under `isInDailyPlan(on:includeOverdue:)`.

**Backups you can read without the app.** Plain versioned JSON, and importing either merges or
replaces ([`Backup.swift`](Sources/DayPlan/Backup.swift)).

**One set of animation curves.** Every timing in both UIs comes from
[`Motion.swift`](Sources/DayPlan/Motion.swift), so a row in the menu bar moves like the same row
in the main window.

**One process.** `WindowGroup` and `MenuBarExtra` live in the same `App` and share a single
`ModelContainer` ([`DayPlanApp.swift`](Sources/DayPlan/DayPlanApp.swift)). No sync code, because
there's nothing to sync.

## Your data

It's all in `~/Library/Application Support/DayPlan/DayPlan.store`. No network, no telemetry, no
account. Anything recovered from a broken store ends up in a `Quarantined/` folder next to it.

Two environment variables move that out of the way, which is how the screenshots above are made
without touching a real store:

```bash
DAYPLAN_STORE_DIR=/tmp/dayplan-demo \
DAYPLAN_SEED_DEMO=1 \
  ./DayPlan.app/Contents/MacOS/DayPlan
```

`DAYPLAN_STORE_DIR` picks a different store location. `DAYPLAN_SEED_DEMO=1` fills it with a sample
day, but only when that store is completely empty, so it can never overwrite anything you care
about.

## License

MIT, see [LICENSE](LICENSE).
