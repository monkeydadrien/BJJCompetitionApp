import SwiftUI

struct SettingsRootView: View {

    @Environment(HomeCityStore.self) private var homeCityStore

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        HomeCityEditView()
                    } label: {
                        HStack(spacing: Spacing.md) {
                            Image(systemName: "house.fill")
                                .foregroundStyle(.accent)
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
                } header: {
                    Text("Location")
                } footer: {
                    Text("Used to filter Events by distance from home.")
                        .font(.caption)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground.ignoresSafeArea())
            .tint(.accent)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .appNavigationBar()
        }
    }
}
