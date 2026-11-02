import ReduxKitUI
import SwiftUI

@main
struct SampleAppApp: App {
    var body: some Scene {
        WindowGroup {
            AppView()
                .environment(AppStore.shared)
                .environment(NavigationStore.shared)
        }
    }
}
