import UIKit

enum SidebarMediaMode: Int {
  case images
  case videos
}

struct FolderSidebarItem: Equatable {
  let folderID: UUID?
  let directoryRelativePath: String?
  let title: String
  let imageCount: Int
  let depth: Int
  let hasChildren: Bool
  let canSelect: Bool
  let canDelete: Bool
}

enum VideoSidebarItemKind: Equatable {
  case folder
  case video
}

struct VideoSidebarItem: Equatable {
  let folderID: UUID
  let relativePath: String?
  let title: String
  let videoCount: Int
  let depth: Int
  let kind: VideoSidebarItemKind
  let hasChildren: Bool
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
  func folderSidebar(
    _ sidebar: FolderSidebarView,
    didChangeMode mode: SidebarMediaMode
  )
  func folderSidebar(
    _ sidebar: FolderSidebarView,
    didSelectVideo item: VideoSidebarItem
  )
  func folderSidebar(
    _ sidebar: FolderSidebarView,
    didRequestDeleteVideo item: VideoSidebarItem
  )
  func folderSidebarDidRequestClose(_ sidebar: FolderSidebarView)
}

final class FolderSidebarView: UIView {
  weak var delegate: FolderSidebarViewDelegate?

  private var items: [FolderSidebarItem] = []
  private var videoItems: [VideoSidebarItem] = []
  private var collapsedFolderIDs: Set<UUID> = []
  private var collapsedVideoDirectoryKeys: Set<String> = []
  private var selectedFolderID: UUID?
  private var selectedDirectoryRelativePath: String?
  private var selectsStandaloneFolder = false
  private var selectedVideoFolderID: UUID?
  private var selectedVideoRelativePath: String?
  private(set) var mode: SidebarMediaMode = .images

