import SwiftUI

struct ContentView: View {
    @State private var store: ProjectStore? = nil

    var body: some View {
        if let store = store {
            WorkspaceView(store: store)
        } else {
            ProjectListView(store: $store)
        }
    }
}

#Preview {
    ContentView()
}
