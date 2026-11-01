import Foundation

public struct FormFlowOutcome: Codable, Equatable {
    public var passed: Bool?
    public var outcomeId: String?
    public var endingId: String?
}

/// A JSON value from the form (an answer).
public enum FormFlowValue: Equatable {
    case string(String), number(Double), bool(Bool), array([FormFlowValue]), object([String: FormFlowValue]), null

    init(json: Any) {
        switch json {
        case let s as String: self = .string(s)
        case let n as NSNumber: self = CFGetTypeID(n) == CFBooleanGetTypeID() ? .bool(n.boolValue) : .number(n.doubleValue)
        case let a as [Any]: self = .array(a.map(FormFlowValue.init(json:)))
        case let o as [String: Any]: self = .object(o.mapValues(FormFlowValue.init(json:)))
        default: self = .null
        }
    }

    var jsonObject: Any {
        switch self {
        case let .string(s): return s
        case let .number(n): return n
        case let .bool(b): return b
        case let .array(a): return a.map { $0.jsonObject }
        case let .object(o): return o.mapValues { $0.jsonObject }
        case .null: return NSNull()
        }
    }
}

/// The form asks the app to do something: notifications, tracking, open a URL, sign in, deep link, or a custom name.
public struct FormFlowRequest: Codable, Equatable {
    public var requestId: String
    public var action: String
    public var params: [String: String]
}

public enum FormFlowEvent: Equatable {
    case ready(formId: String, versionId: String?, experimentId: String?, variantId: String?, locale: String)
    case view
    case start
    case step(index: Int, fieldId: String, total: Int)
    /// `value` is present only when `includeAnswers` is on and the field is not sensitive.
    case answer(fieldId: String, type: String, value: FormFlowValue?)
    case complete(submissionId: String, outcome: FormFlowOutcome, endingId: String?, durationMs: Int?, answers: [String: FormFlowValue]?)
    case request(FormFlowRequest)
    case progress(step: Int, total: Int, percent: Int)
    case close
    case error(message: String)

    /// Parse a message from the `formflow` script message handler (a dictionary) or a JSON string/Data. Returns nil for anything else.
    public static func parse(_ body: Any) -> FormFlowEvent? {
        var obj: [String: Any]?
        if let d = body as? [String: Any] { obj = d }
        else if let s = body as? String, let d = s.data(using: .utf8) { obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] }
        else if let d = body as? Data { obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] }
        guard let o = obj, o["source"] as? String == "formflow", let type = o["type"] as? String else { return nil }
        let data = o["data"] as? [String: Any] ?? [:]
        switch type {
        case "ready":
            return .ready(formId: data["formId"] as? String ?? (o["formId"] as? String ?? ""), versionId: data["versionId"] as? String,
                          experimentId: data["experimentId"] as? String, variantId: data["variantId"] as? String, locale: data["locale"] as? String ?? "")
        case "view": return .view
        case "start": return .start
        case "step":
            guard let i = data["index"] as? Int, let t = data["total"] as? Int else { return nil }
            return .step(index: i, fieldId: data["fieldId"] as? String ?? "", total: t)
        case "answer":
            guard let f = data["fieldId"] as? String else { return nil }
            var v: FormFlowValue?
            if let raw = data["value"], !(raw is NSNull) { v = FormFlowValue(json: raw) }
            return .answer(fieldId: f, type: data["type"] as? String ?? "unknown", value: v)
        case "complete":
            guard let id = data["submissionId"] as? String else { return nil }
            let oc = data["outcome"] as? [String: Any] ?? [:]
            let outcome = FormFlowOutcome(passed: oc["passed"] as? Bool, outcomeId: oc["outcomeId"] as? String, endingId: oc["endingId"] as? String)
            return .complete(submissionId: id, outcome: outcome, endingId: data["endingId"] as? String, durationMs: data["durationMs"] as? Int,
                             answers: (data["answers"] as? [String: Any])?.mapValues(FormFlowValue.init(json:)))
        case "request":
            guard let id = data["requestId"] as? String, let a = data["action"] as? String else { return nil }
            return .request(FormFlowRequest(requestId: id, action: a, params: data["params"] as? [String: String] ?? [:]))
        case "progress":
            guard let s = data["step"] as? Int, let t = data["total"] as? Int else { return nil }
            return .progress(step: s, total: t, percent: data["percent"] as? Int ?? 0)
        case "close": return .close
        case "error": return .error(message: data["message"] as? String ?? "")
        default: return nil // submit (folded into complete), resize
        }
    }
}

public protocol FormFlowDelegate: AnyObject {
    func formFlow(didReceive event: FormFlowEvent)
}

/// Optional closures; set the ones you need. A delegate gets every event too.
public struct FormFlowHandlers {
    public var onReady: ((_ formId: String, _ versionId: String?, _ experimentId: String?, _ variantId: String?, _ locale: String) -> Void)?
    public var onStart: (() -> Void)?
    public var onStep: ((_ index: Int, _ fieldId: String, _ total: Int) -> Void)?
    public var onAnswer: ((_ fieldId: String, _ type: String, _ value: FormFlowValue?) -> Void)?
    public var onComplete: ((_ submissionId: String, _ outcome: FormFlowOutcome, _ endingId: String?, _ durationMs: Int?, _ answers: [String: FormFlowValue]?) -> Void)?
    /// Answer a `request` by calling `respond` (now or later). The result goes back to the form.
    public var onRequest: ((_ request: FormFlowRequest, _ respond: @escaping (FormFlowValue) -> Void) -> Void)?
    /// The form was not ready in time (or failed to load). Carry on with your own flow.
    public var onTimeout: (() -> Void)?
    public var onClose: (() -> Void)?
    public var onError: ((_ message: String) -> Void)?
    public var onEvent: ((FormFlowEvent) -> Void)?
    public init() {}

    func dispatch(_ e: FormFlowEvent) {
        switch e {
        case let .ready(f, v, x, va, l): onReady?(f, v, x, va, l)
        case .start: onStart?()
        case let .step(i, f, t): onStep?(i, f, t)
        case let .answer(f, t, v): onAnswer?(f, t, v)
        case let .complete(s, o, en, d, a): onComplete?(s, o, en, d, a)
        case .close: onClose?()
        case let .error(m): onError?(m)
        case .view, .progress, .request: break
        }
        onEvent?(e)
    }
}
