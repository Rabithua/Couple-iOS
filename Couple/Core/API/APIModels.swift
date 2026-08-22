import Foundation

enum FlexibleCode: Decodable, Sendable, Equatable {
    case number(Int)
    case text(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int.self) {
            self = .number(value)
        } else {
            self = .text(try container.decode(String.self))
        }
    }

    var isSuccess: Bool { self == .number(0) }
}

struct APIEnvelope<Value: Decodable & Sendable>: Decodable, Sendable {
    let code: FlexibleCode
    let message: String
    let data: Value
}

struct NullableAPIEnvelope<Value: Decodable & Sendable>: Decodable, Sendable {
    let code: FlexibleCode
    let message: String
    let data: Value?
}

struct EmptyPayload: Codable, Sendable {}

struct PushDeviceRegistrationRequest: Encodable, Sendable {
    let token: String
    let environment: String
    let locale: String
    let appVersion: String
    let appBuild: String
}

struct PushPreferenceRequest: Encodable, Sendable {
    let collaborationEnabled: Bool
    let remindersEnabled: Bool
}

struct PushDeviceStatus: Decodable, Sendable {
    let deviceId: String
    let environment: String
    let collaborationEnabled: Bool
    let remindersEnabled: Bool
    let active: Bool
}

enum Visibility: String, Codable, CaseIterable, Sendable {
    case shared
    case `private`

    var title: String {
        switch self {
        case .shared: AppLocalization.string("共同可见")
        case .private: AppLocalization.string("仅自己可见")
        }
    }
}

struct User: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var displayName: String
    var timezone: String
    var onboardingCompleted: Bool? = nil

    var hasCompletedOnboarding: Bool { onboardingCompleted != false }
}

enum OnboardingSpaceAction: String, Codable, Sendable {
    case create
    case join
}

struct CompleteOnboardingRequest: Encodable, Sendable {
    let displayName: String
    let birthday: String
    let action: OnboardingSpaceAction
    let inviteCode: String?
}

struct CompleteOnboardingResult: Decodable, Sendable {
    let user: User
    let relationship: RelationshipStatus
}

struct TokenPair: Codable, Hashable, Sendable {
    let accessToken: String
    let refreshToken: String
}

struct AuthResult: Codable, Sendable {
    let user: User
    let tokens: TokenPair
}

struct RegistrationOptionsResult: Decodable, Sendable {
    let options: PublicKeyCreationOptions
    let challengeKey: String
    let userId: String
}

struct AuthenticationOptionsResult: Decodable, Sendable {
    let options: PublicKeyRequestOptions
    let challengeKey: String
}

struct PublicKeyCreationOptions: Decodable, Sendable {
    struct RelyingParty: Decodable, Sendable {
        let id: String
        let name: String
    }

    struct CredentialUser: Decodable, Sendable {
        let id: String
        let name: String
        let displayName: String
    }

    let challenge: String
    let rp: RelyingParty
    let user: CredentialUser
    let excludeCredentials: [PublicKeyDescriptor]?
}

struct PublicKeyRequestOptions: Decodable, Sendable {
    let challenge: String
    let rpId: String
    let allowCredentials: [PublicKeyDescriptor]?

    enum CodingKeys: String, CodingKey {
        case challenge
        case rpId = "rpId"
        case allowCredentials
    }
}

struct PublicKeyDescriptor: Decodable, Sendable {
    let id: String
    let type: String
    let transports: [String]?
}

struct Couple: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var startedOn: String?
    var timezone: String
    let createdAt: Date?
    let updatedAt: Date?
}

struct CoupleMember: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
}

struct CoupleInvite: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let code: String
    let expiresAt: Date
}

struct RelationshipStatus: Codable, Sendable {
    let couple: Couple?
    let members: [CoupleMember]
    let pendingInvite: CoupleInvite?
}

struct InviteResult: Codable, Sendable {
    let invite: CoupleInvite
}

struct AcceptInviteResult: Codable, Sendable {
    let couple: CoupleIdentifier
}

struct CoupleIdentifier: Codable, Sendable {
    let id: String
}

