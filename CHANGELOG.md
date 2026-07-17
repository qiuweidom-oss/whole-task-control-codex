# Changelog

## 2.1.1 - 2026-07-17

- Recognize managed markers with either LF or CRLF line endings in POSIX installers.
- Add a CRLF upgrade regression test to prevent duplicate global rule blocks.
- Shorten the native PowerShell test directory so path-safety checks do not reject the test harness itself.
- Require native PowerShell tests to emit their final success marker.
- Convert WSL paths before invoking Windows PowerShell from the POSIX test suite.
- Publish repository documentation explaining the problem, behavior, limits, installation, recovery, and safety boundaries.

## 2.1.0 - 2026-07-17

- Add UTF-8 BOM encoding for Windows PowerShell 5.1 compatibility.
- Add native PowerShell installation tests.
- Add portable SHA-256 test-tool detection.
- Add Windows path-length preflight checks.
- Limit recovery checks to state that exists and is relevant to the current task.
- Declare implicit invocation policy explicitly.

## 2.0.0 - 2026-07-17

- Replace always-on full-skill loading with a lightweight conditional trigger.
- Add staged installation, timestamped backups, rollback, uninstall, restore, dry-run, and same-name skill protection.
- Add Windows and POSIX installers.
