//
//  GithubApp.swift
//  Example
//
//  Created by Majid Jabrayilov on 17.07.22.
//
import ReduxKit
import SwiftUI

struct Repo: Identifiable, Hashable, Decodable {
    let id: Int
    let name: String
    let description: String?
}

struct SearchResponse: Decodable {
    let items: [Repo]
}

struct SearchState: Hashable {
    var query = ""
    var repos: [Repo] = []
    var isLoading = false
}

enum SearchAction: Actionable {
    case search(query: String)
    case refresh
    case setResults(repos: [Repo])
}

struct SearchReducer: Reducer {
    func reduce(oldState: SearchState, with action: SearchAction) -> SearchState {
        var state = oldState

        switch action {
        case let .search(query):
            state.query = query
            state.isLoading = true
        case .refresh:
            break
        case let .setResults(repos):
            state.repos = repos
            state.isLoading = false
        }

        return state
    }
}

/// Emits a `.refresh` on a timer, so the visible results follow the repository upstream.
///
/// Nothing triggers this service from inside the store: it is an outside source pushing actions in,
/// which is exactly what a ``StoreService`` is for.
struct RefreshService: StoreService {
    let interval: Duration

    func actions() -> AsyncStream<SearchAction> {
        AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: interval)
                    continuation.yield(.refresh)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

actor SearchMiddleware: Middleware {
    struct Dependencies {
        var search: (String) async throws -> SearchResponse

        static var production: Dependencies {
            .init { query in
                guard var urlComponents = URLComponents(string: "https://api.github.com/search/repositories")
                else {
                    return .init(items: [])
                }

                urlComponents.queryItems = [.init(name: "q", value: query)]

                guard let url = urlComponents.url else {
                    return .init(items: [])
                }

                let (data, _) = try await URLSession.shared.data(from: url)
                return try JSONDecoder().decode(SearchResponse.self, from: data)
            }
        }
    }

    let dependencies: Dependencies
    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func process(state: SearchState, with action: SearchAction) async -> SearchAction? {
        switch action {
        case let .search(query):
            return await results(for: query, fallingBackTo: state.repos)
        case .refresh:
            guard !state.query.isEmpty else { return nil }

            return await results(for: state.query, fallingBackTo: state.repos)
        case .setResults:
            return nil
        }
    }

    private func results(for query: String, fallingBackTo repos: [Repo]) async -> SearchAction {
        let response = try? await dependencies.search(query)
        guard !Task.isCancelled else {
            return .setResults(repos: repos)
        }

        return .setResults(repos: response?.items ?? [])
    }
}

typealias SearchStore = Store<SearchState, SearchAction>

@MainActor
struct SearchView: View {
    @State private var store = SearchStore(
        initialState: .init(),
        reducer: SearchReducer(),
        middlewares: [SearchMiddleware(dependencies: .production)],
        services: [RefreshService(interval: .seconds(60))]
    )
    @State private var query = ""

    var body: some View {
        List(store.repos) { repo in
            VStack(alignment: .leading) {
                Text(repo.name)
                    .font(.headline)

                if let description = repo.description {
                    Text(description)
                }
            }
        }
        .redacted(reason: store.isLoading ? .placeholder : [])
        .searchable(text: $query)
        .task(id: query) {
            await store.send(.search(query: query))
        }
        .task {
            await store.run()
        }
        .navigationTitle("Github Search")
    }
}

@main
struct GithubApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                SearchView()
            }
        }
    }
}
