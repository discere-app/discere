# Diagnostics Mode: Optional Error Log Persistence

## Idea

Add an explicit UI toggle in a future diagnostics/developer mode that enables
local persistence of selected log statements.

Default behavior should remain unchanged:
- no persisted general logs
- only structured local diagnostics events

When the toggle is enabled:
- persist `Logger.error(...)`
- optionally also persist `Logger.warn(...)`
- write into the local diagnostics tables or a closely related diagnostics log table
- keep everything local on device

## Why

This would help for issues that are hard to reproduce during normal debugging:
- intermittent Android background failures
- temporary API/provider outages
- device-specific runtime errors
- errors that happen before a developer can inspect live logs

It would also make later export/share of a diagnostics report more useful.

## Requirements

- explicit opt-in in UI
- clearly visible indicator that diagnostics mode is active
- local-only storage, no remote reporting
- ring buffer / bounded size
- automatic shutdown when disabled
- include timestamp, scope, level, message
- optionally include stack trace for `error`

## Important Constraint

Do **not** persist all debug logs by default.

That would create too much noise and unnecessary storage churn. The persisted
mode should be focused on high-signal diagnostics only.

## Possible Future Design

1. Extend `Logger` with an optional diagnostics sink.
2. Activate that sink only when diagnostics mode is enabled in UI.
3. Filter by level/category, e.g.:
   - `error`
   - optional `warning`
   - optional categories like `network`, `background`, `enrichment`
4. Expose persisted entries later in a diagnostics/analyze screen.
5. Allow exporting a compact local diagnostics report.
