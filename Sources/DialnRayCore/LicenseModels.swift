import Foundation

public struct GumroadPurchase: Codable, Equatable, Sendable {
    public var productID: String?
    public var productName: String?
    public var email: String?
    public var recurrence: String?
    public var refunded: Bool?
    public var disputed: Bool?
    public var chargebacked: Bool?
    public var subscriptionEndedAt: String?
    public var subscriptionCancelledAt: String?
    public var subscriptionFailedAt: String?

    enum CodingKeys: String, CodingKey {
        case productID = "product_id"
        case productName = "product_name"
        case email
        case recurrence
        case refunded
        case disputed
        case chargebacked
        case subscriptionEndedAt = "subscription_ended_at"
        case subscriptionCancelledAt = "subscription_cancelled_at"
        case subscriptionFailedAt = "subscription_failed_at"
    }

    public var isEntitled: Bool {
        refunded != true
            && disputed != true
            && chargebacked != true
            && subscriptionEndedAt == nil
            && subscriptionCancelledAt == nil
            && subscriptionFailedAt == nil
    }
}

public struct GumroadLicenseResponse: Codable, Equatable, Sendable {
    public var success: Bool
    public var uses: Int?
    public var purchase: GumroadPurchase?
}

public enum LicenseStatus: Equatable, Sendable {
    case configurationRequired
    case missing
    case checking
    case valid(email: String?, offline: Bool)
    case invalid(reason: String)
}
