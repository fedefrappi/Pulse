// The MIT License (MIT)
//
// Copyright (c) 2020–2022 Alexander Grebenyuk (github.com/kean).

import Foundation
import Combine
import Pulse
import SwiftUI
import CoreData

#if os(iOS)

public struct InsightsView: View {
    @ObservedObject var viewModel: InsightsViewModel

    private var insights: NetworkLoggerInsights { viewModel.insights }

    public var body: some View {
        List {
            Section(header: Text("Transfer Size")) {
                NetworkInspectorTransferInfoView(viewModel: .init(transferSize: insights.transferSize))
                    .padding(.vertical, 8)
            }
            durationSection
            if insights.failures.count > 0 {
                failuresSection
            }
            if insights.redirects.count > 0 {
                redirectsSection
            }
        }
        .listStyle(.automatic)
        .backport.navigationTitle("Insights")
        .navigationBarItems(trailing: navigationTrailingBarItems)
    }

    private var navigationTrailingBarItems: some View {
        Button("Reset") {
            viewModel.insights.reset()
        }
    }

    // MARK: - Duration

    private var durationSection: some View {
        Section(header: Text("Duration")) {
            InfoRow(title: "Median Duration", details: viewModel.medianDuration)
            InfoRow(title: "Duration Range", details: viewModel.durationRange)
            NavigationLink(destination: TopSlowestRequestsViw(viewModel: viewModel)) {
                Text("Show Slowest Requests")
            }.disabled(insights.duration.topSlowestRequests.isEmpty)
        }
    }

    private func barMarkColor(for duration: TimeInterval) -> Color {
        if duration < 1.0 {
            return Color.green
        } else if duration < 1.9 {
            return Color.yellow
        } else {
            return Color.red
        }
    }

    // MARK: - Redirects

    @ViewBuilder
    private var redirectsSection: some View {
        Section(header: HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text("Redirects")
        }) {
            InfoRow(title: "Redirect Count", details: "\(insights.redirects.count)")
            InfoRow(title: "Total Time Lost", details: DurationFormatter.string(from: insights.redirects.timeLost, isPrecise: false))
            NavigationLink(destination: RequestsWithRedirectsView(viewModel: viewModel)) {
                Text("Show Requests with Redirects")
            }.disabled(insights.duration.topSlowestRequests.isEmpty)
        }
    }

    // MARK: - Failures

    @ViewBuilder
    private var failuresSection: some View {
        Section(header: HStack {
            Image(systemName: "xmark.octagon.fill")
                .foregroundColor(.red)
            Text("Failures")
        }) {
            NavigationLink(destination: FailingRequestsListView(viewModel: viewModel)) {
                HStack {
                    Text("Failed Requests")
                    Spacer()
                    Text("\(insights.failures.count)")
                        .foregroundColor(.secondary)
                }
            }.disabled(insights.duration.topSlowestRequests.isEmpty)
        }
    }
}

private struct TopSlowestRequestsViw: View {
    let viewModel: InsightsViewModel

    var body: some View {
        NetworkInsightsRequestsList(viewModel: viewModel.topSlowestRequestsViewModel())
            .navigationBarTitle(Text("Slowest Requests"), displayMode: .inline)
    }
}

private struct RequestsWithRedirectsView: View {
    let viewModel: InsightsViewModel

    var body: some View {
        NetworkInsightsRequestsList(viewModel: viewModel.requestsWithRedirectsViewModel())
            .navigationBarTitle(Text("Redirects"), displayMode: .inline)
    }
}

private struct FailingRequestsListView: View {
    let viewModel: InsightsViewModel

    var body: some View {
        NetworkInsightsRequestsList(viewModel: viewModel.failedRequestsViewModel())
            .navigationBarTitle(Text("Failed Requests"), displayMode: .inline)
    }
}

final class InsightsViewModel: ObservableObject {
    let insights: NetworkLoggerInsights
    private var cancellable: AnyCancellable?

    private let store: LoggerStore

    var medianDuration: String {
        guard let median = insights.duration.median else { return "–" }
        return DurationFormatter.string(from: median, isPrecise: false)
    }

    var durationRange: String {
        guard let min = insights.duration.minimum,
              let max = insights.duration.maximum else {
            return "–"
        }
        if min == max {
            return DurationFormatter.string(from: min, isPrecise: false)
        }
        return "\(DurationFormatter.string(from: min, isPrecise: false)) – \(DurationFormatter.string(from: max, isPrecise: false))"
    }

    init(store: LoggerStore, insights: NetworkLoggerInsights = .shared) {
        self.store = store
        self.insights = insights
        cancellable = insights.didUpdate.throttle(for: 1.0, scheduler: DispatchQueue.main, latest: true).sink { [weak self] in
            withAnimation {
                self?.objectWillChange.send()
            }
        }
    }

    // MARK: - Accessing Data

    func topSlowestRequestsViewModel() -> NetworkInsightsRequestsListViewModel {
        let tasks = self.tasks(with: Array(insights.duration.topSlowestRequests.keys))
            .sorted(by: { $0.duration > $1.duration })
        return NetworkInsightsRequestsListViewModel(tasks: tasks)
    }

    func requestsWithRedirectsViewModel() -> NetworkInsightsRequestsListViewModel {
        let tasks = self.tasks(with: Array(insights.redirects.taskIds))
            .sorted(by: { $0.createdAt > $1.createdAt })
        return NetworkInsightsRequestsListViewModel(tasks: tasks)
    }

    func failedRequestsViewModel() -> NetworkInsightsRequestsListViewModel {
        let tasks = self.tasks(with: Array(insights.failures.taskIds))
            .sorted(by: { $0.createdAt > $1.createdAt })
        return NetworkInsightsRequestsListViewModel(tasks: tasks)
    }

    private func tasks(with ids: [UUID]) -> [NetworkTaskEntity] {
        let request = NSFetchRequest<NetworkTaskEntity>(entityName: "\(NetworkTaskEntity.self)")
        request.fetchLimit = ids.count
        request.predicate = NSPredicate(format: "taskId IN %@", ids)

        return (try? store.viewContext.fetch(request)) ?? []
    }
}

#if DEBUG

struct NetworkInsightsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            InsightsView(viewModel: .init(store: LoggerStore.mock))
        }
    }
}

#endif

#endif
