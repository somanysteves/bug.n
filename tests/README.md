# bug.n tests

Unit tests for bug.n, using [Yunit](https://github.com/Uberi/Yunit).

## Running

From the repo root:

```
test.bat
```

The batch file invokes `AutoHotkeyU64.exe` on `tests/run.ahk` and exits with the number of failed tests (0 on success). On first run after a fresh clone it will also initialize the Yunit submodule automatically; if you'd rather do that manually: `git submodule update --init --recursive`.

## Layout

```
tests/
  vendor/Yunit/     # Yunit as a git submodule (pinned commit — see .gitmodules)
  stubs.ahk         # no-op stubs for src/ symbols we don't exercise
  CIReporter.ahk    # Yunit output module; prints PASS/FAIL, tracks fail count
  test_Tiler.ahk    # tests for src/Tiler.ahk
  run.ahk           # runner — #Includes everything, invokes Yunit, exits with fail count
```

## Writing new tests

1. Create `tests/test_Foo.ahk` with a class whose methods are test cases (see `test_Tiler.ahk` for the pattern).
2. In `run.ahk`, `#Include` the new test file and add the test class to the `Yunit.Use(CIReporter).Test(...)` call. Source files are already all loaded.
3. If a new source file is added to `src/` and references a symbol defined only in `Main.ahk`, add a no-op stub for it to `stubs.ahk`.

## Runner structure: why `#Include` lives at the bottom

`run.ahk` puts its executable code (counter init, `Yunit.Use(...).Test(...)`, summary, `ExitApp`) at the top and every `#Include` directive at the bottom. This mirrors `src/Main.ahk` and is load-bearing: AHK v1's auto-execute section runs top-to-bottom until it hits a `Return`, `Exit`, or `ExitApp`. Library files like `Bar.ahk` contain top-level label blocks (e.g. `Bar_cmdGuiEnter: ... Return`) — if they're `#Include`'d *before* the test invocation, their first `Return` inlines into auto-execute and terminates it prematurely, so `Yunit.Use(...).Test(...)` never runs. Putting `#Include` after `ExitApp` parses the files (so functions/classes/labels are defined) without inlining their code into the auto-execute flow.

One consequence: any top-level initialization inside an included file (like `global FOO := 0`) also won't run. That's why `CIReporter.ahk` *defines* the reporter class but `run.ahk`'s auto-execute block initializes the counter globals explicitly.

## Updating or pinning Yunit

Yunit is tracked as a git submodule; the commit this repo pins is recorded in the main repo's tree, not a README. To move to a newer upstream commit:

```
git -C tests/vendor/Yunit fetch
git -C tests/vendor/Yunit checkout <new-commit-or-tag>
git add tests/vendor/Yunit
git commit -m "Bump Yunit to <new-commit-or-tag>"
```

## AHK v2 migration

When bug.n migrates to AutoHotkey v2, switch the submodule to Yunit's `v2` branch ([github.com/Uberi/Yunit/tree/v2](https://github.com/Uberi/Yunit/tree/v2)):

```
git -C tests/vendor/Yunit fetch origin v2
git -C tests/vendor/Yunit checkout origin/v2
git add tests/vendor/Yunit
```

The assertion API (`Yunit.Assert`) and test class structure are the same across branches — tests should need only syntactic updates matching the v2 language changes in the source under test.

## License note

Yunit is AGPL-3.0 (bug.n is GPL-3.0). Yunit is a test-only dependency and is not linked into `bugn.exe`, so the AGPL copyleft does not propagate to the shipped binary.