struct Anniversary: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let coupleId: String
    let ownerId: String
    var title: String
    var date: String
    var annual: Bool
    var visibility: Visibility
    var reminderEnabled: Bool? = nil
    var reminderOffset: Int?
    var reminderLocalTime: String? = nil
    var reminderInstant: Date?
    let createdAt: Date
    var updatedAt: Date
    var nextOccurrence: String?
    var systemKind: String? = nil

    var isSystemBirthday: Bool { systemKind == "birthday" }

    var displayTitle: String {
        localizedDisplayTitle()
    }

    var systemImageName: String {
        Self.systemImageName(for: title, isSystemBirthday: isSystemBirthday)
    }

    static func systemImageName(
        for title: String,
        isSystemBirthday: Bool = false
    ) -> String {
        let normalizedTitle = title
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: .current
            )
            .lowercased()
        let matches: ([String]) -> Bool = { keywords in
            keywords.contains { normalizedTitle.contains($0) }
        }

        // Specific occasions win when a title contains more than one theme.
        if isSystemBirthday || matches([
            "生日", "birthday", "b-day", "bday"
        ]) {
            return "birthday.cake.fill"
        }
        if matches([
            "结婚", "結婚", "婚礼", "婚禮", "领证", "領證",
            "wedding", "married", "marriage"
        ]) {
            return "heart.circle.fill"
        }
        if matches([
            "旅行", "旅游", "旅遊", "出游", "出遊", "旅程", "度假",
            "travel", "trip", "vacation"
        ]) {
            return "airplane"
        }
        if matches([
            "宠物", "寵物", "猫", "貓", "狗", "毛孩子", "领养", "領養",
            "pet", "kitty", "puppy"
        ]) {
            return "pawprint.fill"
        }
        if matches([
            "搬家", "新家", "入住", "买房", "買房",
            "new home", "move-in", "housewarming"
        ]) {
            return "house.fill"
        }
        if matches([
            "毕业", "畢業", "graduation", "graduate"
        ]) {
            return "graduationcap.fill"
        }
        if matches([
            "初见", "初見", "认识", "認識", "相识", "相識", "见面", "見面",
            "first met", "first meet"
        ]) {
            return "sparkles"
        }
        if matches([
            "在一起", "恋爱", "戀愛", "相恋", "相戀", "告白", "表白", "初吻",
            "together", "dating", "love", "first kiss"
        ]) {
            return "heart.fill"
        }
        if matches([
            "火锅", "火鍋", "餐厅", "餐廳", "晚餐", "咖啡",
            "dinner", "restaurant", "coffee"
        ]) {
            return "fork.knife"
        }
        return "party.popper.fill"
    }

    func localizedDisplayTitle(
        language: AppLanguage = .persisted(),
        bundle: Bundle = .main
    ) -> String {
        guard isSystemBirthday else { return title }
        let format = AppLocalization.string(
            "systemBirthdayTitleFormat",
            defaultValue: "%@的生日",
            bundle: bundle,
            language: language
        )
        return String(format: format, locale: language.locale, title)
    }
}

struct Todo: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let coupleId: String
    let ownerId: String
    var title: String
    var note: String?
    var dueTime: Date?
    var visibility: Visibility
    var completed: Bool
    var completedAt: Date?
    var completedBy: String?
    var reminderEnabled: Bool? = nil
    var reminderOffset: Int?
    var reminderLocalTime: String? = nil
    let createdAt: Date
    var updatedAt: Date
}

struct CalendarEvent: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let coupleId: String
    let ownerId: String
    var title: String
    var description: String?
    var allDay: Bool
    var startTime: Date
    var endTime: Date?
    var timezone: String
    var yearly: Bool
    var visibility: Visibility
    var reminderEnabled: Bool? = nil
    var reminderOffset: Int?
    var reminderLocalTime: String? = nil
    let createdAt: Date
    var updatedAt: Date
    var occurrenceId: String?
    var recurrenceSourceId: String?
}

