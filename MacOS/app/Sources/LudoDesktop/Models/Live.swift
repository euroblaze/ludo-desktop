import Foundation

/// Live (Contract A / B) domain types. Decoded with `.convertFromSnakeCase`,
/// so snake_case JSON maps to these camelCase properties automatically.

/// Customer-facing migration record (Contract A — ludo-apps `Migration`).
struct Migration: Identifiable, Codable, Hashable {
    let id: String
    var accountId: String = ""
    var combo: String = ""
    var stateIndex: Int = 0
    var agentOutcome: String?
    var agentTotalCostUsd: Double?
    var ludoSessionId: String?
    var paid: Bool = false
}

private struct MigrationList: Codable { let items: [Migration] }

/// A customer account in the caller's roster (Contract A — `Account`).
struct Account: Identifiable, Codable, Hashable {
    let id: String
    var name: String?
    var type: String = "customer"
    var displayName: String { name?.isEmpty == false ? name! : id }
}

private struct AccountList: Codable { let items: [Account] }

// `MigrationState` (state_index 0–6 + labels) is now generated from the canonical
// cluster.yaml :: migration.states — see Generated/Generated.swift (CRIE 002 #8).

extension Migration {
    var state: MigrationState { MigrationState(rawValue: stateIndex) ?? .approved }
    /// Status text shown in the fleet, blending state + terminal outcome.
    var statusText: String { agentOutcome ?? state.label }
}

/// One Contract B event (SSE `data:` envelope from `GET /migrations/{id}/events`).
struct SessionEvent: Codable {
    let sessionId: String
    let type: String
    var payload: EventPayload = .init()
    var at: String = ""
    var schemaVersion: String = ""
    var checkpointRequired: Bool = false
}

/// Only the payload fields we read; unknown keys are ignored.
struct EventPayload: Codable {
    var model: String?
    var outcome: String?
    var totalModels: Int?
    var message: String?
    var position: Int?
    var costUsd: Double?
}

/// Caller identity (best-effort; bootstrap mainly keys off the roster size).
struct Me: Codable { var role: String = "customer"; var accountId: String? }

// MARK: - Mock fixtures (agency roster + a live event script)

extension MockData {
    static let accounts: [Account] = [
        Account(id: "acct_acme",  name: "Acme GmbH",  type: "customer"),
        Account(id: "acct_beta",  name: "Beta AG",    type: "customer"),
        Account(id: "acct_gamma", name: "Gamma KG",   type: "customer"),
    ]

    static let migrations: [Migration] = [
        Migration(id: "m_acme",  accountId: "acct_acme",  combo: "15.0 → 18.0", stateIndex: 2, ludoSessionId: "s_9f3a21", paid: true),
        Migration(id: "m_beta",  accountId: "acct_beta",  combo: "14.0 → 18.0", stateIndex: 5, agentOutcome: "migrated", agentTotalCostUsd: 41.0, paid: true),
        Migration(id: "m_gamma", accountId: "acct_gamma", combo: "16.0 → 18.0", stateIndex: 0, paid: false),
    ]

    /// A scripted Contract B sequence used by MockAPIClient.streamEvents.
    static func liveScript(sessionId: String = "s_9f3a21") -> [SessionEvent] {
        let models = ["res.partner", "product.template", "sale.order", "sale.order.line",
                      "account.move.line", "account.payment", "stock.move", "stock.quant"]
        var evs: [SessionEvent] = [
            SessionEvent(sessionId: sessionId, type: "session_started",
                         payload: EventPayload(totalModels: models.count), at: "11:42:03", schemaVersion: "2.0"),
        ]
        for (i, m) in models.enumerated() {
            evs.append(SessionEvent(sessionId: sessionId, type: "model_started",
                                    payload: EventPayload(model: m, totalModels: models.count, position: i + 1), schemaVersion: "2.0"))
            evs.append(SessionEvent(sessionId: sessionId, type: "turn_completed",
                                    payload: EventPayload(model: m, message: "applied recipe", costUsd: 5.5), schemaVersion: "2.0"))
            evs.append(SessionEvent(sessionId: sessionId, type: "model_completed",
                                    payload: EventPayload(model: m), schemaVersion: "2.0"))
        }
        evs.append(SessionEvent(sessionId: sessionId, type: "session_end",
                                payload: EventPayload(outcome: "migrated", costUsd: 44.0), schemaVersion: "2.0"))
        return evs
    }
}
