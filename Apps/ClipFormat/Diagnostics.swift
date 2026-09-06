import Foundation

/// Debug-build diagnostics, shipped to a local LogDock collector when one is
/// configured. A menu-bar app has no console to watch, and `NSLog` from a
/// sandboxed agent process is awkward to read back, so events go somewhere an
/// agent or a human can query.
///
/// Release builds compile this down to nothing: no network, no entitlement.
enum Diagnostics {
    #if DEBUG
    private static let endpoint: URL? = {
        guard let raw = ProcessInfo.processInfo.environment["CLIPFORMAT_LOG_URL"]
                ?? UserDefaults.standard.string(forKey: "LogDockURL") else { return nil }
        return URL(string: raw)?.appendingPathComponent("v1/ingest")
    }()

    private static let token: String? = ProcessInfo.processInfo.environment["CLIPFORMAT_LOG_TOKEN"]
        ?? UserDefaults.standard.string(forKey: "LogDockToken")

    private static let formatter = ISO8601DateFormatter()
    #endif

    static func info(_ message: String, _ metadata: [String: String] = [:]) {
        send(level: "info", message: message, metadata: metadata)
    }

    static func error(_ message: String, _ metadata: [String: String] = [:]) {
        send(level: "error", message: message, metadata: metadata)
    }

    private static func send(level: String, message: String, metadata: [String: String]) {
        #if DEBUG
        NSLog("ClipFormat [\(level)] \(message) \(metadata)")
        guard let endpoint, let token else { return }

        let body: [String: Any] = [
            "source": "clipformat-mac",
            "entries": [[
                "level": level,
                "message": message,
                "timestamp": formatter.string(from: Date()),
                "metadata": metadata,
            ]],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        // Fire and forget: a logging aid must never change how the app behaves.
        URLSession.shared.dataTask(with: request).resume()
        #endif
    }
}