struct Attachment: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let filename: String
    let mimeType: String
    let size: Int
    let width: Int?
    let height: Int?
    let durationMs: Int?
    let finalized: Bool?
    let processingStatus: String?
    let createdAt: Date
    let sortOrder: Int?
    let url: String?
    let posterUrl: String?
    let demoAssetName: String?

    var aspectRatio: CGFloat {
        guard let width, let height, height > 0 else { return 1 }
        return CGFloat(width) / CGFloat(height)
    }

    var isImage: Bool { mimeType.hasPrefix("image/") }
}

struct NoteAssociation: Codable, Identifiable, Hashable, Sendable {
    enum AssociationType: String, Codable, Sendable {
        case anniversary
        case todo
    }

    let type: AssociationType
    let id: String
    let title: String?
}

struct Note: Codable, Identifiable, Hashable, Sendable {
    enum CreationError: LocalizedError, Equatable, Sendable {
        case empty

        var errorDescription: String? {
            switch self {
            case .empty:
                AppLocalization.string(
                    "emptyMemoryError",
                    defaultValue: "请写下内容或选择照片"
                )
            }
        }
    }

    let id: String
    let coupleId: String
    let ownerId: String
    var content: String
    var visibility: Visibility
    var anniversaryId: String?
    var todoId: String?
    var latitude: Double? = nil
    var longitude: Double? = nil
    var locationName: String? = nil
    let createdAt: Date
    var updatedAt: Date
    var associations: [NoteAssociation]
    var attachments: [Attachment]

    var hasRecordContent: Bool {
        Self.hasRecordContent(text: content, attachmentCount: attachments.count)
    }

    var location: NoteLocation? {
        guard let latitude, let longitude else { return nil }
        return NoteLocation(latitude: latitude, longitude: longitude, name: locationName)
    }

    static func hasRecordContent(text: String, attachmentCount: Int) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || attachmentCount > 0
    }

    static func validateCreation(text: String, attachmentCount: Int) throws {
        guard hasRecordContent(text: text, attachmentCount: attachmentCount) else {
            throw CreationError.empty
        }
    }
}

struct NotesPage: Codable, Sendable {
    let items: [Note]
    let nextCursor: String?
}

struct TimelineEntry: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let coupleId: String
    let ownerId: String
    let eventDate: String
    let text: String
    let mood: String?
    let visibility: Visibility
    let sortOrder: Int
    let createdAt: Date
    let updatedAt: Date
}

struct UpcomingItem: Codable, Hashable, Sendable {
    let type: String
    let id: String
    let title: String
    let dueTime: Date?
    let startTime: Date?
    let allDay: Bool?
    let occurrenceId: String?
}

struct HomeData: Codable, Sendable {
    let daysTogether: Int?
    let nextAnniversary: Anniversary?
    let nextUpcoming: UpcomingItem?
    let latestTimelineEntry: TimelineEntry?
}

struct PresignedUploadResult: Codable, Sendable {
    let attachment: Attachment
    let presignedUrl: String
    let objectKey: String
}

struct CreateNoteRequest: Encodable, Sendable {
    let content: String
    let visibility: Visibility
    let anniversaryId: String?
    let todoId: String?
    let latitude: Double?
    let longitude: Double?
    let locationName: String?
    let attachmentIds: [String]
}

struct CreateTodoRequest: Encodable, Sendable {
    let title: String
    let note: String?
    let dueTime: String?
    let visibility: Visibility
    let reminderEnabled: Bool
    let reminderOffset: Int?
    let reminderLocalTime: String?
}

struct CreateAnniversaryRequest: Encodable, Sendable {
    let title: String
    let date: String
    let annual: Bool
    let visibility: Visibility
    let reminderEnabled: Bool
    let reminderOffset: Int?
    let reminderLocalTime: String?
}

struct CreateCalendarEventRequest: Encodable, Sendable {
    let title: String
    let description: String?
    let allDay: Bool
    let startTime: String
    let endTime: String?
    let timezone: String
    let yearly: Bool
    let visibility: Visibility
    let reminderEnabled: Bool
    let reminderOffset: Int?
    let reminderLocalTime: String?
}

struct PresignedUploadRequest: Encodable, Sendable {
    let filename: String
    let mimeType: String
    let size: Int
    let width: Int
    let height: Int
    let durationMs: Int?
}
