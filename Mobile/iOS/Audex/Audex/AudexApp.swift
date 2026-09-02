import SwiftUI

@main
struct AudexApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model.session)
                .environment(model.library)
                .environment(model.playback)
                .environment(model.downloads)
        }
    }
}

#Preview {
    let model = AppModel()
    RootView()
        .environment(model.session)
        .environment(model.library)
        .environment(model.playback)
        .environment(model.downloads)
}
