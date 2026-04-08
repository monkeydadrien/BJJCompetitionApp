import SwiftUI

@main
struct BJJCompanionApp: App {

    @State private var eventsRepo    = EventsRepository()
    @State private var bracketRepo   = BracketRepository()
    @State private var divisionsStore = DivisionsStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(eventsRepo)
                .environment(bracketRepo)
                .environment(divisionsStore)
                .task { await eventsRepo.loadIfNeeded() }
        }
    }
}
