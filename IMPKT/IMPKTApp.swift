import SwiftUI

@main
struct IMPKTApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
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
    }
}
