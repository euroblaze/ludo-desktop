import Foundation

/// Resolves the LUDO gateway base URL for the desktop client.
///
/// Order (per the cluster client-config convention — `ludo-init/docs/contracts-consumer-guide.md`):
///   env `LUDO_API_URL` → `UserDefaults["LUDO_API_URL"]` → the prod default from the canonical
/// `constants/cluster.yaml` `domains` block. Never hardcode a deployment URL at a call site
/// (CRIE 002 #5).
enum ClientConfig {
    /// cluster.yaml :: domains.prod.public — the public gateway edge. Dev overrides via
    /// `LUDO_API_URL` (e.g. `http://10.0.99.1:8080`, the loopback alias — never `localhost`).
    static let defaultBaseURL = URL(string: "https://runludo.com")!

    static var baseURL: URL {
        for source in [ProcessInfo.processInfo.environment["LUDO_API_URL"],
                       UserDefaults.standard.string(forKey: "LUDO_API_URL")] {
            if let raw = source?.trimmingCharacters(in: .whitespacesAndNewlines),
               !raw.isEmpty, let url = URL(string: raw) {
                return url
            }
        }
        return defaultBaseURL
    }
}
