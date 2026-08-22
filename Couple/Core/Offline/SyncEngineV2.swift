import Foundation

enum SyncEngineV2State: Equatable, Sendable {
    case idle
    case syncing(SyncTrigger)
    case waitingForNetwork
    case retrying(attempt: Int, message: String)
    case blocked(String)
}

struct SyncV2RunSummary: Equatable, Sendable {
    let result: SyncRunResult
    let appliedOperationCount: Int
    let rejectedOperationCount: Int
    let remoteChangeCount: Int

    var requiresSnapshotReload: Bool {
        appliedOperationCount > 0 || rejectedOperationCount > 0 || remoteChangeCount > 0
    }
}

actor SyncEngineV2 {
    private let repository: SyncRepositoryV2
    private let transport: any SyncV2Transporting
    private let retryBaseDelay: TimeInterval
    private let batchSize: Int
    private let pageSize: Int
    private let stateStream: AsyncStream<SyncEngineV2State>
    private let stateContinuation: AsyncStream<SyncEngineV2State>.Continuation

    private var activeTask: Task<SyncV2RunSummary, Never>?
    private var activeTaskID: UUID?
    private var retryTask: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?
    private var pendingPull = false
    private var acceptingTriggers = true
    private var retryAttempt = 0
    private(set) var state: SyncEngineV2State = .idle

    init(
        repository: SyncRepositoryV2,
        transport: any SyncV2Transporting,
        retryBaseDelay: TimeInterval = 2,
        batchSize: Int = 50,
        pageSize: Int = 200
    ) {
        self.repository = repository
        self.transport = transport
        self.retryBaseDelay = retryBaseDelay
        self.batchSize = min(max(batchSize, 1), 50)
        self.pageSize = min(max(pageSize, 1), 200)
        let pair = AsyncStream.makeStream(
            of: SyncEngineV2State.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        self.stateStream = pair.stream
        self.stateContinuation = pair.continuation
        pair.continuation.yield(.idle)
    }

    deinit {
        stateContinuation.finish()
    }

    func states() -> AsyncStream<SyncEngineV2State> {
        stateStream
    }

    func resume() async throws {
        acceptingTriggers = true
        try await repository.prepareForSession()
    }

    func trigger(_ trigger: SyncTrigger) async -> SyncV2RunSummary {
        guard acceptingTriggers else {
            return SyncV2RunSummary(
                result: .cancelled,
                appliedOperationCount: 0,
                rejectedOperationCount: 0,
                remoteChangeCount: 0
            )
        }
        pendingPull = true
        if let activeTask { return await activeTask.value }
        publish(.syncing(trigger))
        let taskID = UUID()
        activeTaskID = taskID
        let task = Task { [weak self] in
            guard let self else {
                return SyncV2RunSummary(
                    result: .cancelled,
                    appliedOperationCount: 0,
                    rejectedOperationCount: 0,
                    remoteChangeCount: 0
                )
            }
            return await self.runUntilCaughtUp()
        }
        activeTask = task
        let summary = await task.value
        if activeTaskID == taskID {
            activeTask = nil
            activeTaskID = nil
        }
        return summary
    }

    func startForegroundPolling(
        performPoll: @escaping @Sendable () async -> Void
    ) {
        guard acceptingTriggers, pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(30))
                    guard self != nil, !Task.isCancelled else { return }
                    await performPoll()
                } catch is CancellationError {
                    return
                } catch {
                    return
                }
            }
        }
    }

    func stopForegroundPolling() async {
        let task = pollingTask
        pollingTask = nil
        task?.cancel()
        await task?.value
    }

    func stopAndWait() async {
        acceptingTriggers = false
        pendingPull = false
        let active = activeTask
        let retry = retryTask
        let poll = pollingTask
        activeTask = nil
        activeTaskID = nil
        retryTask = nil
        pollingTask = nil
        active?.cancel()
        retry?.cancel()
        poll?.cancel()
        _ = await active?.value
        await retry?.value
        await poll?.value
        publish(.idle)
    }

    private func runUntilCaughtUp() async -> SyncV2RunSummary {
        var applied = 0
        var rejected = 0
        var changes = 0
        while pendingPull {
            pendingPull = false
            let run = await runExchangeCycle()
            applied += run.appliedOperationCount
            rejected += run.rejectedOperationCount
            changes += run.remoteChangeCount
            guard run.result == .success else {
                return SyncV2RunSummary(
                    result: run.result,
                    appliedOperationCount: applied,
                    rejectedOperationCount: rejected,
                    remoteChangeCount: changes
                )
            }
        }

        retryAttempt = 0
        retryTask?.cancel()
        retryTask = nil
        do {
            let queue = try await repository.queueState()
            if queue.hasBlocked {
                publish(.blocked(AppLocalization.string("有内容未能同步，请检查后重试")))
            } else {
                publish(.idle)
            }
        } catch {
            publish(.blocked(error.localizedDescription))
        }
        return SyncV2RunSummary(
            result: .success,
            appliedOperationCount: applied,
            rejectedOperationCount: rejected,
            remoteChangeCount: changes
        )
    }

    private func runExchangeCycle() async -> SyncV2RunSummary {
        var sentIds: [String] = []
        var applied = 0
        var rejected = 0
        var changes = 0
        var exchangedPages = 0
        var rotatedDevice = false
        do {
            var cursor = try await repository.cursor()
            while true {
                try Task.checkCancellation()
                exchangedPages += 1
                guard exchangedPages <= 1_000 else {
                    throw SyncTransportError.rejected(AppLocalization.string("同步分页超过安全上限"))
                }
                let operations = try await repository.pendingOperations(limit: batchSize, now: .now)
                sentIds = operations.map(\.operationId)
                if !sentIds.isEmpty {
                    try await repository.markSending(operationIds: sentIds, now: .now)
                }

                let exchange: SyncV2Exchange
                do {
                    exchange = try await transport.exchange(
                        cursor: cursor,
                        operations: operations,
                        limit: pageSize
                    )
                } catch SyncTransportError.deviceReused where !rotatedDevice {
                    try await repository.cancelSending(operationIds: sentIds, now: .now)
                    sentIds = []
                    try await repository.rotateDeviceIdentifier()
                    cursor = nil
                    rotatedDevice = true
                    continue
                }

                let appliedPage = try await repository.apply(
                    exchange,
                    sentOperationIds: sentIds,
                    now: .now
                )
                sentIds = []
                applied += appliedPage.appliedCount
                rejected += appliedPage.rejectedCount
                changes += appliedPage.changeCount
                cursor = exchange.page.nextCursor
                if exchange.page.hasMore || !operations.isEmpty { continue }
                return SyncV2RunSummary(
                    result: .success,
                    appliedOperationCount: applied,
                    rejectedOperationCount: rejected,
                    remoteChangeCount: changes
                )
            }
        } catch is CancellationError {
            if !sentIds.isEmpty {
                try? await repository.cancelSending(operationIds: sentIds, now: .now)
            }
            return SyncV2RunSummary(
                result: .cancelled,
                appliedOperationCount: applied,
                rejectedOperationCount: rejected,
                remoteChangeCount: changes
            )
        } catch {
            if !sentIds.isEmpty {
                try? await repository.failSending(
                    operationIds: sentIds,
                    message: error.localizedDescription,
                    now: .now,
                    retryBaseDelay: retryBaseDelay
                )
            }
            await scheduleRetryIfNeeded(message: error.localizedDescription, error: error)
            return SyncV2RunSummary(
                result: .failed(error.localizedDescription),
                appliedOperationCount: applied,
                rejectedOperationCount: rejected,
                remoteChangeCount: changes
            )
        }
    }

    private func scheduleRetryIfNeeded(message: String, error: Error) async {
        guard acceptingTriggers else { return }
        let queue: (hasPending: Bool, hasBlocked: Bool, nextRetry: Date?)
        do {
            queue = try await repository.queueState()
        } catch {
            publish(.blocked(error.localizedDescription))
            return
        }
        if Self.isOffline(error) {
            publish(.waitingForNetwork)
        } else if queue.hasBlocked {
            publish(.blocked(message))
        }
        guard queue.hasPending else {
            if !Self.isOffline(error), !queue.hasBlocked { publish(.idle) }
            return
        }
        guard retryTask == nil else { return }
        retryAttempt += 1
        let fallback = min(retryBaseDelay * pow(2, Double(min(retryAttempt - 1, 10))), 300)
            * Double.random(in: 0.8...1.2)
        let delay = max(queue.nextRetry?.timeIntervalSinceNow ?? fallback, 0.25)
        if !Self.isOffline(error) {
            publish(.retrying(attempt: retryAttempt, message: message))
        }
        retryTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
                guard let self, !Task.isCancelled else { return }
                await self.retryTimerFired()
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }

    private func retryTimerFired() async {
        retryTask = nil
        _ = await trigger(.retry)
    }

    private func publish(_ next: SyncEngineV2State) {
        guard state != next else { return }
        state = next
        stateContinuation.yield(next)
    }

    private static func isOffline(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        return [
            .notConnectedToInternet,
            .networkConnectionLost,
            .cannotConnectToHost,
            .cannotFindHost,
        ].contains(urlError.code)
    }
}
