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
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") {
                    store?.undo()
                }
                .keyboardShortcut("z", modifiers: [.command])
                .disabled(store?.canUndo != true)
                Button("Redo") {
                    store?.redo()
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(store?.canRedo != true)
            }
            CommandMenu("Project") {
                Button("Settings...") {
                    store?.showProjectSettings = true
                }
                .keyboardShortcut(",", modifiers: [.command, .shift])
            }
        }
    }
}
