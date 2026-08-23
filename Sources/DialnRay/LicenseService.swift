import DialnRayCore
import Foundation

@MainActor
final class LicenseService: ObservableObject {
    @Published private(set) var status: LicenseStatus = .missing
    @Published var enteredKey = ""

    private let endpoint = URL(string: "https://api.gumroad.com/v2/licenses/verify")!
    private let keychain = KeychainStore(service: "com.dialnray.app")
    private let keychainAccount = "gumroad-license"
    private let defaults: UserDefaults
    private let session: URLSession
    private let productID: String
    private let offlineGrace: TimeInterval = 7 * 24 * 60 * 60
    private let lastVerifiedKey = "DialnRay.License.LastVerified"
    private let cachedEmailKey = "DialnRay.License.Email"

    init(defaults: UserDefaults = .standard, session: URLSession = .shared) {
        self.defaults = defaults
        self.session = session
        self.productID = (Bundle.main.object(forInfoDictionaryKey: "DialnRayGumroadProductID") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        enteredKey = (try? keychain.read(account: keychainAccount)) ?? ""
        if productID.isEmpty || productID == "REPLACE_WITH_GUMROAD_PRODUCT_ID" {
            status = .configurationRequired
        } else if enteredKey.isEmpty {
            status = .missing
        } else if isInsideOfflineGrace {
            status = .valid(email: defaults.string(forKey: cachedEmailKey), offline: true)
        }
    }

    var developmentAccess: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    var canUseProduct: Bool {
        if developmentAccess { return true }
        if case .valid = status { return true }
        return false
    }

    func activate() async {
        let key = enteredKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            status = .invalid(reason: "Enter the license key from your Gumroad receipt.")
            return
        }
        guard !productID.isEmpty, productID != "REPLACE_WITH_GUMROAD_PRODUCT_ID" else {
            status = .configurationRequired
            return
        }
        do {
            let previousKey = try keychain.read(account: keychainAccount)
            try await verify(key: key, incrementUses: previousKey != key)
            try keychain.write(key, account: keychainAccount)
            enteredKey = key
        } catch {
            status = .invalid(reason: readableMessage(for: error))
        }
    }

    func refreshIfNeeded(force: Bool = false) async {
        guard !productID.isEmpty, productID != "REPLACE_WITH_GUMROAD_PRODUCT_ID" else {
            status = .configurationRequired
            return
        }
        guard let key = try? keychain.read(account: keychainAccount), !key.isEmpty else {
            status = .missing
            return
        }
        enteredKey = key
        if !force, isInsideOfflineGrace {
            status = .valid(email: defaults.string(forKey: cachedEmailKey), offline: true)
            return
        }
        do {
            try await verify(key: key, incrementUses: false)
        } catch {
            if isInsideOfflineGrace {
                status = .valid(email: defaults.string(forKey: cachedEmailKey), offline: true)
            } else {
                status = .invalid(reason: readableMessage(for: error))
            }
        }
    }

    func deactivate() {
        try? keychain.delete(account: keychainAccount)
        defaults.removeObject(forKey: lastVerifiedKey)
        defaults.removeObject(forKey: cachedEmailKey)
        enteredKey = ""
        status = productID.isEmpty || productID == "REPLACE_WITH_GUMROAD_PRODUCT_ID"
            ? .configurationRequired
            : .missing
    }

    private func verify(key: String, incrementUses: Bool) async throws {
        status = .checking
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "product_id", value: productID),
            URLQueryItem(name: "license_key", value: key),
            URLQueryItem(name: "increment_uses_count", value: incrementUses ? "true" : "false"),
        ]
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw LicenseVerificationError.rejected
        }
        let payload = try JSONDecoder().decode(GumroadLicenseResponse.self, from: data)
        guard payload.success, let purchase = payload.purchase else {
            throw LicenseVerificationError.rejected
        }
        guard purchase.productID == nil || purchase.productID == productID else {
            throw LicenseVerificationError.wrongProduct
        }
        guard purchase.isEntitled else {
            throw LicenseVerificationError.ended
        }
        defaults.set(Date().timeIntervalSince1970, forKey: lastVerifiedKey)
        defaults.set(purchase.email, forKey: cachedEmailKey)
        status = .valid(email: purchase.email, offline: false)
    }

    private var isInsideOfflineGrace: Bool {
        let timestamp = defaults.double(forKey: lastVerifiedKey)
        guard timestamp > 0 else { return false }
        return Date().timeIntervalSince1970 - timestamp <= offlineGrace
    }

    private func readableMessage(for error: Error) -> String {
        switch error {
        case LicenseVerificationError.rejected:
            return "Gumroad could not verify this key. Check the key and try again."
        case LicenseVerificationError.wrongProduct:
            return "This key belongs to a different Gumroad product."
        case LicenseVerificationError.ended:
            return "This annual license is no longer active. Renew it on Gumroad to continue."
        default:
            return "DialnRay could not reach Gumroad. Check your connection and try again."
        }
    }
}

private enum LicenseVerificationError: Error {
    case rejected
    case wrongProduct
    case ended
}
