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
2. In `run.ahk`, `#Include` the source file under test (after `stubs.ahk`) and the new test file, and add the test class to the `Yunit.Use(CIReporter).Test(...)` call.
3. If the source file references symbols at load time that you don't want to pull in, add no-op stubs to `stubs.ahk`.

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
