import SwiftUI
import WebKit

/// The privacy policy, shown as the document it is.
///
/// It is Resources/privacy.html, the same file the sign-up screen reads, served through the app's own
/// URL scheme so there is no network involved and no second copy of the wording to drift from the
/// first. A web view and not a SwiftUI Text, because the policy has headings, lists and tables and
/// they are already written once, in the one place that has to be right.
struct PolicyView: UIViewRepresentable {

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(BundleFiles(), forURLScheme: PilotPage.scheme)
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = UIColor(Color.pageCanvas)
        web.scrollView.backgroundColor = UIColor(Color.pageCanvas)
        web.load(URLRequest(url: URL(string: "\(PilotPage.scheme)://app/privacy.html")!))
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {}
}
