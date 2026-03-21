import SwiftUI
import WebKit

/// WKWebView wrapper that loads YouTube Shorts with a mobile user-agent
/// for a full vertical reel experience.
struct SmartTVView: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = context.coordinator

        // Register with controller so it can be controlled externally
        SmartTVController.shared.webView = webView

        // If there's a pending search query, go straight to search instead of /shorts
        if let pending = SmartTVController.shared.pendingQuery {
            SmartTVController.shared.searchAndPlay(query: pending)
        } else {
            if let url = URL(string: "https://m.youtube.com/shorts") {
                webView.load(URLRequest(url: url))
            }
        }

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // No dynamic updates needed
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let url = webView.url?.absoluteString ?? ""
            log("SmartTV: didFinish — url=\(url.prefix(80))")

            if url.contains("/results") {
                // On search results page: click the first Shorts result
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    log("SmartTV: clicking first Shorts result")
                    let js = """
                    (function() {
                        var links = document.querySelectorAll('a[href*="/shorts/"]');
                        if (links.length > 0) {
                            links[0].click();
                        }
                    })();
                    """
                    webView.evaluateJavaScript(js)
                }
            } else if url.contains("/shorts/") {
                // On Shorts player page: navigation done, let YouTube autoplay
                SmartTVController.shared.navigationFinished()
                // Ensure video starts muted
                webView.evaluateJavaScript("document.querySelectorAll('video').forEach(v => v.muted = true)")
                log("SmartTV: on Shorts player, navigation finished (muted)")
            } else {
                SmartTVController.shared.navigationFinished()
            }
        }
    }
}
