import Foundation

struct TweetEnvelope: Decodable, Sendable {
    var tweet: Tweet
}

struct AccountEnvelope: Decodable, Sendable {
    var account: AccountProfile
}

struct AccountProfile: Decodable, Sendable {
    var username: String?
    var accountDisplayName: String?

    enum CodingKeys: String, CodingKey {
        case username
        case accountDisplayName
    }
}

struct Tweet: Decodable, Sendable {
    var idStr: String
    var fullText: String
    var createdAt: Date
    var favoriteCount: Int
    var retweetCount: Int
    var inReplyToStatusID: String?
    var inReplyToScreenName: String?
    var entities: Entities
    var extendedEntities: ExtendedEntities?
    var coordinates: Coordinates?
    var mediaFiles: [String] = []

    enum CodingKeys: String, CodingKey {
        case idStr = "id_str"
        case fullText = "full_text"
        case createdAt = "created_at"
        case favoriteCount = "favorite_count"
        case retweetCount = "retweet_count"
        case inReplyToStatusID = "in_reply_to_status_id_str"
        case inReplyToScreenName = "in_reply_to_screen_name"
        case entities
        case extendedEntities = "extended_entities"
        case coordinates
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        idStr = try container.decode(String.self, forKey: .idStr)
        fullText = try container.decode(String.self, forKey: .fullText)

        let createdAtRaw = try container.decode(String.self, forKey: .createdAt)
        guard let parsedDate = Self.createdAtFormatter.date(from: createdAtRaw) else {
            throw DecodingError.dataCorruptedError(
                forKey: .createdAt,
                in: container,
                debugDescription: "Unexpected date format: \(createdAtRaw)"
            )
        }
        createdAt = parsedDate

        favoriteCount = Self.decodeInt(container: container, key: .favoriteCount) ?? 0
        retweetCount = Self.decodeInt(container: container, key: .retweetCount) ?? 0
        inReplyToStatusID = try container.decodeIfPresent(String.self, forKey: .inReplyToStatusID)
        inReplyToScreenName = try container.decodeIfPresent(String.self, forKey: .inReplyToScreenName)
        entities = try container.decodeIfPresent(Entities.self, forKey: .entities) ?? Entities()
        extendedEntities = try container.decodeIfPresent(ExtendedEntities.self, forKey: .extendedEntities)
        coordinates = try container.decodeIfPresent(Coordinates.self, forKey: .coordinates)
    }

    private static func decodeInt(
        container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) -> Int? {
        if let intValue = try? container.decode(Int.self, forKey: key) {
            return intValue
        }
        if let stringValue = try? container.decode(String.self, forKey: key) {
            return Int(stringValue)
        }
        return nil
    }

    private static let createdAtFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE MMM dd HH:mm:ss Z yyyy"
        return formatter
    }()
}

struct Entities: Decodable, Sendable {
    var hashtags: [Hashtag]
    var urls: [URLEntity]
    var media: [MediaEntity]
    var userMentions: [UserMention]

    enum CodingKeys: String, CodingKey {
        case hashtags
        case urls
        case media
        case userMentions = "user_mentions"
    }

    init() {
        hashtags = []
        urls = []
        media = []
        userMentions = []
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hashtags = try container.decodeIfPresent([Hashtag].self, forKey: .hashtags) ?? []
        urls = try container.decodeIfPresent([URLEntity].self, forKey: .urls) ?? []
        media = try container.decodeIfPresent([MediaEntity].self, forKey: .media) ?? []
        userMentions = try container.decodeIfPresent([UserMention].self, forKey: .userMentions) ?? []
    }
}

struct Hashtag: Decodable, Sendable {
    var text: String
}

struct URLEntity: Decodable, Sendable {
    var url: String?
    var expandedURL: String?
    var displayURL: String?

    enum CodingKeys: String, CodingKey {
        case url
        case expandedURL = "expanded_url"
        case displayURL = "display_url"
    }
}

struct UserMention: Decodable, Sendable {
    var screenName: String
    var name: String?

    enum CodingKeys: String, CodingKey {
        case screenName = "screen_name"
        case name
    }
}

struct ExtendedEntities: Decodable, Sendable {
    var media: [MediaEntity]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        media = try container.decodeIfPresent([MediaEntity].self, forKey: .media) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case media
    }
}

struct MediaEntity: Decodable, Sendable {
    var url: String?
    var type: String?
    var mediaURLHTTPS: String?
    var videoInfo: VideoInfo?

    enum CodingKeys: String, CodingKey {
        case url
        case type
        case mediaURLHTTPS = "media_url_https"
        case videoInfo = "video_info"
    }
}

struct VideoInfo: Decodable, Sendable {
    var variants: [VideoVariant]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        variants = try container.decodeIfPresent([VideoVariant].self, forKey: .variants) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case variants
    }
}

struct VideoVariant: Decodable, Sendable {
    var bitrate: Int?
    var contentType: String?
    var url: String?

    enum CodingKeys: String, CodingKey {
        case bitrate
        case contentType = "content_type"
        case url
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let intValue = try? container.decode(Int.self, forKey: .bitrate) {
            bitrate = intValue
        } else if let stringValue = try? container.decode(String.self, forKey: .bitrate), let intValue = Int(stringValue) {
            bitrate = intValue
        } else {
            bitrate = nil
        }
        contentType = try container.decodeIfPresent(String.self, forKey: .contentType)
        url = try container.decodeIfPresent(String.self, forKey: .url)
    }
}

struct Coordinates: Decodable, Sendable {
    var coordinates: [Double]

    enum CodingKeys: String, CodingKey {
        case coordinates
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let values = try container.decode([LossyDouble].self, forKey: .coordinates)
        coordinates = values.map(\.value)
    }

    var latitudeLongitude: (latitude: Double, longitude: Double)? {
        guard coordinates.count >= 2 else {
            return nil
        }
        return (latitude: coordinates[1], longitude: coordinates[0])
    }
}

private struct LossyDouble: Decodable, Sendable {
    let value: Double

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let double = try? container.decode(Double.self) {
            value = double
            return
        }
        if let string = try? container.decode(String.self), let double = Double(string) {
            value = double
            return
        }
        throw DecodingError.typeMismatch(
            Double.self,
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Expected a number or numeric string for coordinate."
            )
        )
    }
}
