import SwiftUI

struct ContentView: View {
    var body: some View {
        CountdownsView()
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
