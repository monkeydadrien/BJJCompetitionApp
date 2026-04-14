import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            EventsListView()
                .tabItem { Label("Events", systemImage: "calendar") }

            BracketsRootView()
                .tabItem { Label("Brackets", systemImage: "trophy") }

            TrackingRootView()
                .tabItem { Label("My Team", systemImage: "person.3.fill") }

            DivisionPickerView()
                .tabItem { Label("My Divisions", systemImage: "person.fill") }
        }
        .tint(.gold)
        .background(Color.appBackground.ignoresSafeArea())
    }
}
