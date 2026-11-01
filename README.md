# FormFlow for iOS

[![CI](https://github.com/formizeflow/formflow-ios/actions/workflows/ci.yml/badge.svg)](https://github.com/formizeflow/formflow-ios/actions/workflows/ci.yml)

Swift Package for showing FormFlow forms in a `WKWebView`. iOS 15+. No credentials in the app.

Add the package: Xcode, File, Add Package Dependencies, `https://github.com/formizeflow/formflow-ios`. Or in `Package.swift`: `.package(url: "https://github.com/formizeflow/formflow-ios", from: "0.1.0")`.

## Onboarding on first launch (SwiftUI)

```swift
import SwiftUI
import FormFlow

struct Onboarding: View {
    @AppStorage("onboarded") var onboarded = false
    let userId: String

    var body: some View {
        let config = FormFlowConfig(
            baseURL: URL(string: "https://forms.example.com")!,
            slug: "app-onboarding",
            uid: userId,
            hidden: ["app_version": "3.2.0", "platform": "ios"],
            showClose: true
        )
        FormFlowView(config: config,
                     onComplete: { _, _, _, _, _ in onboarded = true },
                     onClose: { onboarded = true })
            .ignoresSafeArea()
    }
}
// RootView: if !onboarded { Onboarding(userId: user.id) } else { Home() }
```

## UIKit

```swift
let vc = FormFlowViewController(config: config, delegate: self)
vc.handlers.onComplete = { id, outcome, ending, ms, answers in ... }
present(vc, animated: true)

extension MyVC: FormFlowDelegate {
    func formFlow(didReceive event: FormFlowEvent) { ... }
}
```

## Events

`ready(formId, versionId, experimentId, variantId, locale)`, `view`, `start`, `step(index, fieldId, total)`, `answer(fieldId, type, value)`, `complete(submissionId, outcome, endingId, durationMs)`, `progress`, `close`, `error`. Answer values are `nil` unless `includeAnswers: true`, and never present for sensitive fields.

Read answers server-side (REST API or the `submission.completed` webhook) and join them on `uid`.

Navigation is limited to the configured host; other http(s) links open in `SFSafariViewController`. The user agent ends with `FormFlowiOS/<version>`.

## Onboarding experiment: decide, preload, fall back

```swift
let client = FormFlowClient(baseURL: URL(string: "https://forms.example.com")!)
let req = FormFlowDecideRequest(entry: "first-launch", uid: user.id, uidSignature: user.formflowSig,
                                attributes: ["plan": user.plan], posthogSessionId: PostHogSDK.shared.getSessionId())

// App start: warm the cache (works offline later).
Task { _ = await client.preload(req) }

// Onboarding step:
Task {
    let base = FormFlowConfig(baseURL: client.baseURL, slug: "", uid: user.id, uidSignature: user.formflowSig,
                              attributes: ["plan": user.plan], includeAnswers: true,
                              posthogSessionId: PostHogSDK.shared.getSessionId(), posthogDistinctId: PostHogSDK.shared.getDistinctId(),
                              appearance: FormFlowAppearance(colorScheme: .system, accent: "#4f46e5"))
    guard let d = try? await client.decide(req), let config = d.config(from: base) else { return finishOnboarding() } // holdout, done, or offline with no cache

    var h = FormFlowHandlers()
    h.onStep = { _, fieldId, _ in if fieldId == "notifications_q" { /* react mid-flow */ } }
    h.onRequest = { r, respond in
        guard r.action == "notifications" else { return respond(.string("unsupported")) }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge]) { ok, _ in respond(.string(ok ? "granted" : "denied")) }
    }
    h.onComplete = { _, _, _, _, answers in save(answers); finishOnboarding() }
    h.onTimeout = finishOnboarding            // 8 s default: never block the app
    h.onClose = finishOnboarding
    let vc = FormFlowViewController(config: config)
    vc.handlers = h
    present(vc, animated: true)
}
```

`FormFlowViewController.preload()` loads the page before it is on screen; `restart()` starts over without saved progress. `uidSignature` is an HMAC of `uid` from your server. In the form, a link like `[Enable notifications](https://example.com/#ff-action=notifications)` triggers `onRequest`.
