import SwiftUI

struct SettingsRootView: View {

    @Environment(HomeCityStore.self) private var homeCityStore

    var body: some View {
        NavigationStack {
            List {
                Section("Location") {
                    NavigationLink {
                        HomeCityEditView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "house.fill")
                                .foregroundStyle(.gold)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Home City")
                                    .foregroundStyle(.primary)
                                Text(homeCityStore.city?.label ?? "Not set")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } footer: {
                    Text("Used to filter Events by distance from home.")
                        .font(.caption)
                }
            }
            .tint(.gold)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.appBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}
