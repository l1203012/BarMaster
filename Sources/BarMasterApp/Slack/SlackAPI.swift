import Foundation

/// A minimal Slack Web API client.
struct SlackAPI {
    struct Failure: LocalizedError {
        let method: String
        let message: String
        var errorDescription: String? { "\(method): \(message)" }
    }

    let userToken: String

    /// Calls `method` with form parameters, using the user token unless another is given.
    func call(_ method: String, _ parameters: [String: String] = [:], token: String? = nil) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://slack.com/api/\(method)")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token ?? userToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = parameters.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = form.percentEncodedQuery?.data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure(method: method, message: "unreadable response")
        }
        guard json["ok"] as? Bool == true else {
            throw Failure(method: method, message: json["error"] as? String ?? "unknown error")
        }
        return json
    }
}
