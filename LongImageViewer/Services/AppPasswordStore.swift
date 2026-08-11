import CryptoKit
import Foundation
import Security

enum AppPasswordStoreError: LocalizedError {
  case passwordAlreadySet
  case passwordNotSet
  case invalidStoredPassword
  case randomGenerationFailed(OSStatus)
  case keychainFailure(OSStatus)

  var errorDescription: String? {
    switch self {
    case .passwordAlreadySet:
      return "应用密码已存在。"
    case .passwordNotSet:
      return "尚未设置应用密码。"
    case .invalidStoredPassword:
      return "保存的应用密码数据已损坏。"
    case .randomGenerationFailed(let status):
      return "无法生成安全的密码数据。\(message(for: status))"
    case .keychainFailure(let status):
      return "无法访问系统钥匙串。\(message(for: status))"
    }
  }

  private func message(for status: OSStatus) -> String {
    if let message = SecCopyErrorMessageString(status, nil) {
      return "\(message)"
    }
    return "系统错误 \(status)"
  }
}

final class AppPasswordStore {
  static let shared = AppPasswordStore()

  private struct StoredCredential: Codable {
    let version: Int
    let salt: Data
    let digest: Data
  }

  private let account = "application-password"
  private let derivationRounds = 50_000
  private let service: String

  private init() {
    let bundleIdentifier =
      Bundle.main.bundleIdentifier
      ?? "com.trae.LongImageViewer"
    service = "\(bundleIdentifier).app-lock"
  }

  func hasPassword() throws -> Bool {
    try readCredentialData() != nil
  }

  func verify(_ password: String) throws -> Bool {
    guard let data = try readCredentialData() else {
      throw AppPasswordStoreError.passwordNotSet
    }
    let credential: StoredCredential
    do {
      credential = try PropertyListDecoder().decode(
        StoredCredential.self,
        from: data
      )
    } catch {
      throw AppPasswordStoreError.invalidStoredPassword
    }
    guard credential.version == 1 else {
      throw AppPasswordStoreError.invalidStoredPassword
    }

    let candidate = deriveDigest(
      password: password,
      salt: credential.salt
    )
    return constantTimeEqual(candidate, credential.digest)
  }

  func setPassword(_ password: String) throws {
    guard try readCredentialData() == nil else {
      throw AppPasswordStoreError.passwordAlreadySet
    }
    try addCredential(makeCredential(password: password))
  }

  func changePassword(
    currentPassword: String,
    newPassword: String
  ) throws -> Bool {
    guard try verify(currentPassword) else {
      return false
    }
    try updateCredential(makeCredential(password: newPassword))
    return true
  }

  func removePassword(currentPassword: String) throws -> Bool {
    guard try verify(currentPassword) else {
      return false
    }
    try deleteCredential()
    return true
  }

  #if DEBUG
    func resetForTesting() throws {
      try deleteCredential(allowsMissingItem: true)
    }
  #endif

  private func makeCredential(
    password: String
  ) throws -> StoredCredential {
    var randomBytes = [UInt8](repeating: 0, count: 16)
    let status = randomBytes.withUnsafeMutableBytes { buffer in
      SecRandomCopyBytes(
        kSecRandomDefault,
        buffer.count,
        buffer.baseAddress!
      )
    }
    guard status == errSecSuccess else {
      throw AppPasswordStoreError.randomGenerationFailed(status)
    }

    let salt = Data(randomBytes)
    return StoredCredential(
      version: 1,
      salt: salt,
      digest: deriveDigest(password: password, salt: salt)
    )
  }

  private func deriveDigest(
    password: String,
    salt: Data
  ) -> Data {
    let passwordData = Data(password.utf8)
    var firstRound = Data(capacity: salt.count + passwordData.count)
    firstRound.append(salt)
    firstRound.append(passwordData)
    var digest = Data(SHA256.hash(data: firstRound))

    for _ in 1..<derivationRounds {
      var round = Data(
        capacity: digest.count + salt.count + passwordData.count
      )
      round.append(digest)
      round.append(salt)
      round.append(passwordData)
      digest = Data(SHA256.hash(data: round))
    }
    return digest
  }

  private func constantTimeEqual(
    _ lhs: Data,
    _ rhs: Data
  ) -> Bool {
    guard lhs.count == rhs.count else { return false }
    var difference: UInt8 = 0
    for (left, right) in zip(lhs, rhs) {
      difference |= left ^ right
    }
    return difference == 0
  }

  private func encoded(
    _ credential: StoredCredential
  ) throws -> Data {
    let encoder = PropertyListEncoder()
    encoder.outputFormat = .binary
    return try encoder.encode(credential)
  }

  private func baseQuery() -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }

  private func readCredentialData() throws -> Data? {
    var query = baseQuery()
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var result: CFTypeRef?
    let status = SecItemCopyMatching(
      query as CFDictionary,
      &result
    )
    switch status {
    case errSecSuccess:
      guard let data = result as? Data else {
        throw AppPasswordStoreError.invalidStoredPassword
      }
      return data
    case errSecItemNotFound:
      return nil
    default:
      throw AppPasswordStoreError.keychainFailure(status)
    }
  }

  private func addCredential(
    _ credential: StoredCredential
  ) throws {
    var query = baseQuery()
    query[kSecValueData as String] = try encoded(credential)
    query[kSecAttrAccessible as String] =
      kSecAttrAccessibleWhenUnlockedThisDeviceOnly

    let status = SecItemAdd(query as CFDictionary, nil)
    guard status == errSecSuccess else {
      throw AppPasswordStoreError.keychainFailure(status)
    }
  }

  private func updateCredential(
    _ credential: StoredCredential
  ) throws {
    let attributes: [String: Any] = [
      kSecValueData as String: try encoded(credential),
      kSecAttrAccessible as String:
        kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
    ]
    let status = SecItemUpdate(
      baseQuery() as CFDictionary,
      attributes as CFDictionary
    )
    guard status == errSecSuccess else {
      throw AppPasswordStoreError.keychainFailure(status)
    }
  }

  private func deleteCredential(
    allowsMissingItem: Bool = false
  ) throws {
    let status = SecItemDelete(baseQuery() as CFDictionary)
    guard
      status == errSecSuccess
        || (allowsMissingItem && status == errSecItemNotFound)
    else {
      throw AppPasswordStoreError.keychainFailure(status)
    }
  }
}
