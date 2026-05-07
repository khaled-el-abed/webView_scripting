import SwiftUI
import WebKit

struct ProfileIndexWebViewScreen: View {
    let title: String
    let listenerName: String
    let onMessage: ((Any) -> Void)?
    @State private var receivedMessageText: String?

    var body: some View {
        ProfileLocalIndexWebView(listenerName: listenerName, onMessage: { payload in
            onMessage?(payload)
            receivedMessageText = stringify(payload)
        })
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .alert("JS Event Received", isPresented: Binding(
                get: { receivedMessageText != nil },
                set: { isPresented in
                    if !isPresented { receivedMessageText = nil }
                }
            )) {
                Button("OK", role: .cancel) {
                    receivedMessageText = nil
                }
            } message: {
                Text(receivedMessageText ?? "")
            }
    }

    private func stringify(_ payload: Any) -> String {
        if let dict = payload as? [String: Any] {
            if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted]),
               let text = String(data: data, encoding: .utf8) {
                return text
            }
        }
        return String(describing: payload)
    }
}

private struct ProfileLocalIndexWebView: UIViewRepresentable {
    let listenerName: String
    let onMessage: ((Any) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(listenerName: listenerName, onMessage: onMessage)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let userContentController = WKUserContentController()
        userContentController.add(context.coordinator, name: listenerName)
        userContentController.addUserScript(context.coordinator.listenerBridgeScript())
        config.userContentController = userContentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator

        if let htmlURL = Bundle.module.url(forResource: "custom_event_demo", withExtension: "html") {
            webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
        } else {
            webView.loadHTMLString("<h3>index.html not found</h3>", baseURL: nil)
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        private let listenerName: String
        private let onMessage: ((Any) -> Void)?

        init(listenerName: String, onMessage: ((Any) -> Void)?) {
            self.listenerName = listenerName
            self.onMessage = onMessage
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == listenerName else { return }
            onMessage?(message.body)
        }

        func listenerBridgeScript() -> WKUserScript {
            let escapedName = listenerName.replacingOccurrences(of: "'", with: "\\'")
            let source = """
            (function() {
              function forwardToNative(e) {
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers['\(escapedName)']) {
                  window.webkit.messageHandlers['\(escapedName)'].postMessage({
                    event: e.type,
                    detail: e.detail || null
                  });
                }
              }
              const interceptedEvents = [
                'myEvent',
                'mySecondEvent',
                'myThirdEvent',
                'myFourthEvent',
                'myFifthEvent',
                'mySixthEvent',
                'mySeventhEvent',
                'myEighthEvent',
                'myNinthEvent',
                'myTenthEvent'
              ];
              for (const eventName of interceptedEvents) {
                document.addEventListener(eventName, forwardToNative);
              }
            })();
            """
            return WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        }
    }
}


let spyScript = """
// Spy on postMessage
const _origPostMessage = window.postMessage.bind(window);
window.postMessage = function(data, origin) {
    window.webkit.messageHandlers.quickSignBridge.postMessage({
        type: "postMessage",
        data: JSON.stringify(data)
    });
    return _origPostMessage(data, origin);
};

// Spy on ALL custom events
const _origDispatch = EventTarget.prototype.dispatchEvent;
EventTarget.prototype.dispatchEvent = function(event) {
    if (event.type !== 'click' && event.type !== 'mousemove') { // filter noise
        window.webkit.messageHandlers.quickSignBridge.postMessage({
            type: "domEvent",
            eventType: event.type,
            detail: JSON.stringify(event.detail ?? null)
        });
    }
    return _origDispatch.call(this, event);
};
"""

let userScript = WKUserScript(
    source: spyScript,
    injectionTime: .atDocumentStart, // must be early
    forMainFrameOnly: false // false catches iframes too
)
config.userContentController.addUserScript(userScript)
config.userContentController.add(weakHandler, name: "quickSignBridge")

// 1. The weak proxy class — prevents retain cycle
class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?

    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}