  private let titleLabel: UILabel = {
    let label = UILabel()
    label.text = L("sidebar.library_title")
    label.textColor = .label
    label.font = .systemFont(ofSize: 24, weight: .bold)
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  private let subtitleLabel: UILabel = {
    let label = UILabel()
    label.text = L("sidebar.images_subtitle")
    label.textColor = .secondaryLabel
    label.font = .systemFont(ofSize: 13)
    label.numberOfLines = 0
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  private lazy var mediaControl: UISegmentedControl = {
    let control = UISegmentedControl(
      items: [
        L("sidebar.images_tab"),
        L("sidebar.videos_tab"),
      ]
    )
    control.selectedSegmentIndex = mode.rawValue
    control.addTarget(
      self,
      action: #selector(mediaControlChanged),
      for: .valueChanged
    )
    control.translatesAutoresizingMaskIntoConstraints = false
    return control
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
    addSubview(mediaControl)
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

      mediaControl.leadingAnchor.constraint(
        equalTo: titleLabel.leadingAnchor
      ),
      mediaControl.trailingAnchor.constraint(
        equalTo: safeAreaLayoutGuide.trailingAnchor,
        constant: -20
      ),
      mediaControl.topAnchor.constraint(
        equalTo: titleLabel.bottomAnchor,
        constant: 14
      ),
      mediaControl.heightAnchor.constraint(equalToConstant: 34),

      subtitleLabel.leadingAnchor.constraint(
        equalTo: titleLabel.leadingAnchor
      ),
      subtitleLabel.trailingAnchor.constraint(
        equalTo: safeAreaLayoutGuide.trailingAnchor,
        constant: -20
      ),
      subtitleLabel.topAnchor.constraint(
        equalTo: mediaControl.bottomAnchor,
        constant: 10
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
    let availableFolderIDs = Set(
      items.compactMap { item in
        item.depth == 0 ? item.folderID : nil
      }
    )
    collapsedFolderIDs.formIntersection(availableFolderIDs)
    tableView.reloadData()
  }

  func updateVideos(
    items: [VideoSidebarItem],
    selectedFolderID: UUID?,
    selectedRelativePath: String?
  ) {
    videoItems = items
    selectedVideoFolderID = selectedFolderID
    selectedVideoRelativePath = selectedRelativePath
    let availableKeys = Set(
      items.compactMap { item in
        item.kind == .folder
          ? videoDirectoryKey(
            folderID: item.folderID,
            relativePath: item.relativePath
          )
          : nil
      }
    )
    collapsedVideoDirectoryKeys.formIntersection(availableKeys)
    tableView.reloadData()
  }

  func setMode(_ mode: SidebarMediaMode, notify: Bool = false) {
    guard self.mode != mode else {
      mediaControl.selectedSegmentIndex = mode.rawValue
      updateModePresentation()
      return
    }
    self.mode = mode
    mediaControl.selectedSegmentIndex = mode.rawValue
    updateModePresentation()
    tableView.reloadData()
    if notify {
      delegate?.folderSidebar(self, didChangeMode: mode)
    }
  }

  @objc private func languageDidChange() {
    titleLabel.text = L("sidebar.library_title")
    mediaControl.setTitle(L("sidebar.images_tab"), forSegmentAt: 0)
    mediaControl.setTitle(L("sidebar.videos_tab"), forSegmentAt: 1)
    updateModePresentation()
    closeButton.accessibilityLabel = L("sidebar.close")
    tableView.reloadData()
  }

  @objc private func mediaControlChanged() {
    let nextMode =
      SidebarMediaMode(rawValue: mediaControl.selectedSegmentIndex)
      ?? .images
    setMode(nextMode, notify: true)
  }

  private func updateModePresentation() {
    subtitleLabel.text =
      mode == .images
      ? L("sidebar.images_subtitle")
      : L("sidebar.videos_subtitle")
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
    if
      item.depth == 0,
      let folderID = item.folderID,
      collapsedFolderIDs.contains(folderID),
      folderID == selectedFolderID
    {
      return true
    }
    return !selectsStandaloneFolder
      && item.folderID == selectedFolderID
      && item.directoryRelativePath
        == selectedDirectoryRelativePath
  }

  private var visibleItems: [FolderSidebarItem] {
    items.filter { item in
      guard
        item.depth > 0,
        let folderID = item.folderID
      else {
        return true
      }
      return !collapsedFolderIDs.contains(folderID)
    }
  }

  private var visibleVideoItems: [VideoSidebarItem] {
    videoItems.filter { item in
      videoAncestorDirectoryKeys(for: item).allSatisfy {
        !collapsedVideoDirectoryKeys.contains($0)
      }
    }
  }

  private func isSelected(_ item: VideoSidebarItem) -> Bool {
    item.kind == .video
      && item.folderID == selectedVideoFolderID
      && item.relativePath == selectedVideoRelativePath
  }

  private func videoDirectoryKey(
    folderID: UUID,
    relativePath: String?
  ) -> String {
    "\(folderID.uuidString)|\(relativePath ?? "")"
  }

  private func videoAncestorDirectoryKeys(
    for item: VideoSidebarItem
  ) -> [String] {
    guard item.depth > 0 else { return [] }
    var keys = [
      videoDirectoryKey(
        folderID: item.folderID,
        relativePath: nil
      )
    ]
    guard let relativePath = item.relativePath else { return keys }
    let components = relativePath.split(separator: "/")
    let directoryComponentCount = max(0, components.count - 1)
    guard directoryComponentCount > 0 else { return keys }
    for index in 1...directoryComponentCount {
      keys.append(
        videoDirectoryKey(
          folderID: item.folderID,
          relativePath: components.prefix(index)
            .joined(separator: "/")
        )
      )
    }
    return keys
  }

  private func toggleVideoDirectory(_ item: VideoSidebarItem) {
    guard item.kind == .folder else { return }
    let key = videoDirectoryKey(
      folderID: item.folderID,
      relativePath: item.relativePath
    )
    if collapsedVideoDirectoryKeys.contains(key) {
      collapsedVideoDirectoryKeys.remove(key)
    } else {
      collapsedVideoDirectoryKeys.insert(key)
    }
    tableView.reloadData()
  }

  private func toggleFolder(_ folderID: UUID) {
    if collapsedFolderIDs.contains(folderID) {
      collapsedFolderIDs.remove(folderID)
    } else {
      collapsedFolderIDs.insert(folderID)
    }
    tableView.reloadData()
  }

  private func disclosureAccessory(
    for item: FolderSidebarItem,
    selected: Bool
  ) -> UIView? {
    guard
      item.depth == 0,
      item.hasChildren,
      let folderID = item.folderID
    else {
      return nil
    }

    let collapsed = collapsedFolderIDs.contains(folderID)
    var configuration = UIButton.Configuration.plain()
    configuration.image = UIImage(
      systemName: collapsed ? "chevron.right" : "chevron.down"
    )
    configuration.baseForegroundColor = .secondaryLabel
    configuration.contentInsets = .zero
    let button = UIButton(configuration: configuration)
    button.accessibilityLabel = L(
      collapsed ? "sidebar.expand" : "sidebar.collapse"
    )
    button.accessibilityValue = item.title
    button.addAction(
      UIAction { [weak self] _ in
        self?.toggleFolder(folderID)
      },
      for: .touchUpInside
    )
    button.frame = CGRect(
      x: selected ? 24 : 0,
      y: 0,
      width: 32,
      height: 32
    )

    let accessory = UIView(
      frame: CGRect(
        x: 0,
        y: 0,
        width: selected ? 56 : 32,
        height: 32
      )
    )
    if selected {
      let checkmark = UIImageView(
        image: UIImage(systemName: "checkmark")
      )
      checkmark.tintColor = .systemBlue
      checkmark.contentMode = .scaleAspectFit
      checkmark.frame = CGRect(x: 0, y: 6, width: 20, height: 20)
      accessory.addSubview(checkmark)
    }
    accessory.addSubview(button)
    return accessory
  }

  private func videoDisclosureAccessory(
    for item: VideoSidebarItem
  ) -> UIView? {
    guard item.kind == .folder, item.hasChildren else { return nil }
    let key = videoDirectoryKey(
      folderID: item.folderID,
      relativePath: item.relativePath
    )
    let collapsed = collapsedVideoDirectoryKeys.contains(key)
    var configuration = UIButton.Configuration.plain()
    configuration.image = UIImage(
      systemName: collapsed ? "chevron.right" : "chevron.down"
    )
    configuration.baseForegroundColor = .secondaryLabel
    configuration.contentInsets = .zero
    let button = UIButton(configuration: configuration)
    button.accessibilityLabel = L(
      collapsed ? "sidebar.expand" : "sidebar.collapse"
    )
    button.accessibilityValue = item.title
    button.addAction(
      UIAction { [weak self] _ in
        self?.toggleVideoDirectory(item)
      },
      for: .touchUpInside
    )
    button.frame = CGRect(x: 0, y: 0, width: 32, height: 32)
    return button
  }

  #if DEBUG
    var visibleItemCountForTesting: Int {
      visibleItems.count
    }

    var totalItemCountForTesting: Int {
      items.count
    }

    var selectedVisibleItemTitleForTesting: String? {
      visibleItems.first(where: isSelected)?.title
    }

    func setFolderCollapsedForTesting(
      _ collapsed: Bool,
      folderID: UUID
    ) {
      if collapsed {
        collapsedFolderIDs.insert(folderID)
      } else {
        collapsedFolderIDs.remove(folderID)
      }
      tableView.reloadData()
    }

    func isFolderCollapsedForTesting(_ folderID: UUID) -> Bool {
      collapsedFolderIDs.contains(folderID)
    }
  #endif
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
    mode == .images
      ? visibleItems.count
      : visibleVideoItems.count
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
    cell.accessoryView = nil
    cell.accessoryType = .none
    cell.accessibilityValue = nil

    if mode == .videos {
      configureVideoCell(
        cell,
        item: visibleVideoItems[indexPath.row]
      )
      return cell
    }

    let item = visibleItems[indexPath.row]
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
    cell.accessoryView = disclosureAccessory(
      for: item,
      selected: selected
    )
    cell.accessoryType =
      selected && cell.accessoryView == nil ? .checkmark : .none
    cell.tintColor = .systemBlue
    cell.selectionStyle = .none
    cell.isUserInteractionEnabled = item.canSelect || item.canDelete
    cell.contentView.alpha = item.canSelect ? 1 : 0.52
    cell.accessibilityValue =
      selected ? L("sidebar.current") : nil
    return cell
  }

  private func configureVideoCell(
    _ cell: UITableViewCell,
    item: VideoSidebarItem
  ) {
    let selected = isSelected(item)
    var content = cell.defaultContentConfiguration()
    content.image = UIImage(
      systemName:
        item.kind == .folder
        ? "folder"
        : selected ? "play.rectangle.fill" : "film"
    )
    content.imageProperties.tintColor =
      selected ? .systemBlue : .secondaryLabel
    content.text = item.title
    content.directionalLayoutMargins.leading =
      12 + CGFloat(item.depth) * 24
    content.textProperties.font = .systemFont(
      ofSize: 16,
      weight: selected ? .semibold : .regular
    )
    if item.kind == .folder {
      content.secondaryText = L(
        "sidebar.video_count_format",
        item.videoCount
      )
    } else {
      content.secondaryText = L("sidebar.video_file")
    }
    content.secondaryTextProperties.color = .secondaryLabel
    cell.contentConfiguration = content

    var background = UIBackgroundConfiguration.listGroupedCell()
    background.backgroundColor =
      selected
      ? UIColor.systemBlue.withAlphaComponent(0.14)
      : .secondarySystemGroupedBackground
    background.cornerRadius = 12
    cell.backgroundConfiguration = background
    cell.accessoryView = videoDisclosureAccessory(for: item)
    cell.accessoryType =
      selected && cell.accessoryView == nil ? .checkmark : .none
    cell.tintColor = .systemBlue
    cell.selectionStyle = .none
    cell.isUserInteractionEnabled = true
    cell.contentView.alpha = 1
    cell.accessibilityValue =
      selected ? L("sidebar.current_video") : nil
  }
}

extension FolderSidebarView: UITableViewDelegate {
  func tableView(
    _ tableView: UITableView,
    didSelectRowAt indexPath: IndexPath
  ) {
    if mode == .videos {
      let item = visibleVideoItems[indexPath.row]
      if item.kind == .folder {
        toggleVideoDirectory(item)
      } else {
        delegate?.folderSidebar(self, didSelectVideo: item)
      }
      return
    }

    let item = visibleItems[indexPath.row]
    guard item.canSelect else { return }
    delegate?.folderSidebar(self, didSelect: item)
  }

  func tableView(
    _ tableView: UITableView,
    trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
  ) -> UISwipeActionsConfiguration? {
    if mode == .videos {
      let item = visibleVideoItems[indexPath.row]
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
          didRequestDeleteVideo: item
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

    let item = visibleItems[indexPath.row]
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
