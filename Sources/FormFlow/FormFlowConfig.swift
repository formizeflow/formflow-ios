import Foundation
#if canImport(UIKit)
import UIKit
#endif

public let formFlowVersion = "0.1.0"
public let formFlowUserAgentSuffix = "FormFlowiOS/\(formFlowVersion)"

public struct FormFlowConfig {
    public var baseURL: URL
    public var slug: String
    public var uid: String?
    /// HMAC of `uid` computed on YOUR server. Never sign in the app.
    public var uidSignature: String?
    /// User attributes (`attrs.<key>`). Platform, os_version, device_model, locale and app_version are added unless `autoAttributes` is false.
    public var attributes: [String: String]
    public var autoAttributes: Bool
    public var posthogSessionId: String?
    public var posthogDistinctId: String?
    /// `false` starts over instead of resuming saved progress (server-side, per uid).
    public var resume: Bool?
    public var appearance: FormFlowAppearance?
    /// Seconds to wait for the form to become ready before `onTimeout` fires.
    public var timeout: TimeInterval
    public var variant: String?
    public var locale: String?
    public var hidden: [String: String]
    public var prefill: [String: String]
    /// Also receive answer values (never for sensitive fields).
    public var includeAnswers: Bool
    public var showClose: Bool

    public init(baseURL: URL, slug: String, uid: String? = nil, variant: String? = nil, locale: String? = nil,
                hidden: [String: String] = [:], prefill: [String: String] = [:],
                includeAnswers: Bool = false, showClose: Bool = false,
                uidSignature: String? = nil, attributes: [String: String] = [:], autoAttributes: Bool = true,
                posthogSessionId: String? = nil, posthogDistinctId: String? = nil, resume: Bool? = nil,
                appearance: FormFlowAppearance? = nil, timeout: TimeInterval = 8) {
        self.uidSignature = uidSignature; self.attributes = attributes; self.autoAttributes = autoAttributes
        self.posthogSessionId = posthogSessionId; self.posthogDistinctId = posthogDistinctId; self.resume = resume
        self.appearance = appearance; self.timeout = timeout
        self.baseURL = baseURL; self.slug = slug; self.uid = uid; self.variant = variant; self.locale = locale
        self.hidden = hidden; self.prefill = prefill; self.includeAnswers = includeAnswers; self.showClose = showClose
    }

    /// `<baseURL>/embed/<slug>?native=1&uid=&variant=&lang=&answers=1&close=1&hidden.x=&prefill.y=` with every value percent-encoded.
    public var url: URL {
        var q = ["native=1"]
        if let uid = uid, !uid.isEmpty { q.append("uid=\(FormFlowConfig.enc(uid))") }
        if let sig = uidSignature, !sig.isEmpty { q.append("uid_sig=\(FormFlowConfig.enc(sig))") }
        if let v = variant, !v.isEmpty { q.append("variant=\(FormFlowConfig.enc(v))") }
        if let l = locale, !l.isEmpty { q.append("lang=\(FormFlowConfig.enc(l))") }
        if includeAnswers { q.append("answers=1") }
        if showClose { q.append("close=1") }
        if resume == false { q.append("resume=0") }
        if let s = posthogSessionId, !s.isEmpty { q.append("ph_session=\(FormFlowConfig.enc(s))") }
        if let d = posthogDistinctId, !d.isEmpty { q.append("ph_distinct=\(FormFlowConfig.enc(d))") }
        if let a = appearance {
            if let c = a.colorScheme { q.append("scheme=\(FormFlowConfig.enc(c.rawValue))") }
            if let c = a.accent { q.append("accent=\(FormFlowConfig.enc(c))") }
            if let f = a.fontFamily { q.append("font=\(FormFlowConfig.enc(f))") }
        }
        for (k, v) in hidden.sorted(by: { $0.key < $1.key }) { q.append("hidden.\(FormFlowConfig.enc(k))=\(FormFlowConfig.enc(v))") }
        for (k, v) in prefill.sorted(by: { $0.key < $1.key }) { q.append("prefill.\(FormFlowConfig.enc(k))=\(FormFlowConfig.enc(v))") }
        for (k, v) in resolvedAttributes.sorted(by: { $0.key < $1.key }) { q.append("attrs.\(FormFlowConfig.enc(k))=\(FormFlowConfig.enc(v))") }
        var base = baseURL.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        return URL(string: "\(base)/embed/\(FormFlowConfig.enc(slug))?\(q.joined(separator: "&"))")!
    }

    public var resolvedAttributes: [String: String] {
        (autoAttributes ? FormFlowConfig.deviceAttributes() : [:]).merging(attributes) { _, mine in mine }
    }

    static func deviceAttributes() -> [String: String] {
        var a = ["platform": "ios", "locale": Locale.current.identifier]
        #if canImport(UIKit)
        a["os_version"] = UIDevice.current.systemVersion
        #endif
        var sys = utsname(); uname(&sys)
        let model = withUnsafePointer(to: &sys.machine) { $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) } }
        a["device_model"] = model
        if let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String { a["app_version"] = v }
        return a
    }

    static func enc(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    /// Only the configured host may load inside the web view.
    public func isAllowed(_ url: URL) -> Bool {
        if url.absoluteString == "about:blank" { return true }
        guard let h = url.host?.lowercased(), let b = baseURL.host?.lowercased() else { return false }
        return h == b
    }
}

public struct FormFlowAppearance {
    public enum ColorScheme: String { case light, dark, system }
    public var colorScheme: ColorScheme?
    /// `#rrggbb`
    public var accent: String?
    public var fontFamily: String?
    public init(colorScheme: ColorScheme? = nil, accent: String? = nil, fontFamily: String? = nil) {
        self.colorScheme = colorScheme; self.accent = accent; self.fontFamily = fontFamily
    }
}
