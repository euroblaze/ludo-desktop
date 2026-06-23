# ludo-desktop

Native desktop clients for LUDO — one per OS. Each is a **thin client of the ludo-apps
BFF** (Contract A, REST + SSE): sign in, review discovery, **choose modules/models/custom
fields to migrate**, launch, and monitor live. No client touches MinIO, the agent, or the
broker; only `account_id` crosses, never customer PII.

| Folder | Platform | Status |
|---|---|---|
| `MacOS/` | macOS 14+ (SwiftUI, universal) | PRD + prototypes ready (`prd_macos.md`, `prototypes/`) |
| `Windows/` | Windows (stack TBD) | placeholder — parity, after macOS (`prd_windows.md`) |

Feature epic: euroblaze/ludo-flywheel#94 · engine support: euroblaze/ludo#466.
Backend behaviour is authoritative in `MacOS/prd_macos.md`; Windows records only deltas.

This folder is a sibling of `ludo-agent/` and `ludo-apps/` in the workspace; it has its own
versioning (not part of either repo).

## License

Business Source License 1.1 (Licensor: wapsol (labs) gmbh) → Apache-2.0 at the change date.
Source-available, not OSI open-source. See `LICENSE`.
