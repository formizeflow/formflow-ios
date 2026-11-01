import Foundation

/// Response of POST /api/v1/public/onboarding/decide.
public struct FormFlowDecision: Codable, Equatable {
    public var show: Bool
    public var experimentId: String?
    public var variantId: String?
    public var formId: String?
    public var slug: String?
    public var versionId: String?
    public var reason: String
    /// Set by the SDK when the network failed and a cached decision was returned.
    public var fromCache: Bool?

    /// A config for this decision, or nil when the flow must be skipped (holdout, completed, no match).
    public func config(from base: FormFlowConfig) -> FormFlowConfig? {
        guard show, let slug = slug else { return nil }
        var c = base; c.slug = slug
        if let v = variantId { c.variant = v }
        return c
    }
}

public struct FormFlowDecideRequest {
    public var entry: String
    public var uid: String?
    public var uidSignature: String?
    public var attributes: [String: String]
    public var posthogSessionId: String?
    public var posthogDistinctId: String?
    public init(entry: String, uid: String? = nil, uidSignature: String? = nil, attributes: [String: String] = [:], posthogSessionId: String? = nil, posthogDistinctId: String? = nil) {
        self.entry = entry; self.uid = uid; self.uidSignature = uidSignature; self.attributes = attributes
        self.posthogSessionId = posthogSessionId; self.posthogDistinctId = posthogDistinctId
    }
}

public final class FormFlowClient {
    public let baseURL: URL
    private let session: URLSession
    private let defaults: UserDefaults
    private let timeout: TimeInterval

    public init(baseURL: URL, timeout: TimeInterval = 8, session: URLSession = .shared, defaults: UserDefaults = .standard) {
        self.baseURL = baseURL; self.timeout = timeout; self.session = session; self.defaults = defaults
    }

    func cacheKey(_ r: FormFlowDecideRequest) -> String { "formflow.decision.\(r.entry).\(r.uid ?? "anon")" }

    public func cached(_ r: FormFlowDecideRequest) -> FormFlowDecision? {
        defaults.data(forKey: cacheKey(r)).flatMap { try? JSONDecoder().decode(FormFlowDecision.self, from: $0) }
    }

    func body(_ r: FormFlowDecideRequest) -> [String: Any] {
        var b: [String: Any] = ["entry": r.entry, "attributes": FormFlowConfig(baseURL: baseURL, slug: "x", attributes: r.attributes).resolvedAttributes]
        if let u = r.uid { b["uid"] = u }
        if let s = r.uidSignature { b["uid_sig"] = s }
        if let s = r.posthogSessionId { b["ph_session"] = s }
        if let d = r.posthogDistinctId { b["ph_distinct"] = d }
        return b
    }

    /// Ask the server whether to show the flow. On network failure returns the cached decision (`fromCache`) or throws.
    public func decide(_ r: FormFlowDecideRequest) async throws -> FormFlowDecision {
        var req = URLRequest(url: baseURL.appendingPathComponent("api/v1/public/onboarding/decide"), timeoutInterval: timeout)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body(r))
        do {
            let (data, resp) = try await session.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let d = try FormFlowClient.decode(data)
            if let enc = try? JSONEncoder().encode(d) { defaults.set(enc, forKey: cacheKey(r)) }
            return d
        } catch {
            if var c = cached(r) { c.fromCache = true; return c }
            throw error
        }
    }

    /// Warm the decision cache. Never throws.
    public func preload(_ r: FormFlowDecideRequest) async -> FormFlowDecision? { try? await decide(r) }

    /// Accepts `{data: {...}}` or the bare object.
    static func decode(_ data: Data) throws -> FormFlowDecision {
        struct Wrapped: Decodable { var data: FormFlowDecision }
        if let w = try? JSONDecoder().decode(Wrapped.self, from: data) { return w.data }
        return try JSONDecoder().decode(FormFlowDecision.self, from: data)
    }
}
