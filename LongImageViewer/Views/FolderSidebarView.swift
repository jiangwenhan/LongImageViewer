import UIKit

struct FolderSidebarItem: Equatable {
  let folderID: UUID?
  let directoryRelativePath: String?
  let title: String
  let imageCount: Int
  let depth: Int
  let canSelect: Bool
  let canDelete: Bool
}

protocol FolderSidebarViewDelegate: AnyObject {
  func folderSidebar(
    _ sidebar: FolderSidebarView,
    didSelect item: FolderSidebarItem
  )
  func folderSidebar(
    _ sidebar: FolderSidebarView,
    didRequestDelete item: FolderSidebarItem
  )
  func folderSidebarDidRequestClose(_ sidebar: FolderSidebarView)
}

final class FolderSidebarView: UIView {
  weak var delegate: FolderSidebarViewDelegate?

  private var items: [FolderSidebarItem] = []
  private var selectedFolderID: UUID?
  private var selectedDirectoryRelativePath: String?
  private var selectsStandaloneFolder = false

  private let titleLabel: UILabel = {
    let label = UILabel()
    label.text = L("sidebar.title")
    label.textColor = .label
    label.font = .systemFont(ofSize: 24, weight: .bold)
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  private let subtitleLabel: UILabel = {
    let label = UILabel()
    label.text = L("sidebar.subtitle")
    label.textColor = .secondaryLabel
    label.font = .systemFont(ofSize: 13)
    label.numberOfLines = 0
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  private let closeButton: UIButton = {
    var configuration = UIButton.Configuration.plain()
    configuration.image = UIImage(systemName: "xmark")
    configuration.baseForegroundColor = .secondaryLabel
    let button = UIButton(configuration: configuration)
    button.accessibilityLabel = L("sidebar.close")
    button.translatesAutoresizingMaskIntoConstraints = false
    return button
  }()

  private lazy var tableView: UITableView = {
    let tableView = UITableView(
      frame: .zero,
      style: .insetGrouped
    )
    tableView.backgroundColor = .clear
    tableView.separatorStyle = .none
    tableView.rowHeight = 64
    tableView.dataSource = self
    tableView.delegate = self
    tableView.translatesAutoresizingMaskIntoConstraints = false
    return tableView
  }()

  override init(frame: CGRect) {
    super.init(frame: frame)

    backgroundColor = .systemBackground
    layer.shadowColor = UIColor.black.cgColor
    layer.shadowOpacity = 0.28
    layer.shadowRadius = 18
    layer.shadowOffset = CGSize(width: 8, height: 0)

    addSubview(titleLabel)
    addSubview(subtitleLabel)
    addSubview(closeButton)
    addSubview(tableView)

    closeButton.addTarget(
      self,
      action: #selector(closeButtonTapped),
      for: .touchUpInside
    )
    let closeSwipe = UISwipeGestureRecognizer(
      target: self,
      action: #selector(closeSwipeRecognized)
    )
    closeSwipe.direction = .left
    closeSwipe.delegate = self
    addGestureRecognizer(closeSwipe)
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(languageDidChange),
      name: AppLocalization.didChangeNotification,
      object: nil
    )

    NSLayoutConstraint.activate([
      titleLabel.leadingAnchor.constraint(
        equalTo: safeAreaLayoutGuide.leadingAnchor,
        constant: 20
      ),
      titleLabel.topAnchor.constraint(
        equalTo: safeAreaLayoutGuide.topAnchor,
        constant: 20
      ),
      titleLabel.trailingAnchor.constraint(
        lessThanOrEqualTo: closeButton.leadingAnchor,
        constant: -8
      ),

      closeButton.trailingAnchor.constraint(
        equalTo: safeAreaLayoutGuide.trailingAnchor,
        constant: -12
      ),
      closeButton.centerYAnchor.constraint(
        equalTo: titleLabel.centerYAnchor
      ),
      closeButton.widthAnchor.constraint(equalToConstant: 44),
      closeButton.heightAnchor.constraint(equalToConstant: 44),

      subtitleLabel.leadingAnchor.constraint(
        equalTo: titleLabel.leadingAnchor
      ),
      subtitleLabel.trailingAnchor.constraint(
        equalTo: safeAreaLayoutGuide.trailingAnchor,
        constant: -20
      ),
      subtitleLabel.topAnchor.constraint(
        equalTo: titleLabel.bottomAnchor,
        constant: 6
      ),

      tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
      tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
      tableView.topAnchor.constraint(
        equalTo: subtitleLabel.bottomAnchor,
        constant: 12
      ),
      tableView.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  func update(
    items: [FolderSidebarItem],
    selectedFolderID: UUID?,
    selectedDirectoryRelativePath: String?,
    selectsStandaloneFolder: Bool
  ) {
    self.items = items
    self.selectedFolderID = selectedFolderID
    self.selectedDirectoryRelativePath =
      selectedDirectoryRelativePath
    self.selectsStandaloneFolder = selectsStandaloneFolder
    tableView.reloadData()
  }

  @objc private func languageDidChange() {
    titleLabel.text = L("sidebar.title")
    subtitleLabel.text = L("sidebar.subtitle")
    closeButton.accessibilityLabel = L("sidebar.close")
    tableView.reloadData()
  }

  @objc private func closeButtonTapped() {
    delegate?.folderSidebarDidRequestClose(self)
  }

  @objc private func closeSwipeRecognized() {
    delegate?.folderSidebarDidRequestClose(self)
  }

  private func isSelected(_ item: FolderSidebarItem) -> Bool {
    if item.folderID == nil {
      return selectsStandaloneFolder
    }
    return !selectsStandaloneFolder
      && item.folderID == selectedFolderID
      && item.directoryRelativePath
        == selectedDirectoryRelativePath
  }
}

extension FolderSidebarView: UIGestureRecognizerDelegate {
  func gestureRecognizer(
    _ gestureRecognizer: UIGestureRecognizer,
    shouldReceive touch: UITouch
  ) -> Bool {
    var touchedView: UIView? = touch.view
    while let view = touchedView {
      if view === tableView {
        return false
      }
      touchedView = view.superview
    }
    return true
  }
}

extension FolderSidebarView: UITableViewDataSource {
  func tableView(
    _ tableView: UITableView,
    numberOfRowsInSection section: Int
  ) -> Int {
    items.count
  }

  func tableView(
    _ tableView: UITableView,
    cellForRowAt indexPath: IndexPath
  ) -> UITableViewCell {
    let reuseIdentifier = "FolderSidebarCell"
    let cell =
      tableView.dequeueReusableCell(
        withIdentifier: reuseIdentifier
      )
      ?? UITableViewCell(
        style: .subtitle,
        reuseIdentifier: reuseIdentifier
      )
    let item = items[indexPath.row]
    let selected = isSelected(item)

    var content = cell.defaultContentConfiguration()
    content.image = UIImage(
      systemName: selected ? "folder.fill" : "folder"
    )
    content.imageProperties.tintColor =
      selected
      ? .systemBlue
      : .secondaryLabel
    content.text = item.title
    content.directionalLayoutMargins.leading =
      item.depth == 0 ? 12 : 36
    content.textProperties.font = .systemFont(
      ofSize: 16,
      weight: selected ? .semibold : .regular
    )
    content.secondaryText = L(
      "sidebar.image_count_format",
      item.imageCount
    )
    content.secondaryTextProperties.color = .secondaryLabel
    cell.contentConfiguration = content

    var background = UIBackgroundConfiguration.listGroupedCell()
    background.backgroundColor =
      selected
      ? UIColor.systemBlue.withAlphaComponent(0.14)
      : .secondarySystemGroupedBackground
    background.cornerRadius = 12
    cell.backgroundConfiguration = background
    cell.accessoryType = selected ? .checkmark : .none
    cell.tintColor = .systemBlue
    cell.selectionStyle = .none
    cell.isUserInteractionEnabled = item.canSelect || item.canDelete
    cell.contentView.alpha = item.canSelect ? 1 : 0.52
    cell.accessibilityValue =
      selected ? L("sidebar.current") : nil
    return cell
  }
}

extension FolderSidebarView: UITableViewDelegate {
  func tableView(
    _ tableView: UITableView,
    didSelectRowAt indexPath: IndexPath
  ) {
    let item = items[indexPath.row]
    guard item.canSelect else { return }
    delegate?.folderSidebar(self, didSelect: item)
  }

  func tableView(
    _ tableView: UITableView,
    trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
  ) -> UISwipeActionsConfiguration? {
    let item = items[indexPath.row]
    guard item.canDelete else { return nil }
    let deleteAction = UIContextualAction(
      style: .destructive,
      title: L("common.delete")
    ) { [weak self] _, _, completion in
      guard let self else {
        completion(false)
        return
      }
      self.delegate?.folderSidebar(
        self,
        didRequestDelete: item
      )
      completion(true)
    }
    deleteAction.image = UIImage(systemName: "trash")
    let configuration = UISwipeActionsConfiguration(
      actions: [deleteAction]
    )
    configuration.performsFirstActionWithFullSwipe = false
    return configuration
  }
}
