import SwiftUI

struct DivisionPickerView: View {

    @Environment(DivisionsStore.self) private var store
    @State private var showingAdd = false

    var body: some View {
        NavigationStack {
            List {
                if store.myDivisions.isEmpty {
                    ContentUnavailableView {
                        Label("No Divisions Added", systemImage: "person.badge.plus")
                    } description: {
                        Text("Add your age group, belt, and weight class so events can highlight athletes in your division.")
                    } actions: {
                        Button {
                            showingAdd = true
                        } label: {
                            Label("Add Division", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.accent)
                    }
                } else {
                    ForEach(store.myDivisions) { div in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(div.belt)
                                .font(.headline)
                            Text("\(div.ageDivision) · \(div.gender) · \(div.weightClass)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { store.myDivisions.remove(atOffsets: $0) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground.ignoresSafeArea())
            .tint(.accent)
            .navigationTitle("My Divisions")
            .navigationBarTitleDisplayMode(.inline)
            .appNavigationBar()
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingAdd = true } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add division")
                }
                if !store.myDivisions.isEmpty {
                    ToolbarItem(placement: .navigationBarLeading) {
                        EditButton()
                    }
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddDivisionSheet()
            }
        }
    }
}

// MARK: - Add sheet

struct AddDivisionSheet: View {

    @Environment(DivisionsStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var gender      = DivisionsStore.genders[0]
    @State private var ageDivision = DivisionsStore.ageDivisions[1]  // Adult
    @State private var belt        = DivisionsStore.belts[2]          // PURPLE
    @State private var weightClass = DivisionsStore.weightClasses[4]  // Middle

    var body: some View {
        NavigationStack {
            Form {
                Picker("Gender", selection: $gender) {
                    ForEach(DivisionsStore.genders, id: \.self) { Text($0) }
                }
                Picker("Age Division", selection: $ageDivision) {
                    ForEach(DivisionsStore.ageDivisions, id: \.self) { Text($0) }
                }
                Picker("Belt", selection: $belt) {
                    ForEach(DivisionsStore.belts, id: \.self) { Text($0) }
                }
                Picker("Weight Class", selection: $weightClass) {
                    ForEach(DivisionsStore.weightClasses, id: \.self) { Text($0) }
                }
            }
            .navigationTitle("Add Division")
            .navigationBarTitleDisplayMode(.inline)
            .appNavigationBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let div = MyDivision(
                            gender: gender,
                            ageDivision: ageDivision,
                            belt: belt,
                            weightClass: weightClass
                        )
                        if !store.myDivisions.contains(div) {
                            store.myDivisions.append(div)
                        }
                        dismiss()
                    }
                }
            }
        }
    }
}
