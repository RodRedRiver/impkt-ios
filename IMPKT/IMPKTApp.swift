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
            PilotPage()
                .ignoresSafeArea(edges: .bottom)
                .tabItem { Label("Test", systemImage: "figure.boxing") }

            UpdateView()
                .tabItem { Label("Update", systemImage: "arrow.down.circle") }
        }
    }
}
