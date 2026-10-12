import Foundation

struct ThinQError: LocalizedError, Equatable {
    let message: String
    var errorDescription: String? { message }
}

/// Client for the official LG ThinQ Connect API.
struct ThinQ: Sendable {
    var pat: String
    var country: String

    private static let baseURL = "https://api-aic.lgthinq.com"
    private static let apiKey = "v6GFvkweNo7DK7yD3ylIZ9w52aKBU0eJ7wLXkSR3" // Public API key from official app, may need updating if it breaks
    private static let clientID = "acbar-\(UUID().uuidString)"

    func devices() async throws -> [AC] {
        let list = try await request("/devices") as? [[String: Any]] ?? []
        var result: [AC] = []
        for (id, name) in Self.airConditioners(in: list) {
            let state = try await request("/devices/\(id)/state") as? [String: Any] ?? [:]
            result.append(AC(id: id, name: name, state: state))
        }
        return result
    }

    func control(_ id: String, _ body: Data) async throws {
        _ = try await request("/devices/\(id)/control", body: body)
    }

    /// Keeps only air conditioners from the `GET /devices` list; the account may hold other LG appliances.
    static func airConditioners(in list: [[String: Any]]) -> [(id: String, name: String)] {
        list.compactMap { device in
            let info = device["deviceInfo"] as? [String: Any] ?? [:]
            guard let id = device["deviceId"] as? String,
                  info["deviceType"] as? String == "DEVICE_AIR_CONDITIONER" else { return nil }
            return (id, info["alias"] as? String ?? id)
        }
    }

    /// Returns the `response` field of a successful reply, or throws the API's error message.
    /// A 200 reply that is not JSON (a proxy or maintenance page) is an error too, not an empty result.
    static func decode(_ data: Data, status: Int) throws -> Any? {
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard status == 200, json != nil || data.isEmpty else {
            let message = (json?["error"] as? [String: Any])?["message"] as? String
            throw ThinQError(message: message ?? "HTTP \(status): \(String(decoding: data.prefix(200), as: UTF8.self))")
        }
        return json?["response"]
    }

    private func request(_ path: String, body: Data? = nil) async throws -> Any? {
        var req = URLRequest(url: URL(string: Self.baseURL + path)!)
        req.httpMethod = body == nil ? "GET" : "POST"
        req.httpBody = body
        for (header, value) in [
            "Authorization": "Bearer \(pat)",
            "x-api-key": Self.apiKey,
            "x-client-id": Self.clientID,
            "x-country": country,
            "x-message-id": String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(22)),
            "x-service-phase": "OP",
            "Content-Type": "application/json",
        ] {
            req.setValue(value, forHTTPHeaderField: header)
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        return try Self.decode(data, status: (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}
