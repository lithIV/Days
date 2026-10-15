import SwiftUI

struct NewTimerView: View {
    @Environment(TimerStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    // Remember the last custom duration, like the Clock app does.
    @AppStorage("lastHours") private var hours = 0
    @AppStorage("lastMinutes") private var minutes = 5
    @AppStorage("lastSeconds") private var seconds = 0
    @State private var label = ""

    private var total: TimeInterval { TimeInterval(hours * 3600 + minutes * 60 + seconds) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 0) {
                        wheel($hours, range: 0..<24, unit: "hr")
                        wheel($minutes, range: 0..<60, unit: "min")
                        wheel($seconds, range: 0..<60, unit: "sec")
                    }
                    .frame(height: 200)
                }
                Section {
                    TextField("Label (optional)", text: $label)
                        .submitLabel(.done)
                }
            }
            .navigationTitle("New Timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        store.start(duration: total, label: label)
                        dismiss()
                    }
                    .bold()
                    .disabled(total == 0)
                }
            }
        }
    }

    private func wheel(_ selection: Binding<Int>, range: Range<Int>, unit: String) -> some View {
        HStack(spacing: 2) {
            Picker(unit, selection: selection) {
                ForEach(range, id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.wheel)
            .frame(minWidth: 0, maxWidth: .infinity)
            .clipped()
            Text(unit)
                .font(.headline)
                .fixedSize()
        }
        .frame(maxWidth: .infinity)
    }
}
