import Foundation

enum AppLanguage: String, CaseIterable {
  case english = "en"
  case simplifiedChinese = "zh-Hans"
  case japanese = "ja"

  var nativeDisplayName: String {
    switch self {
    case .english:
      return "English"
    case .simplifiedChinese:
      return "简体中文"
    case .japanese:
      return "日本語"
    }
  }

  static func preferredLanguage() -> AppLanguage {
    for identifier in Locale.preferredLanguages {
      if identifier.hasPrefix("zh") {
        return .simplifiedChinese
      }
      if identifier.hasPrefix("ja") {
        return .japanese
      }
      if identifier.hasPrefix("en") {
        return .english
      }
    }
    return .english
  }
}

final class AppLocalization {
  static let shared = AppLocalization()
  static let didChangeNotification = Notification.Name(
    "AppLocalizationDidChange"
  )

  private static let storageKey = "selectedAppLanguage"

  private(set) var language: AppLanguage
  private var languageBundle: Bundle

  private init() {
    let savedLanguage =
      UserDefaults.standard.string(forKey: Self.storageKey)
      .flatMap(AppLanguage.init(rawValue:))
    language = savedLanguage ?? AppLanguage.preferredLanguage()
    languageBundle = Self.bundle(for: language)
  }

  func setLanguage(_ language: AppLanguage) {
    guard self.language != language else { return }
    self.language = language
    languageBundle = Self.bundle(for: language)
    UserDefaults.standard.set(
      language.rawValue,
      forKey: Self.storageKey
    )
    NotificationCenter.default.post(
      name: Self.didChangeNotification,
      object: language
    )
  }

  func string(
    _ key: String,
    arguments: [CVarArg] = []
  ) -> String {
    let format = languageBundle.localizedString(
      forKey: key,
      value: key,
      table: nil
    )
    guard !arguments.isEmpty else { return format }
    return String(
      format: format,
      locale: Locale(identifier: language.rawValue),
      arguments: arguments
    )
  }

  private static func bundle(for language: AppLanguage) -> Bundle {
    guard
      let path = Bundle.main.path(
        forResource: language.rawValue,
        ofType: "lproj"
      ),
      let bundle = Bundle(path: path)
    else {
      return .main
    }
    return bundle
  }
}

func L(_ key: String, _ arguments: CVarArg...) -> String {
  AppLocalization.shared.string(key, arguments: arguments)
}
