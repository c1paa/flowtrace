import SwiftUI

@main
struct flowtraceApp: App {
    @FocusedValue(\.projectStore) var store: ProjectStore?

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu("Project") {
                Button("Settings...") {
                    store?.showProjectSettings = true
                }
                .keyboardShortcut(",", modifiers: [.command, .shift])
            }
        }
    }
}
