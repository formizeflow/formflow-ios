#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI

/// SwiftUI wrapper: `FormFlowView(config: ..., onComplete: { ... })`.
public struct FormFlowView: UIViewControllerRepresentable {
    public var config: FormFlowConfig
    public var handlers: FormFlowHandlers

    public init(config: FormFlowConfig, handlers: FormFlowHandlers = FormFlowHandlers()) {
        self.config = config; self.handlers = handlers
    }

    public init(config: FormFlowConfig,
                onReady: ((String, String?, String?, String?, String) -> Void)? = nil,
                onStart: (() -> Void)? = nil,
                onStep: ((Int, String, Int) -> Void)? = nil,
                onAnswer: ((String, String, FormFlowValue?) -> Void)? = nil,
                onComplete: ((String, FormFlowOutcome, String?, Int?, [String: FormFlowValue]?) -> Void)? = nil,
                onClose: (() -> Void)? = nil,
                onError: ((String) -> Void)? = nil,
                onTimeout: (() -> Void)? = nil,
                onRequest: ((FormFlowRequest, @escaping (FormFlowValue) -> Void) -> Void)? = nil) {
        var h = FormFlowHandlers()
        h.onReady = onReady; h.onStart = onStart; h.onStep = onStep; h.onAnswer = onAnswer
        h.onComplete = onComplete; h.onClose = onClose; h.onError = onError; h.onTimeout = onTimeout; h.onRequest = onRequest
        self.init(config: config, handlers: h)
    }

    public func makeUIViewController(context: Context) -> FormFlowViewController {
        let vc = FormFlowViewController(config: config)
        vc.handlers = handlers
        return vc
    }

    public func updateUIViewController(_ vc: FormFlowViewController, context: Context) { vc.handlers = handlers }
}
#endif
