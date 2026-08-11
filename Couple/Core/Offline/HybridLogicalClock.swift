import Foundation

struct HybridLogicalTimestamp: Codable, Hashable, Sendable, Comparable {
    let wallTimeMilliseconds: Int64
    let counter: Int64
    let deviceId: String

    static func < (lhs: HybridLogicalTimestamp, rhs: HybridLogicalTimestamp) -> Bool {
        if lhs.wallTimeMilliseconds != rhs.wallTimeMilliseconds {
            return lhs.wallTimeMilliseconds < rhs.wallTimeMilliseconds
        }
        if lhs.counter != rhs.counter { return lhs.counter < rhs.counter }
        return lhs.deviceId < rhs.deviceId
    }

    var date: Date {
        Date(timeIntervalSince1970: TimeInterval(wallTimeMilliseconds) / 1_000)
    }
}

struct HybridLogicalClock: Sendable {
    private(set) var deviceId: String
    private(set) var lastWallTimeMilliseconds: Int64
    private(set) var counter: Int64
    private(set) var serverOffsetMilliseconds: Int64

    init(
        deviceId: String,
        lastWallTimeMilliseconds: Int64 = 0,
        counter: Int64 = 0,
        serverOffsetMilliseconds: Int64 = 0
    ) {
        self.deviceId = deviceId
        self.lastWallTimeMilliseconds = lastWallTimeMilliseconds
        self.counter = counter
        self.serverOffsetMilliseconds = serverOffsetMilliseconds
    }

    mutating func calibrate(serverTime: Date, receivedAt: Date) {
        serverOffsetMilliseconds = serverTime.millisecondsSince1970 - receivedAt.millisecondsSince1970
    }

    mutating func adoptServerAdjustment(_ authoritative: HybridLogicalTimestamp) {
        lastWallTimeMilliseconds = authoritative.wallTimeMilliseconds
        counter = authoritative.counter
    }

    mutating func tick(at localTime: Date) -> HybridLogicalTimestamp {
        let adjustedWallTime = localTime.millisecondsSince1970 + serverOffsetMilliseconds
        if adjustedWallTime > lastWallTimeMilliseconds {
            lastWallTimeMilliseconds = adjustedWallTime
            counter = 0
        } else {
            counter += 1
        }
        return current
    }

    mutating func observe(
        _ remote: HybridLogicalTimestamp,
        at localTime: Date
    ) -> HybridLogicalTimestamp {
        let adjustedWallTime = localTime.millisecondsSince1970 + serverOffsetMilliseconds
        let previousWallTime = lastWallTimeMilliseconds
        let maximumWallTime = max(adjustedWallTime, previousWallTime, remote.wallTimeMilliseconds)

        if maximumWallTime == previousWallTime, maximumWallTime == remote.wallTimeMilliseconds {
            counter = max(counter, remote.counter) + 1
        } else if maximumWallTime == previousWallTime {
            counter += 1
        } else if maximumWallTime == remote.wallTimeMilliseconds {
            counter = remote.counter + 1
        } else {
            counter = 0
        }
        lastWallTimeMilliseconds = maximumWallTime
        return current
    }

    var current: HybridLogicalTimestamp {
        HybridLogicalTimestamp(
            wallTimeMilliseconds: lastWallTimeMilliseconds,
            counter: counter,
            deviceId: deviceId
        )
    }
}

extension Date {
    var millisecondsSince1970: Int64 {
        Int64((timeIntervalSince1970 * 1_000).rounded())
    }
}
