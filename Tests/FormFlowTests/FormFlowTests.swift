import XCTest
@testable import FormFlow

final class FormFlowTests: XCTestCase {
    func testUrlEncodesEverything() {
        let c = FormFlowConfig(baseURL: URL(string: "https://f.example.com/")!, slug: "on boarding", uid: "u 1&x", variant: "v2", locale: "de",
                               hidden: ["plan": "pro/1"], prefill: ["email": "a+b@c.co"], includeAnswers: true, autoAttributes: false)
        XCTAssertEqual(c.url.absoluteString, "https://f.example.com/embed/on%20boarding?native=1&uid=u%201%26x&variant=v2&lang=de&answers=1&hidden.plan=pro%2F1&prefill.email=a%2Bb%40c.co")
    }

    func testAnswersOffByDefault() {
        let c = FormFlowConfig(baseURL: URL(string: "https://f.co")!, slug: "x", autoAttributes: false)
        XCTAssertEqual(c.url.absoluteString, "https://f.co/embed/x?native=1")
    }

    func testNavigationAllowList() {
        let c = FormFlowConfig(baseURL: URL(string: "https://f.example.com")!, slug: "x")
        XCTAssertTrue(c.isAllowed(URL(string: "https://f.example.com/embed/x")!))
        XCTAssertFalse(c.isAllowed(URL(string: "https://f.example.com.evil.com/")!))
        XCTAssertFalse(c.isAllowed(URL(string: "https://evil.com/")!))
    }

    func testParseReady() {
        let json = #"{"source":"formflow","type":"ready","formId":"f1","data":{"formId":"f1","versionId":"v9","experimentId":"e1","variantId":"b","locale":"en"}}"#
        XCTAssertEqual(FormFlowEvent.parse(json), .ready(formId: "f1", versionId: "v9", experimentId: "e1", variantId: "b", locale: "en"))
    }

    func testParseStepAndAnswerFromDictionary() {
        let step: [String: Any] = ["source": "formflow", "type": "step", "formId": "f", "data": ["index": 2, "fieldId": "a", "total": 5]]
        XCTAssertEqual(FormFlowEvent.parse(step), .step(index: 2, fieldId: "a", total: 5))
        let ans: [String: Any] = ["source": "formflow", "type": "answer", "formId": "f", "data": ["fieldId": "a", "type": "short_text"]]
        XCTAssertEqual(FormFlowEvent.parse(ans), .answer(fieldId: "a", type: "short_text", value: nil))
        let val: [String: Any] = ["source": "formflow", "type": "answer", "formId": "f", "data": ["fieldId": "a", "type": "short_text", "value": "hi"]]
        XCTAssertEqual(FormFlowEvent.parse(val), .answer(fieldId: "a", type: "short_text", value: .string("hi")))
    }

    func testParseComplete() {
        let json = #"{"source":"formflow","type":"complete","formId":"f","data":{"submissionId":"s1","outcome":{"passed":true,"endingId":"end"},"endingId":"end","durationMs":1200}}"#
        XCTAssertEqual(FormFlowEvent.parse(json), .complete(submissionId: "s1", outcome: FormFlowOutcome(passed: true, outcomeId: nil, endingId: "end"), endingId: "end", durationMs: 1200, answers: nil))
    }

    func testIgnoresForeignAndFoldedMessages() {
        XCTAssertNil(FormFlowEvent.parse("garbage"))
        XCTAssertNil(FormFlowEvent.parse(#"{"source":"other","type":"close"}"#))
        XCTAssertNil(FormFlowEvent.parse(#"{"source":"formflow","type":"submit","data":{}}"#))
        XCTAssertEqual(FormFlowEvent.parse(#"{"source":"formflow","type":"close","formId":"f","data":{}}"#), .close)
    }

    func testIdentityAppearanceAndAttributes() {
        let c = FormFlowConfig(baseURL: URL(string: "https://f.co")!, slug: "x", uid: "u", uidSignature: "ab/c=",
                               attributes: ["plan": "pro"], autoAttributes: false, posthogSessionId: "s1", posthogDistinctId: "d1", resume: false,
                               appearance: FormFlowAppearance(colorScheme: .dark, accent: "#112233", fontFamily: "Inter"))
        XCTAssertEqual(c.url.absoluteString, "https://f.co/embed/x?native=1&uid=u&uid_sig=ab%2Fc%3D&resume=0&ph_session=s1&ph_distinct=d1&scheme=dark&accent=%23112233&font=Inter&attrs.plan=pro")
    }

    func testParseRequestAndCompleteAnswers() {
        let r = #"{"source":"formflow","type":"request","formId":"f","data":{"requestId":"r1","action":"notifications","params":{"topic":"news"}}}"#
        XCTAssertEqual(FormFlowEvent.parse(r), .request(FormFlowRequest(requestId: "r1", action: "notifications", params: ["topic": "news"])))
        let c = #"{"source":"formflow","type":"complete","formId":"f","data":{"submissionId":"s","outcome":{},"answers":{"a":"x","n":3,"ok":true,"m":["p","q"]}}}"#
        guard case let .complete(_, _, _, _, answers)? = FormFlowEvent.parse(c) else { return XCTFail() }
        XCTAssertEqual(answers?["a"], .string("x"))
        XCTAssertEqual(answers?["n"], .number(3))
        XCTAssertEqual(answers?["ok"], .bool(true))
        XCTAssertEqual(answers?["m"], .array([.string("p"), .string("q")]))
    }

    func testDecisionDecodeAndConfig() throws {
        let data = #"{"data":{"show":true,"experimentId":"e","variantId":"b","slug":"onb","reason":"variant"}}"#.data(using: .utf8)!
        let d = try FormFlowClient.decode(data)
        let base = FormFlowConfig(baseURL: URL(string: "https://f.co")!, slug: "", autoAttributes: false)
        XCTAssertEqual(d.config(from: base)?.variant, "b")
        XCTAssertEqual(d.config(from: base)?.slug, "onb")
        let holdout = try FormFlowClient.decode(#"{"show":false,"reason":"holdout"}"#.data(using: .utf8)!)
        XCTAssertNil(holdout.config(from: base))
    }
}
