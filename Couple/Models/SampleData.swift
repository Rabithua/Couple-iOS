import Foundation

enum SampleData {
    static let now = Date()
    static let user = User(
        id: "10000000-0000-4000-8000-000000000001",
        displayName: String(localized: "程袭"),
        timezone: "Asia/Shanghai"
    )
    static let partner = CoupleMember(
        id: "10000000-0000-4000-8000-000000000002",
        displayName: String(localized: "长野")
    )
    static let relationship = RelationshipStatus(
        couple: Couple(
            id: "20000000-0000-4000-8000-000000000001",
            startedOn: "2025-02-28",
            timezone: "Asia/Shanghai",
            createdAt: now,
            updatedAt: now
        ),
        members: [CoupleMember(id: user.id, displayName: user.displayName), partner],
        pendingInvite: nil
    )

    static let anniversary = Anniversary(
        id: "30000000-0000-4000-8000-000000000001",
        coupleId: relationship.couple!.id,
        ownerId: user.id,
        title: String(localized: "程袭的生日"),
        date: Calendar.current.date(byAdding: .day, value: 8, to: now)!.dateOnlyString,
        annual: true,
        visibility: .shared,
        reminderOffset: 1_440,
        reminderInstant: nil,
        createdAt: now,
        updatedAt: now,
        nextOccurrence: Calendar.current.date(byAdding: .day, value: 8, to: now)!.dateOnlyString
    )

    static let todos: [Todo] = [
        String(localized: "一起去灵隐寺还愿吧"),
        String(localized: "闪击杭钢"),
        String(localized: "真的很想吃云记烤鸭"),
        String(localized: "清迈好啊，去玩去玩")
    ].enumerated().map { index, title in
        Todo(
            id: "40000000-0000-4000-8000-00000000000\(index + 1)",
            coupleId: relationship.couple!.id,
            ownerId: user.id,
            title: title,
            note: nil,
            dueTime: Calendar.current.date(byAdding: .day, value: 7 + index, to: now),
            visibility: .shared,
            completed: false,
            completedAt: nil,
            completedBy: nil,
            reminderOffset: nil,
            createdAt: now.addingTimeInterval(Double(-index * 3_600)),
            updatedAt: now
        )
    }

    static let completedTodo = Todo(
        id: "40000000-0000-4000-8000-000000000099",
        coupleId: relationship.couple!.id,
        ownerId: user.id,
        title: String(localized: "去灵隐寺还愿吧"),
        note: nil,
        dueTime: nil,
        visibility: .shared,
        completed: true,
        completedAt: now,
        completedBy: partner.id,
        reminderOffset: nil,
        createdAt: now.addingTimeInterval(-172_800),
        updatedAt: now
    )

    static let attachments: [Attachment] = [
        demoAttachment(id: 1, asset: "MemoryWoman", width: 800, height: 1_200),
        demoAttachment(id: 2, asset: "MemoryMan", width: 1_800, height: 1_200),
        demoAttachment(id: 3, asset: "MemoryLake", width: 900, height: 1_200),
        demoAttachment(id: 4, asset: "MemoryCeiling", width: 800, height: 1_200),
        demoAttachment(id: 5, asset: "MemoryWoman2", width: 800, height: 1_200),
        demoAttachment(id: 6, asset: "MemoryToast", width: 1_800, height: 1_200)
    ]

    static let notes: [Note] = [
        Note(
            id: "50000000-0000-4000-8000-000000000001",
            coupleId: relationship.couple!.id,
            ownerId: partner.id,
            content: String(localized: "遇到了特别特别特别好看的夕阳，美美拍照，还有特别棒的双彩虹！\n还见到了好久没见的小狗！\n（👇图一也是小狗哈）"),
            visibility: .shared,
            anniversaryId: nil,
            todoId: nil,
            createdAt: now.addingTimeInterval(-432_000),
            updatedAt: now.addingTimeInterval(-432_000),
            associations: [],
            attachments: Array(attachments[0...1])
        ),
        Note(
            id: "50000000-0000-4000-8000-000000000002",
            coupleId: relationship.couple!.id,
            ownerId: user.id,
            content: String(localized: "谁能拒绝坐在水边逮一下午虾呢～"),
            visibility: .shared,
            anniversaryId: nil,
            todoId: nil,
            createdAt: now.addingTimeInterval(-1_900_000),
            updatedAt: now.addingTimeInterval(-1_900_000),
            associations: [],
            attachments: Array(attachments[2...4])
        ),
        Note(
            id: "50000000-0000-4000-8000-000000000003",
            coupleId: relationship.couple!.id,
            ownerId: partner.id,
            content: "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXX\nXXXXXXXXXX",
            visibility: .shared,
            anniversaryId: anniversary.id,
            todoId: nil,
            createdAt: now.addingTimeInterval(-2_100_000),
            updatedAt: now.addingTimeInterval(-2_100_000),
            associations: [.init(type: .anniversary, id: anniversary.id, title: anniversary.title)],
            attachments: Array(attachments[2...4])
        ),
        Note(
            id: "50000000-0000-4000-8000-000000000004",
            coupleId: relationship.couple!.id,
            ownerId: user.id,
            content: "",
            visibility: .shared,
            anniversaryId: nil,
            todoId: completedTodo.id,
            createdAt: now.addingTimeInterval(-2_400_000),
            updatedAt: now.addingTimeInterval(-2_400_000),
            associations: [.init(type: .todo, id: completedTodo.id, title: completedTodo.title)],
            attachments: []
        )
    ]

    static let home = HomeData(
        daysTogether: 528,
        nextAnniversary: anniversary,
        nextUpcoming: UpcomingItem(
            type: "todo",
            id: todos[0].id,
            title: todos[0].title,
            dueTime: todos[0].dueTime,
            startTime: nil,
            allDay: nil,
            occurrenceId: nil
        ),
        latestTimelineEntry: nil
    )

    static let events: [CalendarEvent] = [
        CalendarEvent(
            id: "60000000-0000-4000-8000-000000000001",
            coupleId: relationship.couple!.id,
            ownerId: user.id,
            title: String(localized: "一起吃晚饭"),
            description: nil,
            allDay: false,
            startTime: Calendar.current.date(byAdding: .day, value: 3, to: now)!,
            endTime: Calendar.current.date(byAdding: .day, value: 3, to: now)!.addingTimeInterval(7_200),
            timezone: "Asia/Shanghai",
            yearly: false,
            visibility: .shared,
            reminderOffset: 60,
            createdAt: now,
            updatedAt: now,
            occurrenceId: nil,
            recurrenceSourceId: nil
        )
    ]

    private static func demoAttachment(id: Int, asset: String, width: Int, height: Int) -> Attachment {
        Attachment(
            id: "70000000-0000-4000-8000-00000000000\(id)",
            filename: "\(asset).png",
            mimeType: "image/png",
            size: 1,
            width: width,
            height: height,
            durationMs: nil,
            finalized: true,
            processingStatus: "ready",
            createdAt: now,
            sortOrder: id,
            url: nil,
            posterUrl: nil,
            demoAssetName: asset
        )
    }
}
