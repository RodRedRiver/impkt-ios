import SwiftUI

@main
struct IMPKTApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

extension Color {
    /// The brand crimson, the same hex the site and the page use.
    ///
    /// #C41E3A is `--red` in css/impkt.css and it is the one accent this company
    /// has. Written out here rather than added to the asset catalog because it is
    /// one colour with no dark variant to carry: the page has no dark mode, on
    /// the stated grounds that it is one page a person opens once, and a tab bar
    /// that went dark over a permanently white web view would be the app
    /// disagreeing with itself.
    static let impktRed = Color(red: 0xC4 / 255, green: 0x1E / 255, blue: 0x3A / 255)
}

/// Two tabs, and no more than two on purpose. Everything a pilot does is in the
/// page, which already guides them step by step; the second tab exists because
/// updating firmware is the one job the page cannot do and should not look like
/// part of a training session.
struct RootView: View {
    var body: some View {
        TabView {
            // Inside the safe area, top and bottom. It used to run under the tab
            // bar so the page's white background reached the bottom of the
            // screen, and that was fine while the page was one locked screen with
            // nothing at the bottom of it. The page scrolls on a phone now, and a
            // scrolling page under a tab bar ends with its last card and its
            // button behind the bar for as long as the pilot is at the bottom of
            // it. The background is white either way.
            PilotPage()
                .tabItem { Label("Test", systemImage: "figure.boxing") }

            UpdateView()
                .tabItem { Label("Update", systemImage: "arrow.down.circle") }
        }
        // The two tabs were system blue, which is the accent of an app that has
        // not chosen one. Sitting directly under a page whose every button is
        // #C41E3A, that reads as somebody else's chrome bolted to the bottom of
        // our screen — most obviously on the activation screen, where the tab bar
        // is one of about four coloured things on the display.
        //
        // Set on the TabView rather than on each tab, so it reaches the Update
        // screen's own buttons through the environment as well. The page needs
        // nothing: it is already the right colour and always was.
        .tint(.impktRed)
    }
}
