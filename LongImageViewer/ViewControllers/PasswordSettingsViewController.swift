import UIKit

final class PasswordSettingsViewController:
  UIViewController,
  UITextFieldDelegate
{
  enum Mode {
    case setup
    case manage
  }

  var onPasswordStateChanged: ((Bool) -> Void)?

  private let mode: Mode
  private let passwordStore: AppPasswordStore
  private let passwordQueue = DispatchQueue(
    label: "com.trae.LongImageViewer.password-settings",
    qos: .userInitiated
  )
  private var isSaving = false

  private lazy var currentPasswordField = makePasswordField(
    placeholder: L("password.current"),
    contentType: .password,
    returnKeyType: .next
  )
  private lazy var newPasswordField = makePasswordField(
    placeholder: L("password.new"),
    contentType: .newPassword,
    returnKeyType: .next
  )
  private lazy var confirmationField = makePasswordField(
    placeholder: L("password.confirm"),
    contentType: .newPassword,
    returnKeyType: .done
  )

  private let errorLabel: UILabel = {
    let label = UILabel()
    label.font = .systemFont(ofSize: 14)
    label.textColor = .systemRed
    label.numberOfLines = 0
    label.textAlignment = .center
    label.isHidden = true
    return label
  }()

  private let primaryButton: UIButton = {
    var configuration = UIButton.Configuration.filled()
    configuration.cornerStyle = .large
    configuration.baseBackgroundColor = .systemBlue
    let button = UIButton(configuration: configuration)
    button.translatesAutoresizingMaskIntoConstraints = false
    return button
  }()

  private let disablePasswordButton: UIButton = {
    var configuration = UIButton.Configuration.plain()
    configuration.title = L("password.disable")
    configuration.baseForegroundColor = .systemRed
    let button = UIButton(configuration: configuration)
    button.translatesAutoresizingMaskIntoConstraints = false
    return button
  }()

  private let descriptionLabel: UILabel = {
    let label = UILabel()
    label.font = .systemFont(ofSize: 15)
    label.textColor = .secondaryLabel
    label.textAlignment = .center
    label.numberOfLines = 0
    return label
  }()

  init(
    mode: Mode,
    passwordStore: AppPasswordStore = .shared
  ) {
    self.mode = mode
    self.passwordStore = passwordStore
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemGroupedBackground
    setupViews()
    setupActions()
    applyLocalization()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(languageDidChange),
      name: AppLocalization.didChangeNotification,
      object: nil
    )
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    if mode == .setup {
      newPasswordField.becomeFirstResponder()
    } else {
      currentPasswordField.becomeFirstResponder()
    }
  }

  func textFieldShouldReturn(_ textField: UITextField) -> Bool {
    if textField === currentPasswordField {
      newPasswordField.becomeFirstResponder()
    } else if textField === newPasswordField {
      confirmationField.becomeFirstResponder()
    } else {
      savePassword()
    }
    return false
  }

  private func setupViews() {
    let scrollView = UIScrollView()
    scrollView.keyboardDismissMode = .interactive
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(scrollView)

    let contentView = UIView()
    contentView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.addSubview(contentView)

    let iconConfiguration = UIImage.SymbolConfiguration(
      pointSize: 38,
      weight: .semibold
    )
    let iconView = UIImageView(
      image: UIImage(
        systemName: mode == .setup ? "lock.badge.plus" : "lock.rotation",
        withConfiguration: iconConfiguration
      )
    )
    iconView.tintColor = .systemBlue
    iconView.contentMode = .scaleAspectFit

    currentPasswordField.isHidden = mode == .setup
    disablePasswordButton.isHidden = mode == .setup

    let stack = UIStackView(
      arrangedSubviews: [
        iconView,
        descriptionLabel,
        currentPasswordField,
        newPasswordField,
        confirmationField,
        errorLabel,
        primaryButton,
        disablePasswordButton,
      ]
    )
    stack.axis = .vertical
    stack.spacing = 14
    stack.setCustomSpacing(24, after: descriptionLabel)
    stack.setCustomSpacing(8, after: errorLabel)
    stack.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(stack)

    NSLayoutConstraint.activate([
      scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      scrollView.topAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.topAnchor
      ),
      scrollView.bottomAnchor.constraint(
        equalTo: view.keyboardLayoutGuide.topAnchor
      ),

      contentView.leadingAnchor.constraint(
        equalTo: scrollView.contentLayoutGuide.leadingAnchor
      ),
      contentView.trailingAnchor.constraint(
        equalTo: scrollView.contentLayoutGuide.trailingAnchor
      ),
      contentView.topAnchor.constraint(
        equalTo: scrollView.contentLayoutGuide.topAnchor
      ),
      contentView.bottomAnchor.constraint(
        equalTo: scrollView.contentLayoutGuide.bottomAnchor
      ),
      contentView.widthAnchor.constraint(
        equalTo: scrollView.frameLayoutGuide.widthAnchor
      ),

      stack.leadingAnchor.constraint(
        equalTo: contentView.leadingAnchor,
        constant: 24
      ),
      stack.trailingAnchor.constraint(
        equalTo: contentView.trailingAnchor,
        constant: -24
      ),
      stack.topAnchor.constraint(
        equalTo: contentView.topAnchor,
        constant: 28
      ),
      stack.bottomAnchor.constraint(
        equalTo: contentView.bottomAnchor,
        constant: -24
      ),

      iconView.heightAnchor.constraint(equalToConstant: 58),
      currentPasswordField.heightAnchor.constraint(equalToConstant: 50),
      newPasswordField.heightAnchor.constraint(equalToConstant: 50),
      confirmationField.heightAnchor.constraint(equalToConstant: 50),
      primaryButton.heightAnchor.constraint(equalToConstant: 50),
      disablePasswordButton.heightAnchor.constraint(
        equalToConstant: 44
      ),
    ])
  }

  private func setupActions() {
    currentPasswordField.delegate = self
    newPasswordField.delegate = self
    confirmationField.delegate = self
    [currentPasswordField, newPasswordField, confirmationField]
      .forEach { field in
        field.addTarget(
          self,
          action: #selector(passwordFieldChanged),
          for: .editingChanged
        )
      }

    primaryButton.addTarget(
      self,
      action: #selector(savePassword),
      for: .touchUpInside
    )
    disablePasswordButton.addTarget(
      self,
      action: #selector(confirmDisablePassword),
      for: .touchUpInside
    )
  }

  @objc private func languageDidChange() {
    applyLocalization()
  }

  private func applyLocalization() {
    title =
      mode == .setup
      ? L("password.setup_title")
      : L("password.manage_title")
    navigationItem.leftBarButtonItem = UIBarButtonItem(
      title: L("common.cancel"),
      primaryAction: UIAction { [weak self] _ in
        self?.dismiss(animated: true)
      }
    )
    currentPasswordField.placeholder = L("password.current")
    newPasswordField.placeholder = L("password.new")
    confirmationField.placeholder = L("password.confirm")
    descriptionLabel.text =
      mode == .setup
      ? L("password.setup_description")
      : L("password.manage_description")
    primaryButton.configuration?.title =
      mode == .setup
      ? L("password.set")
      : L("password.change")
    disablePasswordButton.configuration?.title = L(
      "password.disable"
    )
  }

  private func makePasswordField(
    placeholder: String,
    contentType: UITextContentType,
    returnKeyType: UIReturnKeyType
  ) -> UITextField {
    let field = UITextField()
    field.placeholder = placeholder
    field.isSecureTextEntry = true
    field.textContentType = contentType
    field.returnKeyType = returnKeyType
    field.autocapitalizationType = .none
    field.autocorrectionType = .no
    field.clearButtonMode = .whileEditing
    field.backgroundColor = .secondarySystemGroupedBackground
    field.layer.cornerRadius = 12
    field.layer.cornerCurve = .continuous
    field.layer.borderWidth = 1
    field.layer.borderColor = UIColor.separator.cgColor
    field.font = .systemFont(ofSize: 17)

    let spacer = UIView(
      frame: CGRect(x: 0, y: 0, width: 14, height: 1)
    )
    field.leftView = spacer
    field.leftViewMode = .always
    return field
  }

  @objc private func passwordFieldChanged() {
    showError(nil)
  }

  @objc private func savePassword() {
    guard !isSaving else { return }
    let newPassword = newPasswordField.text ?? ""
    let confirmation = confirmationField.text ?? ""
    guard validate(
      newPassword: newPassword,
      confirmation: confirmation
    ) else {
      return
    }

    let currentPassword = currentPasswordField.text ?? ""
    if mode == .manage, currentPassword.isEmpty {
      showError(L("password.enter_current"))
      currentPasswordField.becomeFirstResponder()
      return
    }

    setBusy(true)
    passwordQueue.async { [weak self] in
      guard let self else { return }
      let result: Result<Bool, Error> = Result {
        switch self.mode {
        case .setup:
          try self.passwordStore.setPassword(newPassword)
          return true
        case .manage:
          return try self.passwordStore.changePassword(
            currentPassword: currentPassword,
            newPassword: newPassword
          )
        }
      }

      DispatchQueue.main.async {
        self.setBusy(false)
        switch result {
        case .success(true):
          self.onPasswordStateChanged?(true)
          self.dismiss(animated: true)
        case .success(false):
          self.currentPasswordField.text = nil
          self.showError(L("password.current_incorrect"))
          self.currentPasswordField.becomeFirstResponder()
        case .failure(let error):
          self.showError(error.localizedDescription)
        }
      }
    }
  }

  private func validate(
    newPassword: String,
    confirmation: String
  ) -> Bool {
    guard (4...64).contains(newPassword.count) else {
      showError(L("password.length"))
      newPasswordField.becomeFirstResponder()
      return false
    }
    guard newPassword == confirmation else {
      showError(L("password.mismatch"))
      confirmationField.becomeFirstResponder()
      return false
    }
    return true
  }

  @objc private func confirmDisablePassword() {
    guard !isSaving else { return }
    let currentPassword = currentPasswordField.text ?? ""
    guard !currentPassword.isEmpty else {
      showError(L("password.enter_current_disable"))
      currentPasswordField.becomeFirstResponder()
      return
    }

    let alert = UIAlertController(
      title: L("password.disable_title"),
      message: L("password.disable_message"),
      preferredStyle: .alert
    )
    alert.addAction(
      UIAlertAction(title: L("common.cancel"), style: .cancel)
    )
    alert.addAction(
      UIAlertAction(
        title: L("password.disable_confirm"),
        style: .destructive
      ) { [weak self] _ in
        self?.disablePassword(currentPassword: currentPassword)
      }
    )
    present(alert, animated: true)
  }

  private func disablePassword(currentPassword: String) {
    setBusy(true)
    passwordQueue.async { [weak self] in
      guard let self else { return }
      let result = Result {
        try self.passwordStore.removePassword(
          currentPassword: currentPassword
        )
      }

      DispatchQueue.main.async {
        self.setBusy(false)
        switch result {
        case .success(true):
          self.onPasswordStateChanged?(false)
          self.dismiss(animated: true)
        case .success(false):
          self.currentPasswordField.text = nil
          self.showError(L("password.current_incorrect"))
          self.currentPasswordField.becomeFirstResponder()
        case .failure(let error):
          self.showError(error.localizedDescription)
        }
      }
    }
  }

  private func setBusy(_ busy: Bool) {
    isSaving = busy
    currentPasswordField.isEnabled = !busy
    newPasswordField.isEnabled = !busy
    confirmationField.isEnabled = !busy
    primaryButton.isEnabled = !busy
    disablePasswordButton.isEnabled = !busy
    primaryButton.configuration?.showsActivityIndicator = busy
  }

  private func showError(_ message: String?) {
    errorLabel.text = message
    errorLabel.isHidden = message == nil
  }
}
