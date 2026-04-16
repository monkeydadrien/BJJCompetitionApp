import SwiftUI

struct HomeCityEditView: View {

    @Environment(HomeCityStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var query: String = ""
    @State private var isGeocoding   = false
    @State private var errorMessage: String?

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedQuery.isEmpty && !isGeocoding
    }

    var body: some View {
        Form {
            Section {
                TextField("e.g. Houston, TX", text: $query)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit { Task { await save() } }
            } header: {
                Text("City")
            } footer: {
                Text("Try \"City, State\" or include a country for best results.")
                    .font(.caption)
            }

            if let current = store.city {
                Section("Current") {
                    HStack(spacing: 12) {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundStyle(.gold)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(current.label)
                                .foregroundStyle(.primary)
                            Text(String(format: "%.3f, %.3f", current.lat, current.lon))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button(role: .destructive) {
                        store.clear()
                    } label: {
                        Label("Remove home city", systemImage: "trash")
                    }
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
            }
        }
        .tint(.gold)
        .navigationTitle("Home City")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.appBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isGeocoding {
                    ProgressView().tint(.gold)
                } else {
                    Button("Save") { Task { await save() } }
                        .disabled(!canSave)
                }
            }
        }
        .onAppear { query = store.city?.label ?? "" }
    }

    @MainActor
    private func save() async {
        guard canSave else { return }
        errorMessage = nil
        isGeocoding = true
        defer { isGeocoding = false }
        do {
            try await store.setCity(trimmedQuery)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
