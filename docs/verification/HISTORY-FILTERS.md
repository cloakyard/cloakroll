# Backup History filters — 5 October 2026

A native toolbar menu filters saved history by iPhone and result (All Results, Completed,
Unfinished). The filled filter symbol and a quiet list-header caption show the active
scope. Clear Filters returns to all history. Unfinished includes running, failed, stopped
and interrupted sessions; it is a historical result, not a claim about current file health
or whether a later retry succeeded. No automatic retry, deletion or source mutation occurs.

The database applies filters before the bounded 100-session read. Device choices include
older history outside that limit and use the saved device key, never the editable phone
name. Equal names receive separate numbered menu labels. SQL device values are bound
parameters. No schema migration or destination access is needed to browse history.

Changing filters clears previous rows and invalidates earlier reads. A read failure retains
the selected filter, exposes Try Again and does not display another scope's rows. A successful
empty result has a native No Matching Backups state with Clear Filters. Normal refresh
failure still retains the last successful rows for the same filter.

## Verification

- Four new core tests: same-name phones and SQL parameter binding; older device sessions
  outside the unfiltered limit; completed/running/partial/stopped/interrupted outcomes;
  filter-before-limit and empty/unknown-device results. All **354 core tests** pass.
- Two new hosted tests exercise overlapping filter reads and failed-filter retry. All
  **150 hosted app tests** pass. Existing offline-history and refresh-race tests still pass.
- Normal Debug and universal Release builds pass; strict lint reports zero violations
  across 113 source files. Whitespace checks and the Release bundle audit pass.
- Native UI with real saved history: all-device Unfinished shows three stopped sessions;
  selecting the connected phone shows only its one stopped session; selecting the other
  saved phone shows only its two. Clear Filters restores the full list. Light/standard and
  dark/compact layouts, menu labels, active-filter accessibility value and list caption
  were inspected. Actual empty-state rendering and full VoiceOver/older-OS runtime checks
  remain unverified; empty data/error/concurrency behavior has automated coverage.

Logs: `/tmp/cloakroll-history-core.log`, `/tmp/cloakroll-history-app-tests.log`,
`/tmp/cloakroll-history-debug.log`, `/tmp/cloakroll-history-release.log`, and
`/tmp/cloakroll-history-lint.log`. Initial new core test fixtures omitted the required
completion counters and correctly failed with invalidCompletion; corrected fixtures pass.
