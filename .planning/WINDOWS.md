---
schema_version: 1
open_count: 2
waived_count: 0
fixed_count: 0
total_count: 2
last_updated: 2026-09-15T15:35:56.565Z
---

# Broken Windows Ledger

> Cross-phase defect register. With `workflow.windows_enforce` enabled, `/gsd-ship` blocks while `open_count > 0`.
> Waive with `gsd-tools windows waive <id> "<reason>"` (reason required).
> Mark fixed with `gsd-tools windows fixed <id>`.

| id | phase | kind | file | line | description | status | reason | recorded_at | resolved_at |
|----|-------|------|------|------|-------------|--------|--------|-------------|-------------|
| 1 | 01 | stub | android/src/main/kotlin/com/danjjohnson/compress_video/CompressVideoPlugin.kt |  | Template getPlatformVersion MethodChannel handler kept deliberately (plan 01-03 instruction) until replaced by the real Pigeon-backed implementation in plan 01-04. | open |  | 2026-09-15T15:35:53.281Z |  |
| 2 | 01 | stub | darwin/compress_video/Sources/compress_video/CompressVideoPlugin.swift |  | Template getPlatformVersion MethodChannel handler kept deliberately (plan 01-03 instruction) until replaced by the real Pigeon-backed implementation in plan 01-06. | open |  | 2026-09-15T15:35:56.565Z |  |

````json
[
  {
    "id": 1,
    "kind": "stub",
    "phase": "01",
    "file": "android/src/main/kotlin/com/danjjohnson/compress_video/CompressVideoPlugin.kt",
    "line": null,
    "description": "Template getPlatformVersion MethodChannel handler kept deliberately (plan 01-03 instruction) until replaced by the real Pigeon-backed implementation in plan 01-04.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-15T15:35:53.281Z",
    "resolved_at": null
  },
  {
    "id": 2,
    "kind": "stub",
    "phase": "01",
    "file": "darwin/compress_video/Sources/compress_video/CompressVideoPlugin.swift",
    "line": null,
    "description": "Template getPlatformVersion MethodChannel handler kept deliberately (plan 01-03 instruction) until replaced by the real Pigeon-backed implementation in plan 01-06.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-15T15:35:56.565Z",
    "resolved_at": null
  }
]
````
