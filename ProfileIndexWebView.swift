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

        if let htmlURL = Bundle.module.url(forResource: "index", withExtension: "html") {
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
              document.addEventListener('myEvent', function(e) {
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers['\(escapedName)']) {
                  window.webkit.messageHandlers['\(escapedName)'].postMessage({
                    event: e.type,
                    detail: e.detail || null
                  });
                }
              });
            })();
            """
            return WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        }
    }
}
