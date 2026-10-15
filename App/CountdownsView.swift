import SwiftUI

struct CountdownsView: View {
    @Environment(CountdownStore.self) private var store
    @State private var editing: Countdown?
    @State private var creating = false

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let now = context.date
                let sorted = store.sorted(at: now)
                let upcoming = sorted.filter { $0.phase(at: now) != .past }
                let past = sorted.filter { $0.phase(at: now) == .past }

                List {
                    if let next = upcoming.first {
                        HeroCard(countdown: next, now: now)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .onTapGesture { editing = next }
                    }
                    if upcoming.count > 1 {
                        Section("Upcoming") {
                            ForEach(upcoming.dropFirst()) { row($0, now: now) }
                        }
                    }
                    if !past.isEmpty {
                        Section("Past") {
                            ForEach(past) { row($0, now: now) }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .overlay {
                    if store.countdowns.isEmpty {
                        ContentUnavailableView {
                            Label("No Countdowns", systemImage: "calendar.badge.clock")
                        } description: {
                            Text("Count down to birthdays, trips, paydays — anything.")
                        } actions: {
                            Button("Add Countdown") { creating = true }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
            .navigationTitle("Countdowns")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { AppearanceMenu() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { creating = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $creating) {
                EditCountdownView(countdown: nil)
            }
            .sheet(item: $editing) { countdown in
                EditCountdownView(countdown: countdown)
            }
        }
    }

    private func row(_ countdown: Countdown, now: Date) -> some View {
        Button { editing = countdown } label: {
            CountdownRow(countdown: countdown, now: now)
        }
        .foregroundStyle(.primary)
        .swipeActions {
            Button(role: .destructive) {
                store.delete(countdown.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

struct CountdownRow: View {
    let countdown: Countdown
    let now: Date

    var body: some View {
        let headline = countdown.headline(at: now)
        let isPast = countdown.phase(at: now) == .past
        HStack(spacing: 14) {
            SymbolBadge(symbol: countdown.symbol, color: countdown.color, size: 40)
                .opacity(isPast ? 0.5 : 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(countdown.title).font(.headline).lineLimit(1)
                Text(countdown.dateText(at: now)).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 0) {
                Text(headline.value)
                    .font(.system(.title, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(isPast ? .secondary : countdown.color)
                if !headline.unit.isEmpty {
                    Text(headline.unit).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// Big card for the soonest countdown.
struct HeroCard: View {
    let countdown: Countdown
    let now: Date

    var body: some View {
        let headline = countdown.headline(at: now)
        let phase = countdown.phase(at: now)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: countdown.symbol).font(.title2)
                Spacer()
                if countdown.repeatsYearly {
                    Image(systemName: "repeat").font(.subheadline).opacity(0.8)
                }
            }
            Spacer(minLength: 12)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(headline.value)
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .contentTransition(.numericText(countsDown: true))
                Text(headline.unit).font(.title3.weight(.semibold)).opacity(0.85)
            }
            Text(countdown.title).font(.title3.weight(.semibold)).lineLimit(2)
            HStack {
                Text(countdown.dateText(at: now))
                Spacer()
                if phase == .upcoming {
                    Text(countdown.breakdown(at: now)).monospacedDigit()
                }
            }
            .font(.subheadline)
            .opacity(0.85)
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .leading)
        .background(countdown.color.gradient, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(.vertical, 6)
    }
}

struct SymbolBadge: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
    }
}

// MARK: - Editor

struct EditCountdownView: View {
    @Environment(CountdownStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private let isNew: Bool
    @State private var draft: Countdown
    @State private var confirmDelete = false

    init(countdown: Countdown?) {
        isNew = countdown == nil
        let tomorrow = Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
        _draft = State(initialValue: countdown ?? Countdown(title: "", date: tomorrow))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        SymbolBadge(symbol: draft.symbol, color: draft.color, size: 44)
                        TextField("Title", text: $draft.title)
                            .font(.title3)
                    }
                }

                Section {
                    DatePicker("Date", selection: $draft.date,
                               displayedComponents: draft.allDay ? [.date] : [.date, .hourAndMinute])
                    Toggle("All day", isOn: $draft.allDay.animation())
                    Toggle("Repeats every year", isOn: $draft.repeatsYearly)
                } footer: {
                    Text("Yearly countdowns roll over to next year once they pass — good for birthdays and holidays.")
                }

                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(Countdown.palette, id: \.name) { item in
                            Circle()
                                .fill(item.color.gradient)
                                .frame(width: 34, height: 34)
                                .overlay {
                                    if item.name == draft.colorName {
                                        Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                                    }
                                }
                                .onTapGesture { draft.colorName = item.name }
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(Countdown.symbols, id: \.self) { symbol in
                            Image(systemName: symbol)
                                .font(.title3)
                                .frame(width: 46, height: 46)
                                .foregroundStyle(symbol == draft.symbol ? .white : .primary)
                                .background(
                                    symbol == draft.symbol ? AnyShapeStyle(draft.color.gradient) : AnyShapeStyle(.quaternary),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                )
                                .onTapGesture { draft.symbol = symbol }
                        }
                    }
                    .padding(.vertical, 6)
                }

                if !isNew {
                    Section {
                        Button("Delete Countdown", role: .destructive) { confirmDelete = true }
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle(isNew ? "New Countdown" : "Edit Countdown")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Add" : "Save") {
                        draft.title = draft.title.trimmingCharacters(in: .whitespaces)
                        store.save(draft)
                        dismiss()
                    }
                    .bold()
                    .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Delete this countdown?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    store.delete(draft.id)
                    dismiss()
                }
            }
        }
    }
}
