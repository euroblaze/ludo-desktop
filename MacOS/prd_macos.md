# LUDO Desktop — macOS · Product Requirements

Status: draft for hand-off · Owner: product · Target: 0.2.apps
Related: feature epic euroblaze/ludo-flywheel#94 · engine euroblaze/ludo#466 ·
`ludo-apps/specs/02_portal.md` · `ludo-apps/specs/04_backend_api.md` · Windows parity `../Windows/prd_windows.md`
Prototypes: `prototypes/*.png` (+ source `*.html`)

---

## 1. Purpose & context

A **native macOS client** that lets a customer drive an Odoo migration end-to-end:
sign in, review the read-only **discovery/X-Ray** of their source system, **choose
which modules / models (and toggle custom fields) to migrate**, launch the run, and
**watch it live**. It is the richer-than-web surface for the scope-selection feature
(epic #94); the Vue portal offers the same flow for browser users.

The app is a **thin client of the ludo-apps BFF** (Contract A, REST + SSE). It
**never** touches MinIO or the agent directly, and **never** holds customer PII
beyond what the customer types into a form to reach their own Odoo. All scope,
inventory, and event data flow through `apps/api`.

Non-goals: no migration logic in the client (engine is server-side); no direct DB or
broker access; not an admin/operator console (that is superadmin web).

## 2. Target & platform

- macOS **14 Sonoma or later**. **Universal binary** (Apple Silicon + Intel).
- Single-window document-less app; standard menu bar; full keyboard + VoiceOver support.
- Distribution: **Developer ID + notarization + hardened runtime + App Sandbox**
  (network-client entitlement only). Auto-update via **Sparkle**. (App Store is a
  later option — see Open questions.)

## 3. Tech stack (recommended)

| Concern | Choice |
|---|---|
| UI | **SwiftUI** (macOS 14), `NavigationSplitView` 3-column for the scope picker |
| Language | Swift 5.9+, structured concurrency (`async/await`, `TaskGroup`) |
| State | `@Observable` (Observation framework) view models, MVVM |
| Networking | `URLSession` async; **typed `Codable` models aligned to Contract A** |
| Live events | SSE over `URLSession.bytes` (async line stream); auto-reconnect w/ backoff |
| Auth | Browser-redirect GitHub OAuth + **PKCE** via `ASWebAuthenticationSession`, custom scheme `ludo-desktop://`; token in **Keychain** |
| Persistence | Keychain (token) + small `UserDefaults`/SwiftData cache (last connection, UI prefs) |
| Localization | String Catalogs (`.xcstrings`), **en + de** (see §10) |
| Updates | Sparkle |
| Min tooling | Xcode 15+, no third-party UI frameworks required |

## 4. Architecture

```
SwiftUI Views ─▶ ViewModels (@Observable) ─▶ APIClient ──HTTPS──▶ ludo-apps BFF (Contract A)
                                          └─ EventClient ─SSE──▶ /migrations/{id}/events
Keychain ◀─ token        (no MinIO, no agent, no broker — all via apps/api)
```

- **APIClient** — one actor wrapping `URLSession`; injects bearer token; decodes typed
  DTOs; maps non-2xx to a typed `APIError`.
- **EventClient** — subscribes to the migration SSE relay; emits decoded Contract-B-derived
  events to the monitor view model; reconnects and resumes on drop.
- **AppModel** — root `@Observable`: auth state, current account, selected connection,
  active migration. Child view models per screen.
- DTOs **mirror Contract A**; when the OpenAPI artifact materializes
  (`packages/contract-internal/openapi.yaml`, per specs/04) generate clients from it.

## 5. Backend API consumed (Contract A)

> **Canonical, client-agnostic version of this section** (tech stack §3, this endpoint table,
> and the scope rules §7) now lives in **[`ludo-init/docs/contracts-consumer-guide.md`](../../ludo-init/docs/contracts-consumer-guide.md)**,
> against the canonical schema in `ludo-init/contracts/`. The table below is the macOS-specific
> view; defer to the consumer guide + contracts where they differ. (The "BFF" is being absorbed
> into the **gateway** — `ludo-webapps`'s backend retires there.)

All under the authenticated gateway. Endpoints in **bold** are added by epic #94; others exist.

| Purpose | Method · path | Notes |
|---|---|---|
| Desktop auth start | `GET /auth/desktop/start?redirect_uri=ludo-desktop://auth/callback&code_challenge=…` | opens in browser; BFF brokers GitHub OAuth |
| Desktop auth callback | redirect → `ludo-desktop://auth/callback?code=…` | app catches via custom scheme |
| Desktop token exchange | `POST /auth/desktop/token` `{code, code_verifier}` | PKCE; returns bearer token → Keychain |
| Current account | `GET /me` | account_id, locale, entitlements |
| Connections / vault | `GET /connections`, `POST /connections` | source Odoo creds (vault-encrypted server-side) |
| Run estimate / X-Ray | `POST /estimates` , `GET /estimates/{id}` | read-only scan; produces inventory |
| **Inventory** | **`GET /estimates/{id}/inventory`** | modules, module→models, record counts, custom_fields, port_blockers |
| **Resolve scope** | **`POST /estimates/{id}/resolve-scope`** | body `{selected_modules, selected_models, excluded_custom_fields}` → `{final_models, auto_included_deps, port_blockers_hit, excluded_system_models}` |
| Create migration | `POST /migrations` | carries `selected_modules/models/excluded_custom_fields` |
| Patch scope | `PATCH /migrations/{id}` | edit selection on a draft |
| Approve / launch | `POST /migrations/{id}/approve` | enqueues the job (mode estimate\|migrate\|dry-run) |
| Status | `GET /migrations/{id}` | state_index, agent_outcome, cost |
| Live events | `GET /migrations/{id}/events` (SSE) | relayed Contract B (model/job/turn/safety/session_end) |

The agent-side DTO these proxy is defined in euroblaze/ludo#466; the client only ever
sees the apps shape.

## 6. Screens

Numbers map to prototype files. Each screen lists purpose · key components · states.

### 6.1 Sign in — `01_signin.png`
- Purpose: authenticate via **browser-redirect** OAuth (the "like Claude" flow) — no in-app
  password form.
- Flow: tap **Sign in with GitHub** → `ASWebAuthenticationSession` opens the **system browser**
  to `GET /auth/desktop/start` (carrying a **PKCE** `code_challenge` + `redirect_uri`) → BFF
  brokers GitHub OAuth → redirect returns to the custom scheme **`ludo-desktop://auth/callback?code=…`**
  → app exchanges `{code, code_verifier}` at `POST /auth/desktop/token` for a bearer token →
  **Keychain**. (Loopback `127.0.0.1` is the CLI-style alternative; custom scheme chosen for the GUI app.)
- Components: brand, **Sign in with GitHub**, endpoint hint.
- States: idle · authenticating (browser open) · error (network/denied; user-cancel is silent).
  On success → Discovery/last view.

### 6.2 Discovery — `02_discovery.png`
- Purpose: show the read-only scan result and entry to scope.
- Components: source-list sidebar (Estimates · Discovery · Migrations · Activity · Connection);
  version-pair pill; stat cards (modules, models, records, **port-blockers** highlighted);
  largest-modules + readiness panels; **Configure scope →** primary.
- States: scanning (progress) · ready · scan-failed (retry). Re-scan re-runs the estimate.

### 6.3 Scope picker — `03_scope_picker.png` *(hero)*
- Purpose: choose modules → models, toggle custom fields, see auto-included deps.
- Layout: **3-column** `NavigationSplitView`.
  - **Col 1 — categories/modules:** tri-state checkboxes (all checked by default = opt-out),
    grouped by Odoo category, per-row count. "All" master + "System" unchecked by default.
  - **Col 2 — models in selection:** table (checkbox · `model` + label · records · fields),
    module master checkbox in header, toolbar **search** filter.
  - **Col 3 — inspector:** for the selected model — its **custom/Studio fields** as toggles
    (standard fields always migrate, shown as a note); **Also required (auto-included)** list
    from `resolve-scope`; **port-blocker** warning when a custom module owns selected data.
- Footer summary bar: `N of M models · +K dependencies · ~records · est. €`.
- Behaviour: any change → debounced (≈300 ms) `POST /resolve-scope`; update deps + footer.
  Tri-state propagation: module ↔ its models; "All" ↔ everything. **Reset to all** clears
  the selection (→ default opt-out). **Review →** persists via create/PATCH.
- States: loading inventory · interactive · resolving (subtle) · resolve-error (keep last good).

### 6.4 Review & launch — `04_review_launch.png`
- Purpose: confirm scope + mode, then start.
- Components: **Selected scope** card (modules, models +deps, excluded, dropped custom fields,
  records, port-blockers); **Estimate** card (cost, duration, version pair); **Run mode**
  segmented control (Estimate · Migrate · Dry-run); **Start migration** primary.
- States: ready · submitting · submit-error · idempotency block (one live migration per
  customer — flywheel #84).

### 6.5 Migration monitor — `05_monitor.png`
- Purpose: live progress + audit while the engine runs.
- Components: overall progress **ring** + "N of M models" + ETA + current model/batch;
  KPI row (records loaded · drift/rollbacks · Cortex wake-ups · cost so far);
  **per-model list** with status (done/running/queued/failed) + progress bars;
  **Live activity** log of relayed Contract-B events (session_started, blueprint_generated,
  model_completed, job_started, turn_*, safety_event); footer (outcome target, data-loss
  count, pending state-checkpoint). **Pause** / **Cancel** (cooperative cancel, agent #416).
- States: connecting · streaming · reconnecting (banner) · paused · completed (→ Outcome) ·
  failed. Closing the app and reopening **re-attaches** to the stream.

### 6.6 Outcome (post-run, no separate mock yet)
- Result badge (migrated / partial / novel / aborted), per-model summary, **download report**
  (presigned via apps), cost, "Back to migrations". Reuse the monitor layout in a final state.

## 7. Scope-selection rules (client behaviour)

- **Default = everything (opt-out).** Empty selection = migrate all discovered models.
- **Granularity = module → model + custom-fields-only.** Standard fields always migrate;
  only custom/Studio fields are individually de-selectable (drop = exclude from extract).
- **Dependencies auto-include + show.** The client never computes closure; it sends the
  tentative selection to `/resolve-scope` and renders `auto_included_deps` + `port_blockers_hit`.
- **System models** (`_SKIP_MODELS`) are surfaced as `excluded_system_models` (read-only,
  cannot be forced in).
- Selection persists on the Migration (`selected_modules`, `selected_models`,
  `excluded_custom_fields`) — never recomputed client-side at launch.

## 8. State, offline & errors

- Token refresh / 401 → silent re-auth, else return to Sign in.
- All network calls cancellable; screens show skeleton/loading and typed error states.
- SSE: exponential backoff reconnect; on reconnect, fetch `GET /migrations/{id}` to
  reconcile current state before resuming the stream.
- No destructive local cache; the BFF is the source of truth.

## 9. Visual design

- System fonts (SF Pro), system **accent**, native controls; **light + dark** mode.
- Spacing/typography per the prototypes; SF Symbols for icons.
- Full **accessibility**: every control labelled (mirrors the web "every element gets an
  id" rule), VoiceOver, Dynamic Type, keyboard navigation, reduced-motion.

## 10. Localization

- Follows the apps locale rule (specs + `libs/shared/i18n.js` doctrine): **system language,
  English fallback**. Ship **en + de** strings (German customers). Currency/number/date via
  `Locale`; **€** default. No hard-coded user-facing strings.

## 11. Security

- **Browser-redirect GitHub OAuth + PKCE** (`ASWebAuthenticationSession`, custom scheme
  `ludo-desktop://auth/callback`) — no in-app password form; bearer token in **Keychain**.
  The `code_verifier` never leaves the device; only the `code_challenge` goes to the BFF.
- Source-Odoo credentials entered in the app are sent to the BFF over **TLS** for
  vault encryption server-side; **never** written to disk locally.
- App Sandbox (network client), hardened runtime, notarized. ATS enforced (no plaintext HTTP).
- The client carries `account_id` only; no other customer PII leaves the device beyond the
  creds the customer enters for their own system.

## 12. Distribution & ops

- Developer ID signing + notarization; Sparkle appcast for updates.
- Crash/error reporting privacy-respecting and **opt-in**; no analytics without consent.
- Versioning tracks `0.2.apps`; min-supported-BFF check on launch (graceful upgrade prompt).

## 13. Milestones

1. **M1 — Shell + auth.** App skeleton, sidebar nav, GitHub OAuth, `/me`, Keychain. 
2. **M2 — Discovery + scope picker (read).** Inventory fetch + 3-column picker + resolve-scope,
   against the **stub** BFF (epic #94 Phase 0/1). Visible value without the broker.
3. **M3 — Launch + monitor.** Create/approve migration, SSE monitor, cancel/resume.
4. **M4 — Outcome + polish + distribution.** Report download, dark mode, a11y, notarize, Sparkle.
5. **(Later) Windows app** — see §14; reuse the **Contract A** OpenAPI + DTOs; native WinUI/.NET.

## 14. Open questions
- **Primary user:** customer self-serve vs operator-assisted? (affects vault-cred entry in-app).
- **Vault credentials:** entered in the desktop app, or portal-only with desktop read-only?
- **Distribution:** Developer ID + Sparkle (recommended) vs Mac App Store (sandbox/IAP constraints).
- **Windows stack:** WinUI 3 / .NET MAUI (native) vs a shared cross-platform core. macOS ships first.
- **Estimate cost display:** show € to customer here, or keep cost operator-only (portal parity)?

## 15. Acceptance criteria
- Sign in with GitHub; token persists across launches (Keychain).
- After a scan, the picker shows real inventory; default state selects everything.
- De-selecting a module/model updates the footer and the auto-included-dependency list via
  `/resolve-scope`; custom fields toggle per model.
- Launching persists `selected_modules/models/excluded_custom_fields` on the Migration and
  enqueues the chosen mode.
- Monitor reflects live Contract-B events; survives a dropped connection (reconnect + reconcile).
- Universal binary, notarized, passes App Sandbox; en + de localized; light + dark; VoiceOver-navigable.
