import SwiftUI
import WebKit

/// In-app documentation viewer using WKWebView
/// Displays CareKeeper documentation site within the app
struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    /// The documentation URL to load
    /// Can be:
    /// - Remote: https://docs.carekeeper.com
    /// - Local: file:///path/to/site/index.html (for offline testing)
    let documentationURL: URL

    @State private var canGoBack = false
    @State private var canGoForward = false

    /// Coordinator to manage WKWebView navigation delegate
    @StateObject private var webViewCoordinator = WebViewCoordinator()

    init(documentationURL: URL? = nil) {
        // Default to production URL (or local build for development)
        self.documentationURL = documentationURL ?? URL(string: "https://carekeeper.pages.dev")!
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // WebView
                WebView(
                    url: documentationURL,
                    canGoBack: $canGoBack,
                    canGoForward: $canGoForward,
                    coordinator: webViewCoordinator
                )

                // Loading overlay
                if webViewCoordinator.isLoading && webViewCoordinator.error == nil {
                    VStack {
                        ProgressView()
                        Text(NSLocalizedString("Loading documentation...", comment: "Help loading message"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                    }
                }

                // Error state
                if let error = webViewCoordinator.error {
                    errorView(error)
                }
            }
            .navigationTitle(NSLocalizedString("Help", comment: "Help navigation title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("Done", comment: "Close help button")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    navigationButtons
                }
            }
        }
    }

    @ViewBuilder
    private var navigationButtons: some View {
        HStack(spacing: 12) {
            // Back button
            Button(action: { webViewCoordinator.goBack() }) {
                Image(systemName: "chevron.left")
            }
            .disabled(!canGoBack)

            // Forward button
            Button(action: { webViewCoordinator.goForward() }) {
                Image(systemName: "chevron.right")
            }
            .disabled(!canGoForward)

            // Reload button
            Button(action: { webViewCoordinator.reload() }) {
                Image(systemName: "arrow.clockwise")
            }
        }
    }

    @ViewBuilder
    private func errorView(_ error: Error) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.orange)

            Text(NSLocalizedString("Cannot Load Documentation", comment: "Help error title"))
                .font(.title3)
                .fontWeight(.semibold)

            Text(error.localizedDescription)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button(NSLocalizedString("Try Again", comment: "Retry loading help")) {
                webViewCoordinator.reload()
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
}

/// UIViewRepresentable wrapper for WKWebView
struct WebView: UIViewRepresentable {
    let url: URL
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    let coordinator: WebViewCoordinator

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = coordinator
        webView.allowsBackForwardNavigationGestures = true

        // Store webView reference in coordinator
        coordinator.webView = webView

        // Load initial URL
        let request = URLRequest(url: url)
        webView.load(request)

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Update binding states from webView
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
    }
}

/// Coordinator to handle WKWebView navigation events
class WebViewCoordinator: NSObject, WKNavigationDelegate, ObservableObject {
    weak var webView: WKWebView?

    @Published var isLoading = true
    @Published var error: Error?

    // MARK: - Navigation Actions

    func goBack() {
        webView?.goBack()
    }

    func goForward() {
        webView?.goForward()
    }

    func reload() {
        error = nil
        webView?.reload()
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
        error = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isLoading = false
        self.error = error
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        isLoading = false
        self.error = error
    }

    // Handle external links (optional: open in Safari for external domains)
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Allow all navigation for now (documentation is self-contained)
        // In the future, could add logic to open external links in Safari
        decisionHandler(.allow)
    }
}

// MARK: - Preview

#Preview("Help View") {
    HelpView()
}

#Preview("Help View - Custom URL") {
    HelpView(documentationURL: URL(string: "https://carekeeper-docs.pages.dev/tutorials/getting-started/")!)
}
