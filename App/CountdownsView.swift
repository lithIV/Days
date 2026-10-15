import SwiftUI
import PhotosUI

struct CountdownsView: View {
    @Environment(CountdownStore.self) private var store
    @State private var editing: Countdown?
    @State private var creating = false
    @State private var selecting = false
    @State private var selected: Set<Countdown.ID> = []
    @State private var pendingDelete: Set<Countdown.ID> = []

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
                            .overlay(alignment: .topTrailing) {
                                if selecting {
                                    checkmark(selected.contains(next.id), onCard: true).padding(18)
                                }
                            }
                            .opacity(selecting && !selected.contains(next.id) ? 0.6 : 1)
                            .onTapGesture { tap(next) }
                            .modifier(RowActions(countdown: next, actions: self))
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
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
                .animation(.default, value: selecting)
                .animation(.default, value: store.countdowns.map(\.id))
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
            .navigationTitle(selecting ? selectionTitle : "Countdowns")
            .toolbar { toolbar }
            .toolbar(selecting ? .hidden : .visible, for: .tabBar)
            .sheet(isPresented: $creating) {
                EditCountdownView(countdown: nil)
            }
            .sheet(item: $editing) { countdown in
                EditCountdownView(countdown: countdown)
            }
            .confirmationDialog(deleteTitle, isPresented: Binding(
                get: { !pendingDelete.isEmpty },
                set: { if !$0 { pendingDelete = [] } }
            ), titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    store.delete(pendingDelete)
                    selected.subtract(pendingDelete)
                    pendingDelete = []
                    if selected.isEmpty { selecting = false }
                }
            }
            .onChange(of: store.countdowns.isEmpty) { _, empty in
                if empty { selecting = false; selected = [] }
            }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        if selecting {
            ToolbarItem(placement: .topBarLeading) {
                let all = Set(store.countdowns.map(\.id))
                Button(selected == all ? "Deselect All" : "Select All") {
                    selected = selected == all ? [] : all
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { stopSelecting() }.bold()
            }
            ToolbarItem(placement: .bottomBar) {
                Button(role: .destructive) {
                    pendingDelete = selected
                } label: {
                    Label("Delete", systemImage: "trash")
                        .labelStyle(.titleAndIcon)
                }
                .tint(.red)
                .disabled(selected.isEmpty)
            }
        } else {
            ToolbarItem(placement: .topBarLeading) { AppearanceMenu() }
            ToolbarItem(placement: .topBarTrailing) {
                if !store.countdowns.isEmpty {
                    Button("Select") { selecting = true }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { creating = true } label: { Image(systemName: "plus") }
            }
        }
    }

    private var selectionTitle: String {
        selected.isEmpty ? "Select Items" : "\(selected.count) Selected"
    }

    private var deleteTitle: String {
        pendingDelete.count == 1 ? "Delete this countdown?" : "Delete \(pendingDelete.count) countdowns?"
    }

    private func row(_ countdown: Countdown, now: Date) -> some View {
        HStack(spacing: 12) {
            if selecting {
                checkmark(selected.contains(countdown.id), onCard: false)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            CountdownRow(countdown: countdown, now: now)
        }
        .contentShape(Rectangle())
        .onTapGesture { tap(countdown) }
        .modifier(RowActions(countdown: countdown, actions: self))
    }

    private func checkmark(_ on: Bool, onCard: Bool) -> some View {
        Image(systemName: on ? "checkmark.circle.fill" : "circle")
            .font(.title2)
            .foregroundStyle(on
                ? AnyShapeStyle(onCard ? Color.white : Color.orange)
                : AnyShapeStyle(onCard ? Color.white.opacity(0.9) : Color.secondary))
    }

    // MARK: Actions

    private func tap(_ countdown: Countdown) {
        if selecting {
            if selected.contains(countdown.id) { selected.remove(countdown.id) } else { selected.insert(countdown.id) }
        } else {
            editing = countdown
        }
    }

    fileprivate func edit(_ countdown: Countdown) { editing = countdown }

    fileprivate func startSelecting(with countdown: Countdown) {
        selected = [countdown.id]
        selecting = true
    }

    fileprivate func askDelete(_ countdown: Countdown) { pendingDelete = [countdown.id] }

    fileprivate func deleteNow(_ countdown: Countdown) { store.delete([countdown.id]) }

    fileprivate var isSelecting: Bool { selecting }

    private func stopSelecting() {
        selecting = false
        selected = []
    }
}

/// Long-press menu and swipe actions shared by the hero card and the rows.
private struct RowActions: ViewModifier {
    let countdown: Countdown
    let actions: CountdownsView

    @ViewBuilder func body(content: Content) -> some View {
        if actions.isSelecting {
            content
        } else {
            content
                .contextMenu {
                    Button { actions.edit(countdown) } label: { Label("Edit", systemImage: "pencil") }
                    Button { actions.startSelecting(with: countdown) } label: {
                        Label("Select", systemImage: "checkmark.circle")
                    }
                    Divider()
                    Button(role: .destructive) { actions.askDelete(countdown) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) { actions.deleteNow(countdown) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading) {
                    Button { actions.edit(countdown) } label: { Label("Edit", systemImage: "pencil") }
                        .tint(.orange)
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
            CountdownIcon(countdown: countdown, size: 40)
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
                    .foregroundStyle(isPast ? .secondary : countdown.accent)
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
            HStack(alignment: .top) {
                CountdownIcon(countdown: countdown, size: 36, style: .onCard)
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
        .foregroundStyle(countdown.cardForeground)
        .shadow(color: .black.opacity(countdown.hasBackgroundImage ? 0.4 : 0), radius: 6, y: 1)
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .leading)
        .background { CountdownBackground(countdown: countdown) }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(.vertical, 6)
    }
}

// MARK: - Editor

struct EditCountdownView: View {
    @Environment(CountdownStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private let isNew: Bool
    @State private var draft: Countdown
    @State private var confirmDelete = false
    @State private var photoItem: PhotosPickerItem?
    @State private var backgroundItem: PhotosPickerItem?
    @State private var importTarget: ImportTarget?
    private enum ImportTarget { case icon, background }
    @State private var importFailed = false
    /// Icon files picked during this edit, cleaned up if not kept.
    @State private var pickedFiles: [String] = []

    init(countdown: Countdown?) {
        isNew = countdown == nil
        let nextWeek = Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
        _draft = State(initialValue: countdown ?? Countdown(title: "", date: nextWeek))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HeroCard(countdown: draft, now: .now)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } footer: {
                    Text("Preview — this is how the countdown looks in the app and in a one-countdown widget.")
                }

                Section {
                    HStack(spacing: 14) {
                        CountdownIcon(countdown: draft, size: 44)
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

                Section {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        noColorSwatch
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
                } header: {
                    Text("Color")
                } footer: {
                    Text("Pick the crossed-out circle for no color: just the icon, no background.")
                }

                Section {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Choose from Photos", systemImage: "photo.on.rectangle")
                    }
                    Button {
                        importTarget = .icon
                    } label: {
                        Label("Choose from Files", systemImage: "folder")
                    }
                    if draft.iconFile != nil {
                        Button(role: .destructive) {
                            draft.iconFile = nil
                        } label: {
                            Label("Remove Custom Icon", systemImage: "xmark.circle")
                        }
                    }
                } header: {
                    Text("Custom Icon")
                } footer: {
                    Text("Transparent PNGs keep their transparency. Pick \"No color\" above to show only your image.")
                }

                Section {
                    PhotosPicker(selection: $backgroundItem, matching: .images) {
                        Label(draft.hasBackgroundImage ? "Change Background Photo" : "Choose Background Photo",
                              systemImage: "photo")
                    }
                    Button {
                        importTarget = .background
                    } label: {
                        Label("Choose from Files", systemImage: "folder")
                    }
                    if draft.hasBackgroundImage {
                        LabeledContent("Dim") {
                            Slider(value: Binding(get: { draft.dim }, set: { draft.backgroundDim = $0 }), in: 0...0.8)
                                .frame(maxWidth: 200)
                        }
                        LabeledContent("Blur") {
                            Slider(value: Binding(get: { draft.blur }, set: { draft.backgroundBlur = $0 }), in: 0...20)
                                .frame(maxWidth: 200)
                        }
                        Button(role: .destructive) {
                            draft.backgroundFile = nil
                        } label: {
                            Label("Remove Background", systemImage: "xmark.circle")
                        }
                    }
                } header: {
                    Text("Background")
                } footer: {
                    Text("Fills the whole widget. Dim and blur help the numbers pop; a soft fade at the bottom keeps the title readable.")
                }

                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        if let file = draft.iconFile, let image = IconStore.image(file) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .padding(6)
                                .frame(width: 46, height: 46)
                                .background(iconTileBackground(selected: true),
                                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        ForEach(Countdown.symbols, id: \.self) { symbol in
                            let selected = draft.iconFile == nil && symbol == draft.symbol
                            Image(systemName: symbol)
                                .font(.title3)
                                .frame(width: 46, height: 46)
                                .foregroundStyle(selected && !draft.isColorless ? .white : .primary)
                                .background(iconTileBackground(selected: selected),
                                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .onTapGesture {
                                    draft.symbol = symbol
                                    draft.iconFile = nil
                                }
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
                    Button("Cancel") {
                        cleanUpPickedFiles(keeping: [])
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Add" : "Save") {
                        draft.title = draft.title.trimmingCharacters(in: .whitespaces)
                        cleanUpPickedFiles(keeping: [draft.iconFile, draft.backgroundFile])
                        store.save(draft)
                        dismiss()
                    }
                    .bold()
                    .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Delete this countdown?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    cleanUpPickedFiles(keeping: [])
                    store.delete([draft.id])
                    dismiss()
                }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    useImage(try? await item.loadTransferable(type: Data.self), for: .icon)
                    photoItem = nil
                }
            }
            .onChange(of: backgroundItem) { _, item in
                guard let item else { return }
                Task {
                    useImage(try? await item.loadTransferable(type: Data.self), for: .background)
                    backgroundItem = nil
                }
            }
            .fileImporter(isPresented: Binding(get: { importTarget != nil }, set: { if !$0 { importTarget = nil } }),
                          allowedContentTypes: [.image]) { result in
                let target = importTarget ?? .icon
                guard case .success(let url) = result else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                useImage(try? Data(contentsOf: url), for: target)
            }
            .alert("Couldn't use that image", isPresented: $importFailed) {
                Button("OK", role: .cancel) {}
            }
        }
        .interactiveDismissDisabled(!pickedFiles.isEmpty)
    }

    private var noColorSwatch: some View {
        let selected = draft.isColorless
        return Circle()
            .strokeBorder(Color.secondary, lineWidth: 2)
            .frame(width: 34, height: 34)
            .overlay {
                Rectangle()
                    .fill(Color.red)
                    .frame(width: 2, height: 30)
                    .rotationEffect(.degrees(45))
            }
            .overlay {
                if selected {
                    Circle().strokeBorder(Color.primary, lineWidth: 3).frame(width: 40, height: 40)
                }
            }
            .frame(width: 40, height: 40)
            .contentShape(Circle())
            .onTapGesture { draft.colorName = Countdown.noColor }
    }

    private func iconTileBackground(selected: Bool) -> AnyShapeStyle {
        guard selected else { return AnyShapeStyle(.quaternary) }
        return draft.isColorless ? AnyShapeStyle(.tertiary) : AnyShapeStyle(draft.color.gradient)
    }

    private func useImage(_ data: Data?, for target: ImportTarget) {
        let file = data.flatMap { data in
            target == .background
                ? IconStore.save(data, maxSide: 1000, photo: true)
                : IconStore.save(data)
        }
        guard let file else {
            importFailed = true
            return
        }
        pickedFiles.append(file)
        switch target {
        case .icon: draft.iconFile = file
        case .background: draft.backgroundFile = file
        }
    }

    private func cleanUpPickedFiles(keeping kept: Set<String?>) {
        for file in pickedFiles where !kept.contains(file) { IconStore.delete(file) }
        pickedFiles = []
    }
}
