import ReduxKit
import ReduxKitExtensions
import SwiftUI

/// Main view of the application
struct MainView: View {
    @Environment(Store<AppStore.State, AppStore.Action>.self) private var store
    @Environment(Store<NavigationStore.State, NavigationStore.Action>.self) private var navigationStore

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.green)

                    Text("Welcome!")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Your app is ready to use")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 60)

                // Content
                VStack(alignment: .leading, spacing: 16) {
                    InfoRow(
                        icon: "gearshape.fill",
                        title: "Redux Architecture",
                        description: "Powered by ReduxKit"
                    )

                    InfoRow(
                        icon: "arrow.triangle.branch",
                        title: "Unidirectional Flow",
                        description: "Predictable state management"
                    )

                    InfoRow(
                        icon: "doc.text.fill",
                        title: "Type Safe",
                        description: "Built with Swift best practices"
                    )
                }
                .padding(.horizontal, 24)

                // Example buttons
                VStack(spacing: 12) {
                    Button {
                        navigationStore.dispatch(.push(.prismExample))
                    } label: {
                        HStack {
                            Image(systemName: "sparkles")
                            Text("View Prism Example")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .padding()
                        .background(Color.purple.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .foregroundStyle(.purple)

                    Button {
                        navigationStore.dispatch(.push(.keyedExample))
                    } label: {
                        HStack {
                            Image(systemName: "list.bullet.rectangle")
                            Text("View Keyed Example")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .padding()
                        .background(Color.teal.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .foregroundStyle(.teal)

                    Button {
                        navigationStore.dispatch(.push(.offsetExample))
                    } label: {
                        HStack {
                            Image(systemName: "list.number")
                            Text("View Offset Example")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .padding()
                        .background(Color.orange.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .foregroundStyle(.orange)

                    Button {
                        navigationStore.dispatch(.push(.filterOffsetExample))
                    } label: {
                        HStack {
                            Image(systemName: "slider.horizontal.3")
                            Text("View Filter Offset Example")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .foregroundStyle(.blue)

                    Button {
                        navigationStore.dispatch(.push(.filteredKeyedExample))
                    } label: {
                        HStack {
                            Image(systemName: "person.3.fill")
                            Text("View Filtered Keyed Example")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .padding()
                        .background(Color.green.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .foregroundStyle(.green)

                    Button {
                        navigationStore.dispatch(.push(.sortedOffsetExample))
                    } label: {
                        HStack {
                            Image(systemName: "chart.bar.fill")
                            Text("View Sorted Offset Example")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .padding()
                        .background(Color.purple.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .foregroundStyle(.purple)

                    Button {
                        navigationStore.dispatch(.push(.optionalExample))
                    } label: {
                        HStack {
                            Image(systemName: "questionmark.circle")
                            Text("View Optional Example")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .padding()
                        .background(Color.indigo.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .foregroundStyle(.indigo)

                    Button {
                        navigationStore.dispatch(.push(.undoableExample))
                    } label: {
                        HStack {
                            Image(systemName: "arrow.uturn.backward.circle")
                            Text("View Undoable Example")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .padding()
                        .background(Color.cyan.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .foregroundStyle(.cyan)

                    Button {
                        navigationStore.dispatch(.push(.descriptiveUndoableExample))
                    } label: {
                        HStack {
                            Image(systemName: "list.bullet.circle")
                            Text("View Descriptive Undo Example")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .padding()
                        .background(Color.mint.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .foregroundStyle(.mint)

                    Button {
                        navigationStore.dispatch(.push(.actionableUndoableExample))
                    } label: {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("View Actionable Undo Example")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .padding()
                        .background(Color.pink.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .foregroundStyle(.pink)

                    Button {
                        navigationStore.dispatch(.push(.serviceExample))
                    } label: {
                        HStack {
                            Image(systemName: "timer")
                            Text("View Service Example (Pomodoro)")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .foregroundStyle(.red)
                }
                .padding(.horizontal, 24)

                // Actions
                VStack(spacing: 12) {
                    Button {
                        store.dispatch(.authenticate)
                    } label: {
                        Text("Get Started")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Button {
                        store.dispatch(.logout)
                    } label: {
                        Text("Sign Out")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("Home")
    }
}

// MARK: - Supporting Views

private struct InfoRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(Color.blue.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    NavigationStack {
        MainView()
            .environment(AppStore.shared)
            .environment(NavigationStore.shared)
    }
}
