import SwiftUI

struct ContentView: View {
    @SceneStorage("tab") private var tab = "countdowns"

    var body: some View {
        TabView(selection: $tab) {
            CountdownsView()
                .tabItem { Label("Countdowns", systemImage: "calendar.badge.clock") }
                .tag("countdowns")
            TimersView()
                .tabItem { Label("Timers", systemImage: "timer") }
                .tag("timers")
        }
    }
}

struct AppearanceMenu: View {
    @AppStorage("appearance") private var appearance: Appearance = .system

    var body: some View {
        Menu {
            Picker("Appearance", selection: $appearance) {
                ForEach(Appearance.allCases) { Text($0.title).tag($0) }
            }
        } label: {
            Image(systemName: "circle.lefthalf.filled")
        }
    }
}
