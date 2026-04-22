import SwiftUI

struct ContentView: View {
    var body: some View {
        // iOS 26 Tab API — gives the tab bar Liquid Glass treatment, the
        // minimize-on-scroll behavior, and proper Search-tab integration in
        // the future. The legacy `.tabItem { Label(...) }` form still works
        // but doesn't pick up the new glass material.
        TabView {
            Tab("Events", systemImage: "calendar") {
                EventsListView()
            }

            Tab("Matches", systemImage: "rectangle.split.3x1.fill") {
                MatchesRootView()
            }

            Tab("My Team", systemImage: "person.3.fill") {
                TrackingRootView()
            }

            Tab("My Divisions", systemImage: "person.fill") {
                DivisionPickerView()
            }

            Tab("Settings", systemImage: "gearshape.fill") {
                SettingsRootView()
            }
        }
        .tint(.accent)
        .background(Color.appBackground.ignoresSafeArea())
    }
}
