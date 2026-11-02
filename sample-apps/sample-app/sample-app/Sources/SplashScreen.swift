import SwiftUI

/// Splash screen displayed during app initialization
struct SplashScreen: View {
    var body: some View {
        ZStack {
            Color.blue.opacity(0.1)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "swift")
                    .font(.system(size: 80))
                    .foregroundStyle(.blue)

                Text("Sample App")
                    .font(.title)
                    .fontWeight(.bold)

                ProgressView()
                    .tint(.blue)
            }
        }
    }
}

#Preview {
    SplashScreen()
}
