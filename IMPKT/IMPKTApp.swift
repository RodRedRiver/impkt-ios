import SwiftUI
import UIKit

@main
struct IMPKTApp: App {

    /// The bars are painted before the first screen exists, which is why this is in
    /// init and not in a view: an appearance proxy applies to bars created after it
    /// is set, and the tab bar is created with the first screen.
    init() { IMPKTApp.paintTheBars() }

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

/// Four tabs. The first one is the page, which is still the product; the other three
/// are each a job the page cannot do from inside a web view.
///
/// Update installs firmware over Bluetooth, which no browser can. Devices says what
/// the phone can hear right now, which the page only shows while it happens to be
/// looking for something. Profile says what is stored on this phone and what leaves
/// it, which is worth being able to read without starting a drill to get to it.
struct RootView: View {
    var body: some View {
        TabView {
            // Inside the safe area, top and bottom, so nothing the page draws slides
            // under the clock or behind the tab bar. What that leaves is a band above
            // the page and a band below it, and both are painted the page's own
            // canvas here. They were the window's white, and against #f5f5f7 a white
            // band does not read as the edge of the screen, it reads as a thick
            // border around the page.
            PilotPage()
                .background(Color.pageCanvas)
                .tabItem { Label("Test", systemImage: "figure.boxing") }

            UpdateView()
                .tabItem { Label("Update", systemImage: "arrow.down.circle") }

            DevicesView()
                .tabItem { Label("Devices", systemImage: "dot.radiowaves.left.and.right") }

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
        .tint(.impktRed)
    }
}
