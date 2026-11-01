#if canImport(UIKit) && canImport(WebKit)
import UIKit
import WebKit
import SafariServices

public final class FormFlowViewController: UIViewController, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    public let config: FormFlowConfig
    public weak var delegate: FormFlowDelegate?
    public var handlers = FormFlowHandlers()
    private var webView: WKWebView!
    private var ready = false
    private var timer: Timer?
    private var fresh = false

    public init(config: FormFlowConfig, delegate: FormFlowDelegate? = nil) {
        self.config = config; self.delegate = delegate
        super.init(nibName: nil, bundle: nil)
    }
    public required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override func loadView() {
        let c = WKWebViewConfiguration()
        c.applicationNameForUserAgent = formFlowUserAgentSuffix
        c.userContentController.add(WeakHandler(self), name: "formflow")
        let w = WKWebView(frame: .zero, configuration: c)
        w.navigationDelegate = self
        w.uiDelegate = self
        w.scrollView.bounces = false
        w.scrollView.contentInsetAdjustmentBehavior = .never // the page handles safe areas itself
        w.isOpaque = false
        w.backgroundColor = .clear
        webView = w
        view = w
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        load()
    }

    private func load() {
        ready = false
        var c = config
        if fresh { c.resume = false }
        webView.load(URLRequest(url: c.url))
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: config.timeout, repeats: false) { [weak self] _ in self?.timedOut() }
    }

    private func timedOut() { if !ready { ready = true; handlers.onTimeout?() } }

    /// Load the form now (view not on screen yet) so it shows instantly later. Call before presenting.
    public func preload() { loadViewIfNeeded() }

    /// Start over, ignoring saved progress.
    public func restart() { fresh = true; loadViewIfNeeded(); load() }

    /// Answer a `request` event (done for you when you use `handlers.onRequest`).
    public func respond(requestId: String, result: FormFlowValue) {
        let msg: [String: Any] = ["type": "respond", "requestId": requestId, "result": result.jsonObject]
        guard let d = try? JSONSerialization.data(withJSONObject: msg), let json = String(data: d, encoding: .utf8),
              let lit = try? JSONSerialization.data(withJSONObject: [json]), let arr = String(data: lit, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.FormFlow&&window.FormFlow.native&&window.FormFlow.native.receive(\(arr)[0]);", completionHandler: nil)
    }


    deinit { timer?.invalidate(); webView?.configuration.userContentController.removeScriptMessageHandler(forName: "formflow") }

    public func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let e = FormFlowEvent.parse(message.body) else { return }
        if case .ready = e { ready = true; timer?.invalidate() }
        if case let .request(r) = e, let h = handlers.onRequest { h(r) { [weak self] v in self?.respond(requestId: r.requestId, result: v) } }
        handlers.dispatch(e)
        delegate?.formFlow(didReceive: e)
    }

    public func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { return decisionHandler(.cancel) }
        if config.isAllowed(url) { return decisionHandler(.allow) }
        if let s = url.scheme?.lowercased(), s == "http" || s == "https" {
            present(SFSafariViewController(url: url), animated: true)
        }
        decisionHandler(.cancel)
    }

    // target=_blank links
    public func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url, let s = url.scheme?.lowercased(), s == "http" || s == "https" { present(SFSafariViewController(url: url), animated: true) }
        return nil
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { report(error) }
    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { report(error) }
    private func report(_ error: Error) {
        let e = FormFlowEvent.error(message: error.localizedDescription)
        handlers.dispatch(e); delegate?.formFlow(didReceive: e)
        timedOut()
    }
}

/// WKUserContentController retains its handlers; keep the controller out of the cycle.
private final class WeakHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ t: WKScriptMessageHandler) { target = t }
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) { target?.userContentController(c, didReceive: m) }
}
#endif
