import UIKit

final class AppLockViewController: UIViewController {
  private static let relockGraceInterval: TimeInterval = 3 * 60

  private let contentViewController: UIViewController
  private let passwordStore: AppPasswordStore
  private let authenticationQueue = DispatchQueue(
    label: "com.trae.LongImageViewer.password-authentication",
    qos: .userInitiated
  )
  private let startsLocked: Bool
  private let initialProtectionError: String?
  private var isLocked = false
  private var isAuthenticating = false
  private var backgroundedAt: TimeInterval?
  private var mayResumeWithoutPassword = false

  private let lockView = AppLockView()
  private let privacyTitleLabel: UILabel = {
    let label = UILabel()
    label.text = L("lock.privacy_title")
    label.font = .systemFont(ofSize: 22, weight: .bold)
    label.textAlignment = .center
    return label
  }()
  private lazy var privacyView: UIView = {
    let view = UIView()
    view.backgroundColor = .systemBackground
    view.translatesAutoresizingMaskIntoConstraints = false

    let configuration = UIImage.SymbolConfiguration(
      pointSize: 38,
      weight: .semibold
    )
    let iconView = UIImageView(
      image: UIImage(
        systemName: "lock.fill",
        withConfiguration: configuration
      )
    )
    iconView.tintColor = .systemBlue
    iconView.contentMode = .scaleAspectFit

    let stack = UIStackView(
      arrangedSubviews: [iconView, privacyTitleLabel]
    )
    stack.axis = .vertical
    stack.alignment = .center
    stack.spacing = 14
    stack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      iconView.widthAnchor.constraint(equalToConstant: 56),
      iconView.heightAnchor.constraint(equalToConstant: 56),
    ])
    return view
  }()

  init(
    contentViewController: UIViewController,
    passwordStore: AppPasswordStore = .shared
  ) {
    self.contentViewController = contentViewController
    self.passwordStore = passwordStore
    do {
      startsLocked = try passwordStore.hasPassword()
      initialProtectionError = nil
    } catch {
      startsLocked = true
      initialProtectionError = error.localizedDescription
    }
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black

    addChild(contentViewController)
    contentViewController.view.translatesAutoresizingMaskIntoConstraints =
      false
    view.addSubview(contentViewController.view)
    NSLayoutConstraint.activate([
      contentViewController.view.leadingAnchor.constraint(
        equalTo: view.leadingAnchor
      ),
      contentViewController.view.trailingAnchor.constraint(
        equalTo: view.trailingAnchor
      ),
      contentViewController.view.topAnchor.constraint(
        equalTo: view.topAnchor
      ),
      contentViewController.view.bottomAnchor.constraint(
        equalTo: view.bottomAnchor
      ),
    ])
    contentViewController.didMove(toParent: self)

    lockView.onSubmit = { [weak self] password in
      self?.unlock(using: password)
    }

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(applicationWillResignActive),
      name: UIApplication.willResignActiveNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(applicationDidEnterBackground),
      name: UIApplication.didEnterBackgroundNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(applicationDidBecomeActive),
      name: UIApplication.didBecomeActiveNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(languageDidChange),
      name: AppLocalization.didChangeNotification,
      object: nil
    )
    applyLocalization()

    if startsLocked {
      activateLock(errorMessage: initialProtectionError)
    }
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    if isLocked {
      attachLockViewToTopLevelWindow()
      lockView.focusPasswordField()
    }

    #if DEBUG
      reportDebugLockStateIfRequested()
    #endif
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  @objc private func languageDidChange() {
    applyLocalization()
  }

  private func applyLocalization() {
    privacyTitleLabel.text = L("lock.privacy_title")
    lockView.applyLocalization()
  }

  func presentPasswordSettings() {
    guard !isLocked else { return }

    let hasPassword: Bool
    do {
      hasPassword = try passwordStore.hasPassword()
    } catch {
      presentError(error)
      return
    }

    let settings = PasswordSettingsViewController(
      mode: hasPassword ? .manage : .setup,
      passwordStore: passwordStore
    )
    settings.onPasswordStateChanged = { [weak self] hasPassword in
      guard let self else { return }
      if !hasPassword {
        self.backgroundedAt = nil
        self.mayResumeWithoutPassword = false
        self.removePrivacyView()
        self.deactivateLock()
      }
    }
    let navigationController = UINavigationController(
      rootViewController: settings
    )
    navigationController.modalPresentationStyle = .formSheet

    DispatchQueue.main.asyncAfter(
      deadline: .now() + 0.2
    ) { [weak self] in
      guard let self else { return }
      self.topViewController().present(
        navigationController,
        animated: true
      )
    }
  }

  @objc private func applicationWillResignActive() {
    do {
      if try passwordStore.hasPassword() {
        attachPrivacyView()
      }
    } catch {
      activateLock(errorMessage: error.localizedDescription)
    }
  }

  @objc private func applicationDidEnterBackground() {
    do {
      if try passwordStore.hasPassword() {
        backgroundedAt = ProcessInfo.processInfo.systemUptime
        mayResumeWithoutPassword = !isLocked
      }
    } catch {
      backgroundedAt = ProcessInfo.processInfo.systemUptime
      mayResumeWithoutPassword = false
      activateLock(errorMessage: error.localizedDescription)
    }
  }

  @objc private func applicationDidBecomeActive() {
    removePrivacyView()

    do {
      guard try passwordStore.hasPassword() else {
        backgroundedAt = nil
        mayResumeWithoutPassword = false
        deactivateLock()
        return
      }

      if let backgroundedAt {
        let requiresAuthentication =
          Self.shouldRequireAuthentication(
            backgroundedAt: backgroundedAt,
            now: ProcessInfo.processInfo.systemUptime
          )
        let canResume =
          mayResumeWithoutPassword && !requiresAuthentication
        self.backgroundedAt = nil
        mayResumeWithoutPassword = false

        if canResume {
          deactivateLock()
        } else {
          activateLock(errorMessage: nil)
        }
      } else if isLocked {
        activateLock(errorMessage: nil)
      }
    } catch {
      activateLock(errorMessage: error.localizedDescription)
    }

    guard isLocked else { return }
    attachLockViewToTopLevelWindow()
    DispatchQueue.main.asyncAfter(
      deadline: .now() + 0.25
    ) { [weak self] in
      self?.lockView.focusPasswordField()
    }
  }

  private static func shouldRequireAuthentication(
    backgroundedAt: TimeInterval,
    now: TimeInterval
  ) -> Bool {
    now - backgroundedAt >= relockGraceInterval
  }

  private func activateLock(errorMessage: String?) {
    isLocked = true
    isAuthenticating = false
    lockView.clearPassword()
    lockView.setBusy(false)
    if let errorMessage {
      lockView.showError(
        L("lock.read_error_format", errorMessage)
      )
    } else {
      lockView.showError(nil)
    }

    if isViewLoaded {
      attachLockView(to: view.window ?? view)
    }
  }

  private func deactivateLock() {
    isLocked = false
    isAuthenticating = false
    lockView.resignPasswordField()
    lockView.removeFromSuperview()
  }

  private func attachLockViewToTopLevelWindow() {
    attachLockView(to: view.window ?? view)
  }

  private func attachPrivacyView() {
    guard isViewLoaded else { return }
    guard let hostView = view.window ?? view else { return }
    if privacyView.superview === hostView {
      hostView.bringSubviewToFront(privacyView)
      return
    }

    privacyView.removeFromSuperview()
    hostView.addSubview(privacyView)
    NSLayoutConstraint.activate([
      privacyView.leadingAnchor.constraint(
        equalTo: hostView.leadingAnchor
      ),
      privacyView.trailingAnchor.constraint(
        equalTo: hostView.trailingAnchor
      ),
      privacyView.topAnchor.constraint(equalTo: hostView.topAnchor),
      privacyView.bottomAnchor.constraint(equalTo: hostView.bottomAnchor),
    ])
  }

  private func removePrivacyView() {
    privacyView.removeFromSuperview()
  }

  private func attachLockView(to hostView: UIView) {
    if lockView.superview === hostView {
      hostView.bringSubviewToFront(lockView)
      return
    }

    lockView.removeFromSuperview()
    lockView.translatesAutoresizingMaskIntoConstraints = false
    hostView.addSubview(lockView)
    NSLayoutConstraint.activate([
      lockView.leadingAnchor.constraint(
        equalTo: hostView.leadingAnchor
      ),
      lockView.trailingAnchor.constraint(
        equalTo: hostView.trailingAnchor
      ),
      lockView.topAnchor.constraint(equalTo: hostView.topAnchor),
      lockView.bottomAnchor.constraint(equalTo: hostView.bottomAnchor),
    ])
  }

  private func unlock(using password: String) {
    guard !isAuthenticating else { return }
    guard !password.isEmpty else {
      lockView.showError(L("lock.enter_password"))
      return
    }

    isAuthenticating = true
    lockView.setBusy(true)
    authenticationQueue.async { [weak self] in
      guard let self else { return }
      let result = Result {
        try self.passwordStore.verify(password)
      }

      DispatchQueue.main.async {
        self.isAuthenticating = false
        self.lockView.setBusy(false)
        switch result {
        case .success(true):
          self.deactivateLock()
        case .success(false):
          self.lockView.clearPassword()
          self.lockView.showError(L("lock.incorrect"))
          self.lockView.focusPasswordField()
        case .failure(let error):
          self.lockView.showError(
            L(
              "lock.verify_error_format",
              error.localizedDescription
            )
          )
        }
      }
    }
  }

  private func topViewController() -> UIViewController {
    var current: UIViewController = self
    while let presented = current.presentedViewController {
      current = presented
    }
    if let navigation = current as? UINavigationController {
      return navigation.visibleViewController ?? navigation
    }
    return current
  }

  private func presentError(_ error: Error) {
    let alert = UIAlertController(
      title: L("lock.settings_error_title"),
      message: error.localizedDescription,
      preferredStyle: .alert
    )
    alert.addAction(
      UIAlertAction(title: L("common.ok"), style: .default)
    )
    topViewController().present(alert, animated: true)
  }

  #if DEBUG
    private func reportDebugLockStateIfRequested() {
      guard
        ProcessInfo.processInfo.arguments.contains(
          "--report-app-lock-state"
        )
      else {
        return
      }

      let hasPassword = (try? passwordStore.hasPassword()) ?? false
      let now = ProcessInfo.processInfo.systemUptime
      let shortBackgroundRequiresPassword =
        Self.shouldRequireAuthentication(
          backgroundedAt: now - 179,
          now: now
        )
      let expiredBackgroundRequiresPassword =
        Self.shouldRequireAuthentication(
          backgroundedAt: now - 180,
          now: now
        )
      let result: [String: Any] = [
        "status":
          isLocked
            && hasPassword
            && !shortBackgroundRequiresPassword
            && expiredBackgroundRequiresPassword
          ? "passed" : "failed",
        "isLocked": isLocked,
        "hasPassword": hasPassword,
        "gracePeriodSeconds": Self.relockGraceInterval,
        "shortBackgroundRequiresPassword":
          shortBackgroundRequiresPassword,
        "expiredBackgroundRequiresPassword":
          expiredBackgroundRequiresPassword,
      ]
      let documentsURL = FileManager.default.urls(
        for: .documentDirectory,
        in: .userDomainMask
      )[0]
      let resultURL = documentsURL.appendingPathComponent(
        "app-lock-result.json"
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

private final class AppLockView: UIView, UITextFieldDelegate {
  var onSubmit: ((String) -> Void)?

  private let passwordField: UITextField = {
    let field = UITextField()
    field.placeholder = L("lock.password_placeholder")
    field.isSecureTextEntry = true
    field.textContentType = .password
    field.autocapitalizationType = .none
    field.autocorrectionType = .no
    field.clearButtonMode = .whileEditing
    field.returnKeyType = .go
    field.backgroundColor = .secondarySystemBackground
    field.layer.cornerRadius = 12
    field.layer.cornerCurve = .continuous
    field.layer.borderWidth = 1
    field.layer.borderColor = UIColor.separator.cgColor
    field.font = .systemFont(ofSize: 17)
    field.accessibilityIdentifier = "appPasswordField"

    let spacer = UIView(
      frame: CGRect(x: 0, y: 0, width: 14, height: 1)
    )
    field.leftView = spacer
    field.leftViewMode = .always
    field.translatesAutoresizingMaskIntoConstraints = false
    return field
  }()

  private let unlockButton: UIButton = {
    var configuration = UIButton.Configuration.filled()
    configuration.title = L("lock.unlock")
    configuration.cornerStyle = .large
    configuration.baseBackgroundColor = .systemBlue
    let button = UIButton(configuration: configuration)
    button.accessibilityIdentifier = "unlockAppButton"
    button.translatesAutoresizingMaskIntoConstraints = false
    return button
  }()

  private let errorLabel: UILabel = {
    let label = UILabel()
    label.font = .systemFont(ofSize: 14)
    label.textColor = .systemRed
    label.textAlignment = .center
    label.numberOfLines = 0
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  private let titleLabel: UILabel = {
    let label = UILabel()
    label.text = L("lock.title")
    label.font = .systemFont(ofSize: 26, weight: .bold)
    label.textAlignment = .center
    return label
  }()

  private let subtitleLabel: UILabel = {
    let label = UILabel()
    label.text = L("lock.subtitle")
    label.font = .systemFont(ofSize: 15)
    label.textColor = .secondaryLabel
    label.textAlignment = .center
    return label
  }()

  override init(frame: CGRect) {
    super.init(frame: frame)
    accessibilityIdentifier = "appLockView"
    backgroundColor = .systemBackground
    setupViews()
    passwordField.delegate = self
    passwordField.addTarget(
      self,
      action: #selector(passwordChanged),
      for: .editingChanged
    )
    unlockButton.addTarget(
      self,
      action: #selector(submitPassword),
      for: .touchUpInside
    )
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func clearPassword() {
    passwordField.text = nil
  }

  func focusPasswordField() {
    passwordField.becomeFirstResponder()
  }

  func resignPasswordField() {
    passwordField.resignFirstResponder()
  }

  func showError(_ message: String?) {
    errorLabel.text = message
    errorLabel.isHidden = message == nil
  }

  func setBusy(_ busy: Bool) {
    passwordField.isEnabled = !busy
    unlockButton.isEnabled = !busy
    unlockButton.configuration?.showsActivityIndicator = busy
  }

  func applyLocalization() {
    passwordField.placeholder = L("lock.password_placeholder")
    unlockButton.configuration?.title = L("lock.unlock")
    titleLabel.text = L("lock.title")
    subtitleLabel.text = L("lock.subtitle")
  }

  func textFieldShouldReturn(_ textField: UITextField) -> Bool {
    submitPassword()
    return false
  }

  @objc private func passwordChanged() {
    showError(nil)
  }

  @objc private func submitPassword() {
    onSubmit?(passwordField.text ?? "")
  }

  private func setupViews() {
    let iconConfiguration = UIImage.SymbolConfiguration(
      pointSize: 44,
      weight: .semibold
    )
    let iconView = UIImageView(
      image: UIImage(
        systemName: "lock.fill",
        withConfiguration: iconConfiguration
      )
    )
    iconView.tintColor = .systemBlue
    iconView.contentMode = .scaleAspectFit

    let stack = UIStackView(
      arrangedSubviews: [
        iconView,
        titleLabel,
        subtitleLabel,
        passwordField,
        errorLabel,
        unlockButton,
      ]
    )
    stack.axis = .vertical
    stack.alignment = .fill
    stack.spacing = 14
    stack.setCustomSpacing(22, after: subtitleLabel)
    stack.setCustomSpacing(8, after: passwordField)
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)

    let responsiveWidth = stack.widthAnchor.constraint(
      equalTo: safeAreaLayoutGuide.widthAnchor,
      constant: -56
    )
    responsiveWidth.priority = .defaultHigh

    NSLayoutConstraint.activate([
      stack.centerXAnchor.constraint(equalTo: centerXAnchor),
      stack.centerYAnchor.constraint(
        equalTo: safeAreaLayoutGuide.centerYAnchor,
        constant: -30
      ),
      stack.leadingAnchor.constraint(
        greaterThanOrEqualTo: safeAreaLayoutGuide.leadingAnchor,
        constant: 28
      ),
      stack.trailingAnchor.constraint(
        lessThanOrEqualTo: safeAreaLayoutGuide.trailingAnchor,
        constant: -28
      ),
      responsiveWidth,
      stack.widthAnchor.constraint(greaterThanOrEqualToConstant: 264),
      stack.widthAnchor.constraint(lessThanOrEqualToConstant: 420),
      passwordField.heightAnchor.constraint(equalToConstant: 52),
      unlockButton.heightAnchor.constraint(equalToConstant: 50),
      errorLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 18),
      iconView.heightAnchor.constraint(equalToConstant: 64),
    ])
  }
}
