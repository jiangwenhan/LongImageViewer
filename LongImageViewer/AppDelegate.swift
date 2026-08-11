import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
  var window: UIWindow?

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let passwordStore = AppPasswordStore.shared
    #if DEBUG
      preparePasswordTestingIfRequested(passwordStore)
    #endif

    let window = UIWindow(frame: UIScreen.main.bounds)
    let viewerViewController = ViewerViewController()
    let lockViewController = AppLockViewController(
      contentViewController: viewerViewController,
      passwordStore: passwordStore
    )
    viewerViewController.onPasswordSettingsRequested = {
      [weak lockViewController] in
      lockViewController?.presentPasswordSettings()
    }
    window.rootViewController = lockViewController
    window.makeKeyAndVisible()
    self.window = window
    return true
  }

  #if DEBUG
    private func preparePasswordTestingIfRequested(
      _ passwordStore: AppPasswordStore
    ) {
      let arguments = ProcessInfo.processInfo.arguments

      if arguments.contains("--reset-app-password") {
        try? passwordStore.resetForTesting()
      }

      if
        let index = arguments.firstIndex(
          of: "--install-debug-app-password"
        ),
        arguments.indices.contains(index + 1)
      {
        do {
          if try passwordStore.hasPassword() {
            try passwordStore.resetForTesting()
          }
          try passwordStore.setPassword(arguments[index + 1])
        } catch {
          writePasswordStoreTestResult([
            "status": "setup-failed",
            "error": error.localizedDescription,
          ])
        }
      }

      guard arguments.contains("--password-store-smoke-test") else {
        return
      }

      do {
        try passwordStore.resetForTesting()
        try passwordStore.setPassword("Initial#123")
        let initialPasswordWorks = try passwordStore.verify(
          "Initial#123"
        )
        let wrongPasswordRejected = try !passwordStore.verify(
          "Wrong#123"
        )
        let passwordChanged = try passwordStore.changePassword(
          currentPassword: "Initial#123",
          newPassword: "Updated#456"
        )
        let oldPasswordRejected = try !passwordStore.verify(
          "Initial#123"
        )
        let newPasswordWorks = try passwordStore.verify(
          "Updated#456"
        )
        let passwordRemoved = try passwordStore.removePassword(
          currentPassword: "Updated#456"
        )
        let hasPasswordAfterRemoval = try passwordStore.hasPassword()

        let passed =
          initialPasswordWorks
          && wrongPasswordRejected
          && passwordChanged
          && oldPasswordRejected
          && newPasswordWorks
          && passwordRemoved
          && !hasPasswordAfterRemoval
        writePasswordStoreTestResult([
          "status": passed ? "passed" : "failed",
          "initialPasswordWorks": initialPasswordWorks,
          "wrongPasswordRejected": wrongPasswordRejected,
          "passwordChanged": passwordChanged,
          "oldPasswordRejected": oldPasswordRejected,
          "newPasswordWorks": newPasswordWorks,
          "passwordRemoved": passwordRemoved,
          "hasPasswordAfterRemoval": hasPasswordAfterRemoval,
        ])
      } catch {
        writePasswordStoreTestResult([
          "status": "failed",
          "error": error.localizedDescription,
        ])
      }
    }

    private func writePasswordStoreTestResult(
      _ result: [String: Any]
    ) {
      let documentsURL = FileManager.default.urls(
        for: .documentDirectory,
        in: .userDomainMask
      )[0]
      let resultURL = documentsURL.appendingPathComponent(
        "password-store-result.json"
      )
      guard
        let data = try? JSONSerialization.data(
          withJSONObject: result,
          options: [.prettyPrinted, .sortedKeys]
        )
      else {
        return
      }
      try? data.write(to: resultURL, options: .atomic)
    }
  #endif
}
