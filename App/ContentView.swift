import SwiftUI

struct ContentView: View {
    @Environment(TimerStore.self) private var store
    @AppStorage("appearance") private var appearance: Appearance = .system
    @State private var showingNew = false

    var body: some View {
        NavigationStack {
            List {
                if store.timers.isEmpty {
                    Section {
                        ContentUnavailableView {
                            Label("No Timers", systemImage: "timer")
                        } description: {
                            Text("Tap a quick start below or + to make your own.")
                        }
                    }
                } else {
                    Section("Timers") {
                        ForEach(store.timers) { timer in
                            TimerRow(timer: timer)
                                .swipeActions {
                                    Button(role: .destructive) {
                                        store.remove(timer.id)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }

                Section("Quick Start") {
                    PresetGrid()
                }

                if !store.recents.isEmpty {
                    Section("Recents") {
                        ForEach(store.recents) { preset in
                            RecentRow(preset: preset)
                                .swipeActions {
                                    Button(role: .destructive) {
                                        store.forgetRecent(preset)
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Timers")
            .animation(.default, value: store.timers.map(\.id))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Appearance", selection: $appearance) {
                            ForEach(Appearance.allCases) { Text($0.title).tag($0) }
                        }
                    } label: {
                        Image(systemName: "circle.lefthalf.filled")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingNew = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNew) {
                NewTimerView()
            }
            .safeAreaInset(edge: .bottom) {
                if !store.finished.isEmpty {
                    FinishedBanner()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.35), value: store.finished.isEmpty)
        }
    }
}

// MARK: - Rows

struct TimerRow: View {
    @Environment(TimerStore.self) private var store
    let timer: TimerItem

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            HStack(spacing: 16) {
                ProgressRing(progress: timer.progress(at: context.date), status: timer.status)
                    .frame(width: 50, height: 50)

                VStack(alignment: .leading, spacing: 2) {
                    Text(DurationFormat.clock(timer.remaining(at: context.date)))
                        .font(.system(size: 34, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(timer.status == .paused ? .secondary : .primary)
                        .contentTransition(.numericText(countsDown: true))
                    Text(timer.displayLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
                controls
            }
            .padding(.vertical, 4)
        }
        .contextMenu {
            Button { store.addMinute(timer.id) } label: { Label("+1 Minute", systemImage: "plus.circle") }
            Button { store.restart(timer.id) } label: { Label("Restart", systemImage: "arrow.counterclockwise") }
            Button(role: .destructive) { store.remove(timer.id) } label: { Label("Delete", systemImage: "trash") }
        }
    }

    @ViewBuilder private var controls: some View {
        switch timer.status {
        case .running:
            CircleButton(systemImage: "pause.fill", color: .orange) { store.pause(timer.id) }
        case .paused:
            CircleButton(systemImage: "play.fill", color: .green) { store.resume(timer.id) }
        case .finished:
            HStack(spacing: 10) {
                CircleButton(systemImage: "arrow.counterclockwise", color: .orange) { store.restart(timer.id) }
                CircleButton(systemImage: "xmark", color: .gray) { store.remove(timer.id) }
            }
        }
    }
}

struct RecentRow: View {
    @Environment(TimerStore.self) private var store
    let preset: Preset

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(DurationFormat.clock(preset.duration))
                    .font(.system(.title2, design: .rounded, weight: .light))
                    .monospacedDigit()
                Text(preset.label.isEmpty ? DurationFormat.words(preset.duration) : preset.label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            CircleButton(systemImage: "play.fill", color: .green) {
                store.start(duration: preset.duration, label: preset.label)
            }
        }
    }
}

struct PresetGrid: View {
    @Environment(TimerStore.self) private var store
    private let presets: [TimeInterval] = [60, 180, 300, 600, 900, 1800, 2700, 3600]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(presets, id: \.self) { seconds in
                Button {
                    store.start(duration: seconds)
                } label: {
                    Text(DurationFormat.short(seconds))
                        .font(.system(.headline, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color.orange.opacity(0.16), in: Capsule())
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Pieces

struct ProgressRing: View {
    let progress: Double
    let status: TimerItem.Status

    private var color: Color {
        switch status {
        case .running: .orange
        case .paused: .secondary
        case .finished: .red
        }
    }

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.2), lineWidth: 5)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.25), value: progress)
            if status == .finished {
                Image(systemName: "bell.fill")
                    .foregroundStyle(.red)
                    .symbolEffect(.bounce, options: .repeating)
            }
        }
    }
}

struct CircleButton: View {
    let systemImage: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .bold))
                .frame(width: 44, height: 44)
                .background(color.opacity(0.2), in: Circle())
                .foregroundStyle(color)
        }
        .buttonStyle(.borderless)
        .sensoryFeedback(.impact(weight: .light), trigger: systemImage)
    }
}

struct FinishedBanner: View {
    @Environment(TimerStore.self) private var store

    var body: some View {
        VStack(spacing: 12) {
            Label(title, systemImage: "bell.and.waves.left.and.right.fill")
                .font(.headline)
                .symbolEffect(.pulse)
            HStack(spacing: 12) {
                Button {
                    store.repeatFinished()
                } label: {
                    Text("Repeat").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button {
                    store.stopFinished()
                } label: {
                    Text("Stop").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
            .controlSize(.large)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private var title: String {
        let done = store.finished
        return done.count == 1 ? "\(done[0].displayLabel) is done" : "\(done.count) timers done"
    }
}
