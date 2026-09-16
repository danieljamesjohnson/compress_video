---
schema_version: 1
open_count: 5
waived_count: 0
fixed_count: 0
total_count: 5
last_updated: 2026-09-16T03:06:00.964Z
---

# Broken Windows Ledger

> Cross-phase defect register. With `workflow.windows_enforce` enabled, `/gsd-ship` blocks while `open_count > 0`.
> Waive with `gsd-tools windows waive <id> "<reason>"` (reason required).
> Mark fixed with `gsd-tools windows fixed <id>`.

| id | phase | kind | file | line | description | status | reason | recorded_at | resolved_at |
|----|-------|------|------|------|-------------|--------|--------|-------------|-------------|
| 1 | 01 | stub | android/src/main/kotlin/com/danjjohnson/compress_video/CompressVideoPlugin.kt |  | Template getPlatformVersion MethodChannel handler kept deliberately (plan 01-03 instruction) until replaced by the real Pigeon-backed implementation in plan 01-04. | open |  | 2026-09-15T15:35:53.281Z |  |
| 2 | 01 | stub | darwin/compress_video/Sources/compress_video/CompressVideoPlugin.swift |  | Template getPlatformVersion MethodChannel handler kept deliberately (plan 01-03 instruction) until replaced by the real Pigeon-backed implementation in plan 01-06. | open |  | 2026-09-15T15:35:56.565Z |  |
| 3 | 02 | unrun-verify | .github/workflows/ci.yml |  | New APK native-lib/zipalign/build-constraint CI step is wired and passes the same commands locally, but this session did not push to trigger a live CI run (consistent with this phase's no-push-per-plan practice); QUESTIONS.md item 6 already tracks the Apple job's billing block separately. | open |  | 2026-09-16T03:06:00.774Z |  |
| 4 | 02 | unrun-verify | android/src/main/kotlin/com/danjjohnson/compress_video/PluginFiles.kt |  | clearCache()'s symlink-escape mitigation (T-02-26: a candidate whose canonical path resolves outside the cache directory is skipped) is code-reviewed and unit-reasoned but has no dedicated symlink-based integration test proving it functionally. | open |  | 2026-09-16T03:06:00.867Z |  |
| 5 | 02 | unrun-verify | example/lib/main.dart |  | The plan's optional manual on-device check of the new compress screen (tap Compress, watch progress, tap Cancel) was inconclusive on the danserver headless emulator (native splash persisted); the underlying CompressVideo.compress()/cancel() calls are already proven end-to-end by automated integration tests. | open |  | 2026-09-16T03:06:00.964Z |  |

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
  },
  {
    "id": 3,
    "kind": "unrun-verify",
    "phase": "02",
    "file": ".github/workflows/ci.yml",
    "line": null,
    "description": "New APK native-lib/zipalign/build-constraint CI step is wired and passes the same commands locally, but this session did not push to trigger a live CI run (consistent with this phase's no-push-per-plan practice); QUESTIONS.md item 6 already tracks the Apple job's billing block separately.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-16T03:06:00.774Z",
    "resolved_at": null
  },
  {
    "id": 4,
    "kind": "unrun-verify",
    "phase": "02",
    "file": "android/src/main/kotlin/com/danjjohnson/compress_video/PluginFiles.kt",
    "line": null,
    "description": "clearCache()'s symlink-escape mitigation (T-02-26: a candidate whose canonical path resolves outside the cache directory is skipped) is code-reviewed and unit-reasoned but has no dedicated symlink-based integration test proving it functionally.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-16T03:06:00.867Z",
    "resolved_at": null
  },
  {
    "id": 5,
    "kind": "unrun-verify",
    "phase": "02",
    "file": "example/lib/main.dart",
    "line": null,
    "description": "The plan's optional manual on-device check of the new compress screen (tap Compress, watch progress, tap Cancel) was inconclusive on the danserver headless emulator (native splash persisted); the underlying CompressVideo.compress()/cancel() calls are already proven end-to-end by automated integration tests.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-16T03:06:00.964Z",
    "resolved_at": null
  }
]
````
