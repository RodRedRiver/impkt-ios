import SwiftUI
import UIKit

@main
struct IMPKTApp: App {

    /// The bars are painted before the first screen exists, which is why this is in
    /// init and not in a view: an appearance proxy applies to bars created after it
    /// is set, and the tab bar is created with the first screen.
    ///
    /// The leaderboard starts listening here too, and for a related reason: it has to be
    /// counting punches before anybody opens its tab. A gym connects the band on the Test
    /// tab, and the punch thrown to check the band is awake is thrown there. A screen
    /// that only starts counting when it is looked at would lose it.
    init() {
        IMPKTApp.paintTheBars()
        Leaderboard.shared.listen()
    }

    var body: some Scene {
        WindowGroup { RootView() }
    }

    /// The bar at the top of a screen and the bar along the bottom of every screen,
    /// painted the page's own colour.
    ///
    /// Both are white by default, and white against a #f5f5f7 page does not read as a
    /// bar at all: it reads as a thick border drawn around the content, top and
    /// bottom, which is what they were called the day they were noticed. Opaque, and
    /// the same appearance for the scroll edge as for the standard state, so nothing
    /// changes colour as a list slides under it.
    ///
    /// The tab bar keeps the hairline the system draws above it and the title bar
    /// does not get one until something has scrolled under it, which is where iOS
    /// puts them and, with every surface flat, the only thing left separating a bar
    /// from the page.
    private static func paintTheBars() {
        let canvas = UIColor(Color.pageCanvas)

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = canvas
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = canvas
        let edge = UINavigationBarAppearance()
        edge.configureWithOpaqueBackground()
        edge.backgroundColor = canvas
        edge.shadowColor = nil
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = edge
    }
}

extension Color {
    /// The brand crimson, the same hex the site and the page use.
    static let impktRed = Color(red: 0xC4 / 255, green: 0x1E / 255, blue: 0x3A / 255)

    /// The canvas: `--frost` in css/pilot.css, and what the page sets `body` to.
    ///
    /// Declared here rather than in the asset catalog for the same reason as the red.
    /// There is no dark variant to carry, because the page has no dark variant: it is
    /// a white product on a light grey ground, which is also why the app asks for the
    /// light appearance in Info.plist. A colour with one value is a constant.
    static let pageCanvas = Color(red: 0xF5 / 255, green: 0xF5 / 255, blue: 0xF7 / 255)
}

/// The frosted capsule the page's buttons are: translucent, blurring what is behind it, with a thin
/// light rim and dark type. Matte, no gloss and no colour. Pressing springs it in.
struct FrostedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.primary)
            .background(.ultraThinMaterial, in: Capsule())
            .background(Color.impktRed.opacity(configuration.isPressed ? 0.20 : 0.14), in: Capsule())
            .overlay(
                Capsule().strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.8), Color.white.opacity(0.18), Color.white.opacity(0.5)],
                        startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 12, y: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.32, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension View {
    /// A list that sits on the page's canvas instead of the system's grouped grey.
    ///
    /// iOS paints a grouped list #F2F2F7, which is three units off the page's
    /// #F5F5F7: invisible on its own, and not invisible once the tab bar carries the
    /// page's colour across the bottom of every screen. One ground behind everything
    /// is the whole idea, so the lists join it rather than nearly joining it.
    func onCanvas() -> some View {
        scrollContentBackground(.hidden).background(Color.pageCanvas)
    }
}

/// Four tabs and a door. The first tab is the page, which is still the product; the
/// other three are each a job the page cannot do from inside a web view. Beta, in the
/// middle of the bar, is the door: it opens the next app, on the same wraps, full screen
/// for the people testing it. See `betaMode`.
///
/// Leaderboard is one band, a queue of people and the hardest punch of the session,
/// which is what a gym asks for within a minute of being handed a band and is a
/// different shape from a drill: no profile, no plan, no recording, one name at a time.
/// Devices says what the phone can hear right now, which the page only shows while it
/// happens to be looking for something, and it is also where a wrap is updated over
/// Bluetooth, which no browser can do. Profile says what is stored on this phone, and
/// holds the privacy policy.
struct RootView: View {
    /// The tab on screen. Held here, not by the TabView, so that something other than a tap can
    /// change it: the page asks for Devices when there is no wrap to run a drill with.
    @State private var tab = 0

    /// Beta mode: the next app, full screen, over everything else.
    ///
    /// Not a tab. The beta app has its own bar along the bottom, and a tab of it sat on top
    /// of this one, two bars stacked. So the Beta item in the bar is a door rather than a
    /// place: pressing it covers the app with the beta, and the way out is the beta's own
    /// Settings, which is where a tester looks for it. Remembered across launches, so a
    /// tester who closed the app in the beta opens it in the beta.
    ///
    /// The tabs stay alive underneath, and have to: the Test tab's page holds the link to
    /// the wraps, and the beta's punches come off that link.
    @AppStorage("impkt.betaMode") private var betaMode = false

    private static let tabs = ["test": 0, "leaderboard": 2, "devices": 3, "profile": 4]

    /// The bar's selection, with the Beta item turned into entering beta mode. The tab on
    /// screen does not change, so leaving the beta lands back where it was entered from.
    private var selection: Binding<Int> {
        Binding(get: { tab }, set: { next in
            if next == 1 { betaMode = true } else { tab = next }
        })
    }

    var body: some View {
        TabView(selection: selection) {
            // Inside the safe area, top and bottom, so nothing the page draws slides
            // under the clock or behind the tab bar. What that leaves is a band above
            // the page and a band below it, and both are painted the page's own
            // canvas here. They were the window's white, and against #f5f5f7 a white
            // band does not read as the edge of the screen, it reads as a thick
            // border around the page.
            PilotPage()
                .background(Color.pageCanvas)
                .tabItem { Label("Test", systemImage: "figure.boxing") }
                .tag(0)

            // Never on screen: choosing it enters beta mode instead. See `selection`.
            Color.pageCanvas
                .tabItem { Label("Beta", systemImage: "flask") }
                .tag(1)

            LeaderboardView()
                .tabItem { Label("Leaderboard", systemImage: "trophy") }
                .tag(2)

            DevicesView()
                .tabItem { Label("Devices", systemImage: "dot.radiowaves.left.and.right") }
                .tag(3)

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(4)
        }
        .tint(.impktRed)
        // Edge to edge, under the clock and the home indicator, so it is one surface
        // rather than a page in a frame. The beta app keeps its own content clear of both.
        .fullScreenCover(isPresented: $betaMode) {
            BetaPage().ignoresSafeArea()
        }
        .onReceive(NotificationCenter.default.publisher(for: .impktOpenTab)) { note in
            guard let name = note.userInfo?["tab"] as? String else { return }
            if name == "beta" { betaMode = true; return }
            if let index = RootView.tabs[name] {
                // A tab is under the beta, so asking for one is asking to leave it.
                betaMode = false
                tab = index
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .impktExitBeta)) { _ in
            betaMode = false
        }
    }
}

extension Notification.Name {
    /// The page asking the app to show one of its tabs. userInfo["tab"] is "devices", "profile" and so on.
    static let impktOpenTab = Notification.Name("impkt.openTab")
    /// The beta app's Leave beta, from its Settings.
    static let impktExitBeta = Notification.Name("impkt.exitBeta")
}
