# Upstream PR Review Log

Tracks our decisions on open PRs against `fuhsjr00/bug.n` as we evaluate them for our fork.

| Upstream PR | Title | Decision | Notes |
|---|---|---|---|
| [#277](https://github.com/fuhsjr00/bug.n/pull/277) | Color theme editor (alpha) | **Merged** | Pulled in via fork PR [#1](https://github.com/somanysteves/bug.n/pull/1). |
| [#278](https://github.com/fuhsjr00/bug.n/pull/278) | Bar toggle-able per monitor-view | **Merged** | Pulled in via fork PR [#2](https://github.com/somanysteves/bug.n/pull/2) from `Fuco1:feature/toggle-status-bar-per-view`. Known cost: switching to/from a view where the bar is hidden triggers a second `View_arrange` inside `Monitor_updateBar` (on top of the one already in `Monitor_activateView`). No overhead when `showBar` is consistent across views. |
| [#283](https://github.com/fuhsjr00/bug.n/pull/283) | Fix chrome browser freeze | **Skip** | Adds `WinActivate, ahk_class Progman` before every activation in `Window_activate()`, which is called on every focus change. Targeted at a specific Chrome/Win10-20H2 interaction from 2021; we haven't confirmed the issue still reproduces on current Chrome/Win11, so holding off for now. |

## Not yet reviewed

- [#59](https://github.com/fuhsjr00/bug.n/pull/59) — Add `Monitor_greedyView()` (has conflicts)

## Out of scope

- [#306](https://github.com/fuhsjr00/bug.n/pull/306) — Fix window gap after resolution change (authored by us)
