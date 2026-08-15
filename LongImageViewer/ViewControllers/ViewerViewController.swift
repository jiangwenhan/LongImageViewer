import UIKit
import UniformTypeIdentifiers

final class ViewerViewController: UIViewController {
  var onPasswordSettingsRequested: (() -> Void)?

  private enum PickerMode {
    case images
    case imageFolder
    case videoFolder
  }

  private enum SelectionStorage {
    static let folderKey = "selectedFolderID"
    static let standaloneValue = "__standalone__"
    static let sidebarModeKey = "sidebarMediaMode"
  }

  private let tileOverlap = 1 / UIScreen.main.scale
  private let library = ImageLibrary.shared
  private let videoLibrary = VideoLibrary.shared
  private var documents: [ImageDocument] = []
  private var displayTiles: [DisplayTile] = []
  private var pageStartOffsets: [CGFloat] = []
  private var lastLaidOutWidth: CGFloat = 0
  private var currentPageIndex = 0
  private var pickerMode = PickerMode.images
  private var memoryTimer: Timer?
  private var isSynchronizingFolders = false
  private var isSynchronizingVideoFolders = false
  private var prefetchRequests: [IndexPath: ImageRequestToken] = [:]
  private var selectedFolderID: UUID?
  private var selectsStandaloneFolder = false
  private var pendingFolderURLs: [URL] = []
  private var isSelectingFolderBatch = false
  private var isSidebarVisible = false
  private var sidebarWidthConstraint: NSLayoutConstraint?
  private var sidebarMode =
    SidebarMediaMode(
      rawValue: UserDefaults.standard.integer(
        forKey: SelectionStorage.sidebarModeKey
      )
    ) ?? .images
  private var selectedVideoFolderID: UUID?
  private var selectedVideoRelativePath: String?

  #if DEBUG
    private var didProcessSimulatorFixtures = false
    private var didProcessSimulatorVideoFixtures = false
    private var smokeTestDisplayLink: CADisplayLink?
    private var smokeTestStartTime: CFTimeInterval = 0
    private var smokeTestLastFrameTime: CFTimeInterval = 0
    private var smokeTestFrameCount = 0
    private var smokeTestSlowFrameCount = 0
    private var smokeTestVisitedPages: Set<Int> = []
    private var smokeTestInitialTileCount = 0
    private var smokeTestPeakMemoryBytes: UInt64 = 0
    private var smokeTestDirectorySyncDuration: TimeInterval = 0
    private var didHandleDebugSidebarArguments = false
  #endif

  private lazy var collectionView: UICollectionView = {
    let layout = UICollectionViewFlowLayout()
    layout.scrollDirection = .vertical
    layout.minimumLineSpacing = -tileOverlap
    layout.minimumInteritemSpacing = 0
    layout.sectionInset = .zero

    let collectionView = UICollectionView(
      frame: .zero,
      collectionViewLayout: layout
    )
    collectionView.backgroundColor = .black
    collectionView.alwaysBounceVertical = true
    collectionView.showsVerticalScrollIndicator = true
    collectionView.contentInsetAdjustmentBehavior = .never
    collectionView.decelerationRate = .normal
    collectionView.dataSource = self
    collectionView.delegate = self
    collectionView.prefetchDataSource = self
    collectionView.register(
      ImageTileCell.self,
      forCellWithReuseIdentifier: ImageTileCell.reuseIdentifier
    )
    collectionView.translatesAutoresizingMaskIntoConstraints = false
    return collectionView
  }()

  private let overlayView: UIVisualEffectView = {
    let view = UIVisualEffectView(
      effect: UIBlurEffect(style: .systemUltraThinMaterialDark)
    )
    view.layer.cornerRadius = 12
    view.layer.cornerCurve = .continuous
    view.clipsToBounds = true
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  private let pageLabel: UILabel = {
    let label = UILabel()
    label.font = .monospacedDigitSystemFont(
      ofSize: 15,
      weight: .semibold
    )
    label.textColor = .white
    label.setContentCompressionResistancePriority(
      .required,
      for: .horizontal
    )
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  private let filenameLabel: UILabel = {
    let label = UILabel()
    label.font = .systemFont(ofSize: 15, weight: .semibold)
    label.textColor = .white
    label.textAlignment = .center
    label.lineBreakMode = .byTruncatingMiddle
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  private let memoryLabel: UILabel = {
    let label = UILabel()
    label.font = .monospacedDigitSystemFont(
      ofSize: 12,
      weight: .semibold
    )
    label.textColor = UIColor(white: 0.88, alpha: 1)
    label.textAlignment = .right
    label.setContentCompressionResistancePriority(
      .required,
      for: .horizontal
    )
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  private let sortButton: UIButton = {
    var configuration = UIButton.Configuration.filled()
    configuration.baseBackgroundColor = UIColor(
      white: 0.08,
      alpha: 0.78
    )
    configuration.baseForegroundColor = .white
    configuration.cornerStyle = .capsule
    configuration.image = UIImage(systemName: "arrow.up.arrow.down")
    configuration.contentInsets = NSDirectionalEdgeInsets(
      top: 10,
      leading: 12,
      bottom: 10,
      trailing: 12
    )
    let button = UIButton(configuration: configuration)
    button.accessibilityLabel = L("sort.accessibility")
    button.translatesAutoresizingMaskIntoConstraints = false
    return button
  }()

  private let addButton: UIButton = {
    var configuration = UIButton.Configuration.filled()
    configuration.baseBackgroundColor = UIColor(
      white: 0.08,
      alpha: 0.78
    )
    configuration.baseForegroundColor = .white
    configuration.cornerStyle = .capsule
    configuration.image = UIImage(systemName: "folder")
    configuration.title = L("source.button")
    configuration.imagePadding = 5
    configuration.contentInsets = NSDirectionalEdgeInsets(
      top: 10,
      leading: 13,
      bottom: 10,
      trailing: 13
    )
    let button = UIButton(configuration: configuration)
    button.translatesAutoresizingMaskIntoConstraints = false
    return button
  }()

  private let emptyStateView = UIView()
  private let emptyIcon = UIImageView(
    image: UIImage(systemName: "photo.on.rectangle.angled")
  )
  private let emptyTitleLabel: UILabel = {
    let label = UILabel()
    label.text = L("empty.initial_title")
    label.font = .systemFont(ofSize: 22, weight: .bold)
    label.textColor = .white
    label.textAlignment = .center
    return label
  }()
  private let emptySubtitleLabel: UILabel = {
    let label = UILabel()
    label.text = L("empty.browse_locations")
    label.font = .systemFont(ofSize: 15, weight: .regular)
    label.textColor = UIColor(white: 0.72, alpha: 1)
    label.textAlignment = .center
    label.numberOfLines = 0
    return label
  }()
  private let emptyImportButton: UIButton = {
    var configuration = UIButton.Configuration.filled()
    configuration.title = L("empty.browse_folder")
    configuration.image = UIImage(systemName: "folder")
    configuration.imagePadding = 8
    configuration.cornerStyle = .large
    configuration.baseBackgroundColor = .systemBlue
    let button = UIButton(configuration: configuration)
    return button
  }()

  private let activityIndicator: UIActivityIndicatorView = {
    let indicator = UIActivityIndicatorView(style: .large)
    indicator.color = .white
    indicator.hidesWhenStopped = true
    indicator.translatesAutoresizingMaskIntoConstraints = false
    return indicator
  }()

  private let sidebarDimmingView: UIView = {
    let view = UIView()
    view.backgroundColor = .black
    view.alpha = 0
    view.isHidden = true
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  private let folderSidebarView: FolderSidebarView = {
    let view = FolderSidebarView()
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    setupViews()
    setupActions()
    applyLocalization()
    startMemoryUpdates()
    restoreFolderSelection()
    reloadLibrary(preservingPage: false)
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
  }

  deinit {
    memoryTimer?.invalidate()
    NotificationCenter.default.removeObserver(self)
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()

    let sidebarWidth = min(view.bounds.width * 0.84, 360)
    if sidebarWidthConstraint?.constant != sidebarWidth {
      sidebarWidthConstraint?.constant = sidebarWidth
      if !isSidebarVisible {
        folderSidebarView.transform = CGAffineTransform(
          translationX: -sidebarWidth,
          y: 0
        )
      }
    }

    let width = collectionView.bounds.width
    guard width > 0, abs(width - lastLaidOutWidth) > 0.5 else {
      return
    }
    lastLaidOutWidth = width
    rebuildPageOffsets()
    collectionView.collectionViewLayout.invalidateLayout()
    updateCurrentPage()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)

    #if DEBUG
      importSimulatorFixturesIfRequested()
      importSimulatorVideoFixturesIfRequested()
      handleDebugSidebarArgumentsIfNeeded()
      reportLocalizationStateIfRequested()
      runLanguageSwitchSmokeTestIfRequested()
    #endif
  }

  private func setupViews() {
    view.addSubview(collectionView)
    view.addSubview(overlayView)
    view.addSubview(sortButton)
    view.addSubview(addButton)
    view.addSubview(activityIndicator)

    let overlayContent = overlayView.contentView
    overlayContent.addSubview(pageLabel)
    overlayContent.addSubview(filenameLabel)
    overlayContent.addSubview(memoryLabel)

    emptyStateView.translatesAutoresizingMaskIntoConstraints = false
    emptyIcon.tintColor = UIColor(white: 0.72, alpha: 1)
    emptyIcon.contentMode = .scaleAspectFit
    emptyIcon.translatesAutoresizingMaskIntoConstraints = false
    emptyTitleLabel.translatesAutoresizingMaskIntoConstraints = false
    emptySubtitleLabel.translatesAutoresizingMaskIntoConstraints = false
    emptyImportButton.translatesAutoresizingMaskIntoConstraints = false

    emptyStateView.addSubview(emptyIcon)
    emptyStateView.addSubview(emptyTitleLabel)
    emptyStateView.addSubview(emptySubtitleLabel)
    emptyStateView.addSubview(emptyImportButton)
    view.addSubview(emptyStateView)
    view.addSubview(sidebarDimmingView)
    view.addSubview(folderSidebarView)
    view.bringSubviewToFront(activityIndicator)

    let sidebarWidthConstraint = folderSidebarView.widthAnchor.constraint(
      equalToConstant: 340
    )
    self.sidebarWidthConstraint = sidebarWidthConstraint

    NSLayoutConstraint.activate([
      collectionView.leadingAnchor.constraint(
        equalTo: view.leadingAnchor
      ),
      collectionView.trailingAnchor.constraint(
        equalTo: view.trailingAnchor
      ),
      collectionView.topAnchor.constraint(equalTo: view.topAnchor),
      collectionView.bottomAnchor.constraint(
        equalTo: view.bottomAnchor
      ),

      overlayView.leadingAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.leadingAnchor,
        constant: 10
      ),
      overlayView.trailingAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.trailingAnchor,
        constant: -10
      ),
      overlayView.topAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.topAnchor,
        constant: 8
      ),
      overlayView.heightAnchor.constraint(equalToConstant: 42),

      pageLabel.leadingAnchor.constraint(
        equalTo: overlayContent.leadingAnchor,
        constant: 12
      ),
      pageLabel.centerYAnchor.constraint(
        equalTo: overlayContent.centerYAnchor
      ),
      pageLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 52),

      filenameLabel.leadingAnchor.constraint(
        greaterThanOrEqualTo: pageLabel.trailingAnchor,
        constant: 8
      ),
      filenameLabel.trailingAnchor.constraint(
        lessThanOrEqualTo: memoryLabel.leadingAnchor,
        constant: -8
      ),
      filenameLabel.centerXAnchor.constraint(
        equalTo: overlayContent.centerXAnchor
      ),
      filenameLabel.centerYAnchor.constraint(
        equalTo: overlayContent.centerYAnchor
      ),

      memoryLabel.trailingAnchor.constraint(
        equalTo: overlayContent.trailingAnchor,
        constant: -12
      ),
      memoryLabel.centerYAnchor.constraint(
        equalTo: overlayContent.centerYAnchor
      ),
      memoryLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 78),

      sortButton.leadingAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.leadingAnchor,
        constant: 12
      ),
      sortButton.bottomAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.bottomAnchor,
        constant: -12
      ),

      addButton.trailingAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.trailingAnchor,
        constant: -12
      ),
      addButton.bottomAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.bottomAnchor,
        constant: -12
      ),

      emptyStateView.centerXAnchor.constraint(
        equalTo: view.centerXAnchor
      ),
      emptyStateView.centerYAnchor.constraint(
        equalTo: view.centerYAnchor
      ),
      emptyStateView.leadingAnchor.constraint(
        greaterThanOrEqualTo: view.leadingAnchor,
        constant: 30
      ),
      emptyStateView.trailingAnchor.constraint(
        lessThanOrEqualTo: view.trailingAnchor,
        constant: -30
      ),

      emptyIcon.topAnchor.constraint(
        equalTo: emptyStateView.topAnchor
      ),
      emptyIcon.centerXAnchor.constraint(
        equalTo: emptyStateView.centerXAnchor
      ),
      emptyIcon.widthAnchor.constraint(equalToConstant: 72),
      emptyIcon.heightAnchor.constraint(equalToConstant: 72),

      emptyTitleLabel.topAnchor.constraint(
        equalTo: emptyIcon.bottomAnchor,
        constant: 18
      ),
      emptyTitleLabel.leadingAnchor.constraint(
        equalTo: emptyStateView.leadingAnchor
      ),
      emptyTitleLabel.trailingAnchor.constraint(
        equalTo: emptyStateView.trailingAnchor
      ),

      emptySubtitleLabel.topAnchor.constraint(
        equalTo: emptyTitleLabel.bottomAnchor,
        constant: 10
      ),
      emptySubtitleLabel.leadingAnchor.constraint(
        equalTo: emptyStateView.leadingAnchor
      ),
      emptySubtitleLabel.trailingAnchor.constraint(
        equalTo: emptyStateView.trailingAnchor
      ),

      emptyImportButton.topAnchor.constraint(
        equalTo: emptySubtitleLabel.bottomAnchor,
        constant: 24
      ),
      emptyImportButton.centerXAnchor.constraint(
        equalTo: emptyStateView.centerXAnchor
      ),
      emptyImportButton.bottomAnchor.constraint(
        equalTo: emptyStateView.bottomAnchor
      ),

      sidebarDimmingView.leadingAnchor.constraint(
        equalTo: view.leadingAnchor
      ),
      sidebarDimmingView.trailingAnchor.constraint(
        equalTo: view.trailingAnchor
      ),
      sidebarDimmingView.topAnchor.constraint(equalTo: view.topAnchor),
      sidebarDimmingView.bottomAnchor.constraint(
        equalTo: view.bottomAnchor
      ),

      folderSidebarView.leadingAnchor.constraint(
        equalTo: view.leadingAnchor
      ),
      folderSidebarView.topAnchor.constraint(equalTo: view.topAnchor),
      folderSidebarView.bottomAnchor.constraint(
        equalTo: view.bottomAnchor
      ),
      sidebarWidthConstraint,

      activityIndicator.centerXAnchor.constraint(
        equalTo: view.centerXAnchor
      ),
      activityIndicator.centerYAnchor.constraint(
        equalTo: view.centerYAnchor
      ),
    ])

    folderSidebarView.transform = CGAffineTransform(
      translationX: -340,
      y: 0
    )
  }

  private func setupActions() {
    folderSidebarView.delegate = self

    addButton.addTarget(
      self,
      action: #selector(sourceButtonTapped),
      for: .touchUpInside
    )
    emptyImportButton.addTarget(
      self,
      action: #selector(selectFolderTapped),
      for: .touchUpInside
    )
    sortButton.menu = makeSortMenu()
    sortButton.showsMenuAsPrimaryAction = true

    let openSwipe = UISwipeGestureRecognizer(
      target: self,
      action: #selector(openSidebarSwipeRecognized)
    )
    openSwipe.direction = .right
    openSwipe.cancelsTouchesInView = false
    view.addGestureRecognizer(openSwipe)

    let closeSwipe = UISwipeGestureRecognizer(
      target: self,
      action: #selector(closeSidebarSwipeRecognized)
    )
    closeSwipe.direction = .left
    sidebarDimmingView.addGestureRecognizer(closeSwipe)

    let dismissTap = UITapGestureRecognizer(
      target: self,
      action: #selector(sidebarDimmingViewTapped)
    )
    sidebarDimmingView.addGestureRecognizer(dismissTap)
  }

  private func makeSortMenu() -> UIMenu {
    let actions = ImageSortOption.allCases.map { [weak self] option in
      UIAction(
        title: option.title,
        image: UIImage(systemName: option.systemImageName),
        state: option == self?.library.sortOption ? .on : .off
      ) { _ in
        self?.applySort(option)
      }
    }

    let deleteAction = UIAction(
      title: L("sort.clear_all"),
      image: UIImage(systemName: "trash"),
      attributes: .destructive
    ) { [weak self] _ in
      self?.confirmDeleteAll()
    }
    return UIMenu(
      title: L("sort.title"),
      children: actions + [deleteAction]
    )
  }

  private func applyLocalization() {
    sortButton.accessibilityLabel = L("sort.accessibility")
    addButton.configuration?.title = L("source.button")
    emptyImportButton.configuration?.title = L(
      "empty.browse_folder"
    )
    sortButton.menu = makeSortMenu()
    updateEmptyState()
    updateFolderSidebar()
    updateMemoryLabel()
  }

  @objc private func languageDidChange() {
    applyLocalization()
  }

  @objc private func sourceButtonTapped() {
    let sheet = UIAlertController(
      title: L("source.title"),
      message: folderStatusMessage,
      preferredStyle: .actionSheet
    )
    sheet.addAction(
      UIAlertAction(
        title: L("source.manage_library"),
        style: .default
      ) { [weak self] _ in
        self?.showFolderSidebar()
      }
    )
    sheet.addAction(
      UIAlertAction(
        title: L("source.batch_add_folders"),
        style: .default
      ) { [weak self] _ in
        self?.beginFolderBatchSelection()
      }
    )
    sheet.addAction(
      UIAlertAction(
        title: L("source.select_files"),
        style: .default
      ) { [weak self] _ in
        self?.presentImagePicker()
      }
    )
    sheet.addAction(
      UIAlertAction(
        title: L("source.sync_folders"),
        style: .default
      ) { [weak self] _ in
        self?.syncFolders(showResult: true)
      }
    )
    sheet.addAction(
      UIAlertAction(
        title: L("source.add_video_folder"),
        style: .default
      ) { [weak self] _ in
        self?.presentVideoFolderPicker()
      }
    )
    if !videoLibrary.folders.isEmpty {
      sheet.addAction(
        UIAlertAction(
          title: L("source.sync_video_folders"),
          style: .default
        ) { [weak self] _ in
          self?.syncVideoFolders(showResult: true)
        }
      )
    }
    if videoLibrary.hasHiddenItems {
      sheet.addAction(
        UIAlertAction(
          title: L("source.restore_hidden_videos"),
          style: .default
        ) { [weak self] _ in
          self?.restoreHiddenVideoItems()
        }
      )
    }
    sheet.addAction(
      UIAlertAction(
        title: L("source.password_lock"),
        style: .default
      ) { [weak self] _ in
        self?.onPasswordSettingsRequested?()
      }
    )
    sheet.addAction(
      UIAlertAction(
        title: L("language.title"),
        style: .default
      ) { [weak self] _ in
        self?.presentLanguagePicker()
      }
    )
    sheet.addAction(
      UIAlertAction(title: L("common.cancel"), style: .cancel)
    )
    sheet.popoverPresentationController?.sourceView = addButton
    sheet.popoverPresentationController?.sourceRect = addButton.bounds
    present(sheet, animated: true)
  }

  private func presentLanguagePicker() {
    let sheet = UIAlertController(
      title: L("language.title"),
      message: L("language.message"),
      preferredStyle: .actionSheet
    )
    for language in AppLanguage.allCases {
      let title =
        language == AppLocalization.shared.language
        ? "✓ \(language.nativeDisplayName)"
        : language.nativeDisplayName
      sheet.addAction(
        UIAlertAction(title: title, style: .default) { _ in
          AppLocalization.shared.setLanguage(language)
        }
      )
    }
    sheet.addAction(
      UIAlertAction(title: L("common.cancel"), style: .cancel)
    )
    sheet.popoverPresentationController?.sourceView = addButton
    sheet.popoverPresentationController?.sourceRect = addButton.bounds
    present(sheet, animated: true)
  }

  @objc private func selectFolderTapped() {
    beginFolderBatchSelection()
  }

  private func beginFolderBatchSelection() {
    pendingFolderURLs = []
    isSelectingFolderBatch = true

    #if targetEnvironment(macCatalyst)
      presentFolderPicker()
    #else
      let alert = UIAlertController(
        title: L("batch.explanation_title"),
        message: L("batch.explanation_message"),
        preferredStyle: .alert
      )
      alert.addAction(
        UIAlertAction(
          title: L("batch.start"),
          style: .default
        ) { [weak self] _ in
          self?.presentFolderPicker()
        }
      )
      alert.addAction(
        UIAlertAction(
          title: L("common.cancel"),
          style: .cancel
        ) { [weak self] _ in
          self?.resetFolderBatchSelection()
        }
      )
      DispatchQueue.main.asyncAfter(
        deadline: .now() + 0.2
      ) { [weak self] in
        self?.present(alert, animated: true)
      }
    #endif
  }

  private func presentImagePicker() {
    pickerMode = .images
    let picker = UIDocumentPickerViewController(
      forOpeningContentTypes: [.image],
      asCopy: true
    )
    picker.allowsMultipleSelection = true
    picker.delegate = self
    present(picker, animated: true)
  }

  private func presentFolderPicker() {
    pickerMode = .imageFolder
    let picker = UIDocumentPickerViewController(
      forOpeningContentTypes: [.folder],
      asCopy: false
    )
    #if targetEnvironment(macCatalyst)
      picker.allowsMultipleSelection = true
    #else
      picker.allowsMultipleSelection = false
    #endif
    picker.delegate = self
    picker.directoryURL =
      FileManager.default.urls(
        for: .documentDirectory,
        in: .userDomainMask
      ).first
    present(picker, animated: true)
  }

  private func presentVideoFolderPicker() {
    pickerMode = .videoFolder
    let picker = UIDocumentPickerViewController(
      forOpeningContentTypes: [.folder],
      asCopy: false
    )
    picker.allowsMultipleSelection = false
    picker.delegate = self
    picker.directoryURL =
      FileManager.default.urls(
        for: .documentDirectory,
        in: .userDomainMask
      ).first
    present(picker, animated: true)
  }

  private func appendPendingFolders(_ urls: [URL]) {
    var knownPaths = Set(
      pendingFolderURLs.map { $0.standardizedFileURL.path }
    )
    for url in urls {
      let path = url.standardizedFileURL.path
      if knownPaths.insert(path).inserted {
        pendingFolderURLs.append(url)
      }
    }
  }

  private func presentFolderBatchProgress() {
    guard isSelectingFolderBatch, !pendingFolderURLs.isEmpty else {
      return
    }

    let folderNames = pendingFolderURLs.map(\.lastPathComponent)
    let message = L(
      "batch.selected_format",
      folderNames.count,
      folderNames.joined(separator: "\n")
    )
    let sheet = UIAlertController(
      title: L("batch.continue_title"),
      message: message,
      preferredStyle: .actionSheet
    )
    sheet.addAction(
      UIAlertAction(
        title: L("batch.continue"),
        style: .default
      ) { [weak self] _ in
        self?.presentFolderPicker()
      }
    )
    sheet.addAction(
      UIAlertAction(
        title: L("batch.import_format", folderNames.count),
        style: .default
      ) { [weak self] _ in
        self?.finishFolderBatchSelection()
      }
    )
    sheet.addAction(
      UIAlertAction(
        title: L("batch.cancel"),
        style: .cancel
      ) { [weak self] _ in
        self?.resetFolderBatchSelection()
      }
    )
    sheet.popoverPresentationController?.sourceView = addButton
    sheet.popoverPresentationController?.sourceRect = addButton.bounds
    present(sheet, animated: true)
  }

  private func finishFolderBatchSelection() {
    let selectedURLs = pendingFolderURLs
    resetFolderBatchSelection()
    guard !selectedURLs.isEmpty else { return }

    setImporting(true)
    library.addFolders(from: selectedURLs) { [weak self] result in
      guard let self else { return }
      self.setImporting(false)

      switch result {
      case .success(let summary):
        if
          let firstSelectedURL = selectedURLs.first,
          let folderID = self.library.folderID(for: firstSelectedURL)
        {
          self.selectedFolderID = folderID
          self.selectsStandaloneFolder = false
          self.persistFolderSelection()
        }
        ImagePipeline.shared.clearCache()
        self.reloadLibrary(preservingPage: false)
        self.presentFolderSyncSummary(
          summary,
          title:
            selectedURLs.count == 1
            ? L("batch.added_one")
            : L("batch.added_format", selectedURLs.count)
        )
      case .failure(let error):
        self.presentError(error)
      }
    }
  }

  private func resetFolderBatchSelection() {
    pendingFolderURLs = []
    isSelectingFolderBatch = false
  }

  private var folderStatusMessage: String {
    let imageNames = library.folderDisplayNames
    let videoNames = videoLibrary.folderDisplayNames
    guard !imageNames.isEmpty || !videoNames.isEmpty else {
      return L("folder.status_available")
    }
    var lines: [String] = []
    if !imageNames.isEmpty {
      lines.append(
        L(
          "folder.status_images_format",
          imageNames.joined(separator: L("common.list_separator"))
        )
      )
    }
    if !videoNames.isEmpty {
      lines.append(
        L(
          "folder.status_videos_format",
          videoNames.joined(separator: L("common.list_separator"))
        )
      )
    }
    return lines.joined(separator: "\n")
  }

  private var sidebarItems: [FolderSidebarItem] {
    var items: [FolderSidebarItem] = []
    for folder in library.folders {
      let summaries = library.directorySummaries(in: folder)
      for summary in summaries {
        items.append(
          FolderSidebarItem(
            folderID: folder.id,
            directoryRelativePath: summary.relativePath,
            title: summary.displayName,
            imageCount: summary.imageCount,
            depth: summary.relativePath == nil ? 0 : 1,
            hasChildren:
              summary.relativePath == nil
                && summaries.count > 1,
            canSelect:
              summary.relativePath == nil
                || summary.imageCount > 0,
            canDelete: summary.relativePath == nil
          )
        )
      }
    }
    if library.hasStandaloneDocuments {
      items.append(
        FolderSidebarItem(
          folderID: nil,
          directoryRelativePath: nil,
          title: L("folder.manual_import"),
          imageCount: library.imageCount(in: nil),
          depth: 0,
          hasChildren: false,
          canSelect: true,
          canDelete: true
        )
      )
    }
    return items
  }

  private var videoSidebarItems: [VideoSidebarItem] {
    var items: [VideoSidebarItem] = []
    for folder in videoLibrary.folders {
      let videos = videoLibrary.videos(in: folder.id)
      items.append(
        VideoSidebarItem(
          folderID: folder.id,
          relativePath: nil,
          title: folder.displayName,
          videoCount: videos.count,
          depth: 0,
          kind: .folder,
          hasChildren: !videos.isEmpty,
          canDelete: true
        )
      )
      appendVideoItems(
        to: &items,
        folderID: folder.id,
        directoryRelativePath: nil,
        depth: 1,
        videos: videos
      )
    }
    return items
  }

  private func appendVideoItems(
    to items: inout [VideoSidebarItem],
    folderID: UUID,
    directoryRelativePath: String?,
    depth: Int,
    videos: [VideoDocument]
  ) {
    let directVideos = videos.filter {
      $0.directoryRelativePath == directoryRelativePath
    }.sorted {
      $0.filename.localizedStandardCompare($1.filename)
        == .orderedAscending
    }
    for video in directVideos {
      items.append(
        VideoSidebarItem(
          folderID: folderID,
          relativePath: video.relativePath,
          title: video.filename,
          videoCount: 0,
          depth: depth,
          kind: .video,
          hasChildren: false,
          canDelete: true
        )
      )
    }

    let childDirectories = immediateChildDirectories(
      below: directoryRelativePath,
      videos: videos
    )
    for childDirectory in childDirectories {
      let descendantCount = videos.lazy.filter {
        $0.directoryRelativePath == childDirectory
          || $0.directoryRelativePath?.hasPrefix(
            childDirectory + "/"
          ) == true
      }.count
      items.append(
        VideoSidebarItem(
          folderID: folderID,
          relativePath: childDirectory,
          title:
            childDirectory.split(separator: "/").last.map(String.init)
            ?? childDirectory,
          videoCount: descendantCount,
          depth: depth,
          kind: .folder,
          hasChildren: descendantCount > 0,
          canDelete: true
        )
      )
      appendVideoItems(
        to: &items,
        folderID: folderID,
        directoryRelativePath: childDirectory,
        depth: depth + 1,
        videos: videos
      )
    }
  }

  private func immediateChildDirectories(
    below parent: String?,
    videos: [VideoDocument]
  ) -> [String] {
    let parentComponents = parent?.split(separator: "/") ?? []
    let children = videos.compactMap { video -> String? in
      guard let directory = video.directoryRelativePath else {
        return nil
      }
      let components = directory.split(separator: "/")
      guard
        components.count > parentComponents.count,
        Array(components.prefix(parentComponents.count))
          == Array(parentComponents)
      else {
        return nil
      }
      return components.prefix(parentComponents.count + 1)
        .joined(separator: "/")
    }
    return Array(Set(children)).sorted {
      $0.localizedStandardCompare($1) == .orderedAscending
    }
  }

  private func restoreFolderSelection() {
    let savedValue = UserDefaults.standard.string(
      forKey: SelectionStorage.folderKey
    )
    if savedValue == SelectionStorage.standaloneValue,
      library.hasStandaloneDocuments
    {
      selectedFolderID = nil
      selectsStandaloneFolder = true
      return
    }
    if let savedValue,
      let folderID = UUID(uuidString: savedValue),
      library.folders.contains(where: { $0.id == folderID })
    {
      selectedFolderID = folderID
      selectsStandaloneFolder = false
      return
    }
    selectDefaultCollection()
  }

  private func selectDefaultCollection() {
    if let firstFolder = library.folders.first {
      selectedFolderID = firstFolder.id
      selectsStandaloneFolder = false
    } else if library.hasStandaloneDocuments {
      selectedFolderID = nil
      selectsStandaloneFolder = true
    } else {
      selectedFolderID = nil
      selectsStandaloneFolder = false
    }
    persistFolderSelection()
  }

  private func persistFolderSelection() {
    let value: String?
    if selectsStandaloneFolder {
      value = SelectionStorage.standaloneValue
    } else {
      value = selectedFolderID?.uuidString
    }
    UserDefaults.standard.set(
      value,
      forKey: SelectionStorage.folderKey
    )
  }

  private func ensureFolderSelectionIsValid() {
    if selectsStandaloneFolder {
      if !library.hasStandaloneDocuments {
        selectDefaultCollection()
      }
      return
    }
    if let selectedFolderID {
      if !library.folders.contains(where: { $0.id == selectedFolderID }) {
        selectDefaultCollection()
      }
    } else {
      selectDefaultCollection()
    }
  }

  private func updateFolderSidebar() {
    folderSidebarView.update(
      items: sidebarItems,
      selectedFolderID: selectedFolderID,
      selectedDirectoryRelativePath:
        currentDirectoryRelativePath,
      selectsStandaloneFolder: selectsStandaloneFolder
    )
    folderSidebarView.updateVideos(
      items: videoSidebarItems,
      selectedFolderID: selectedVideoFolderID,
      selectedRelativePath: selectedVideoRelativePath
    )
    folderSidebarView.setMode(sidebarMode)
  }

  private var currentDirectoryRelativePath: String? {
    guard
      !selectsStandaloneFolder,
      documents.indices.contains(currentPageIndex)
    else {
      return nil
    }
    return documents[currentPageIndex].directoryRelativePath
  }

  private var selectedCollectionTitle: String {
    if selectsStandaloneFolder {
      return L("folder.manual_import")
    }
    return library.folders.first {
      $0.id == selectedFolderID
    }?.displayName ?? L("folder.generic")
  }

  @objc private func openSidebarSwipeRecognized() {
    showFolderSidebar()
  }

  @objc private func closeSidebarSwipeRecognized() {
    hideFolderSidebar()
  }

  @objc private func sidebarDimmingViewTapped() {
    hideFolderSidebar()
  }

  private func showFolderSidebar() {
    updateFolderSidebar()
    guard !isSidebarVisible else { return }
    isSidebarVisible = true
    sidebarDimmingView.isHidden = false
    view.layoutIfNeeded()
    UIView.animate(
      withDuration: 0.25,
      delay: 0,
      options: [.curveEaseOut, .beginFromCurrentState]
    ) {
      self.sidebarDimmingView.alpha = 0.38
      self.folderSidebarView.transform = .identity
    }
  }

  private func hideFolderSidebar() {
    guard isSidebarVisible else { return }
    isSidebarVisible = false
    let width = sidebarWidthConstraint?.constant ?? 340
    UIView.animate(
      withDuration: 0.22,
      delay: 0,
      options: [.curveEaseIn, .beginFromCurrentState]
    ) {
      self.sidebarDimmingView.alpha = 0
      self.folderSidebarView.transform = CGAffineTransform(
        translationX: -width,
        y: 0
      )
    } completion: { _ in
      self.sidebarDimmingView.isHidden = true
    }
  }

  private func selectCollection(_ item: FolderSidebarItem) {
    let switchesRoot =
      item.folderID != selectedFolderID
        || (item.folderID == nil && !selectsStandaloneFolder)
    selectedFolderID = item.folderID
    selectsStandaloneFolder = item.folderID == nil
    currentPageIndex = 0
    persistFolderSelection()
    if switchesRoot {
      ImagePipeline.shared.clearCache()
      reloadLibrary(preservingPage: false)
    }

    let targetPage: Int
    if let directoryRelativePath = item.directoryRelativePath {
      targetPage =
        documents.firstIndex {
          $0.directoryRelativePath == directoryRelativePath
        } ?? 0
    } else {
      targetPage = 0
    }
    scrollToPage(at: targetPage, animated: false)
    hideFolderSidebar()
  }

  private func startMemoryUpdates() {
    updateMemoryLabel()
    let timer = Timer(
      timeInterval: 1,
      target: self,
      selector: #selector(updateMemoryLabel),
      userInfo: nil,
      repeats: true
    )
    RunLoop.main.add(timer, forMode: .common)
    memoryTimer = timer
  }

  @objc private func updateMemoryLabel() {
    memoryLabel.text = ProcessMemoryMonitor.formattedUsedMemory
    if let usedBytes = ProcessMemoryMonitor.usedBytes {
      ImagePipeline.shared.trimIfNeeded(usedBytes: usedBytes)
      #if DEBUG
        smokeTestPeakMemoryBytes = max(
          smokeTestPeakMemoryBytes,
          usedBytes
        )
      #endif
    }
  }

  @objc private func applicationDidBecomeActive() {
    if !library.folders.isEmpty {
      syncFolders(showResult: false)
    }
    if !videoLibrary.folders.isEmpty {
      syncVideoFolders(showResult: false)
    }
  }

  private func syncFolders(showResult: Bool) {
    guard !isSynchronizingFolders else { return }
    isSynchronizingFolders = true
    if showResult {
      setImporting(true)
    }

    library.syncFolders { [weak self] result in
      guard let self else { return }
      self.isSynchronizingFolders = false
      if showResult {
        self.setImporting(false)
      }

      switch result {
      case .success(let summary):
        self.ensureFolderSelectionIsValid()
        if summary.addedCount > 0
          || summary.updatedCount > 0
          || summary.removedCount > 0
        {
          ImagePipeline.shared.clearCache()
          self.reloadLibrary(preservingPage: true)
        } else {
          self.updateFolderSidebar()
        }
        if showResult {
          self.presentFolderSyncSummary(
            summary,
            title: L("folder.sync_complete")
          )
        }
      case .failure(let error):
        if showResult {
          self.presentError(error)
        }
      }
    }
  }

  private func presentFolderSyncSummary(
    _ summary: FolderSyncSummary,
    title: String
  ) {
    var lines = [
      L("folder.sync_added_format", summary.addedCount),
      L("folder.sync_updated_format", summary.updatedCount),
      L("folder.sync_removed_format", summary.removedCount),
    ]
    if !summary.failedFilenames.isEmpty {
      lines.append(
        L(
          "folder.sync_failed_format",
          summary.failedFilenames.joined(
            separator: L("common.list_separator")
          )
        )
      )
    }
    if !summary.unavailableFolders.isEmpty {
      lines.append(
        L(
          "folder.sync_unavailable_format",
          summary.unavailableFolders.joined(
            separator: L("common.list_separator")
          )
        )
      )
    }

    let alert = UIAlertController(
      title: title,
      message: lines.joined(separator: "\n"),
      preferredStyle: .alert
    )
    alert.addAction(
      UIAlertAction(title: L("common.ok"), style: .default)
    )
    present(alert, animated: true)
  }

  private func syncVideoFolders(showResult: Bool) {
    guard
      !videoLibrary.folders.isEmpty,
      !isSynchronizingVideoFolders
    else {
      return
    }
    isSynchronizingVideoFolders = true
    if showResult {
      setImporting(true)
    }
    videoLibrary.syncFolders { [weak self] result in
      guard let self else { return }
      self.isSynchronizingVideoFolders = false
      if showResult {
        self.setImporting(false)
      }
      switch result {
      case .success(let summary):
        self.updateFolderSidebar()
        if showResult {
          self.presentVideoSyncSummary(
            summary,
            title: L("video.sync_complete")
          )
        }
      case .failure(let error):
        if showResult {
          self.presentError(error)
        }
      }
    }
  }

  private func restoreHiddenVideoItems() {
    setImporting(true)
    videoLibrary.restoreHiddenItems { [weak self] result in
      guard let self else { return }
      self.setImporting(false)
      switch result {
      case .success(let summary):
        self.updateFolderSidebar()
        self.presentVideoSyncSummary(
          summary,
          title: L("video.restore_complete")
        )
      case .failure(let error):
        self.presentError(error)
      }
    }
  }

  private func presentVideoSyncSummary(
    _ summary: VideoSyncSummary,
    title: String
  ) {
    var lines = [
      L("video.sync_added_format", summary.addedCount),
      L("video.sync_updated_format", summary.updatedCount),
      L("video.sync_removed_format", summary.removedCount),
    ]
    if !summary.unavailableFolders.isEmpty {
      lines.append(
        L(
          "folder.sync_unavailable_format",
          summary.unavailableFolders.joined(
            separator: L("common.list_separator")
          )
        )
      )
    }
    let alert = UIAlertController(
      title: title,
      message: lines.joined(separator: "\n"),
      preferredStyle: .alert
    )
    alert.addAction(
      UIAlertAction(title: L("common.ok"), style: .default)
    )
    present(alert, animated: true)
  }

  private func playVideo(_ item: VideoSidebarItem) {
    guard
      item.kind == .video,
      let relativePath = item.relativePath,
      let video = videoLibrary.videos.first(
        where: {
          $0.sourceFolderID == item.folderID
            && $0.relativePath == relativePath
        }
      )
    else {
      return
    }

    do {
      let access = try videoLibrary.playbackAccess(for: video)
      selectedVideoFolderID = item.folderID
      selectedVideoRelativePath = relativePath
      updateFolderSidebar()
      hideFolderSidebar()
      let player = VideoPlayerViewController(
        playbackAccess: access,
        title: video.filename
      )
      present(player, animated: true)
    } catch {
      presentError(error)
    }
  }

  private func applySort(_ option: ImageSortOption) {
    let currentDocumentID =
      documents.indices.contains(currentPageIndex)
      ? documents[currentPageIndex].id
      : nil
    library.setSortOption(option)
    reloadLibrary(preservingPage: false)
    sortButton.menu = makeSortMenu()

    if let currentDocumentID,
      let newIndex = documents.firstIndex(
        where: { $0.id == currentDocumentID }
      )
    {
      scrollToPage(at: newIndex, animated: false)
    }
  }

  private func confirmDeleteAll() {
    guard !documents.isEmpty || !library.folders.isEmpty else { return }

    let alert = UIAlertController(
      title: L("clear.title"),
      message: L("clear.message"),
      preferredStyle: .alert
    )
    alert.addAction(
      UIAlertAction(title: L("common.cancel"), style: .cancel)
    )
    alert.addAction(
      UIAlertAction(title: L("common.clear"), style: .destructive) {
        [weak self] _ in
        self?.setImporting(true)
        self?.library.deleteAll { result in
          guard let self else { return }
          self.setImporting(false)
          switch result {
          case .success:
            ImagePipeline.shared.clearCache()
            self.reloadLibrary(preservingPage: false)
          case .failure(let error):
            self.presentError(error)
          }
        }
      }
    )
    present(alert, animated: true)
  }

  private func reloadLibrary(preservingPage: Bool) {
    for request in prefetchRequests.values {
      request.cancel()
    }
    prefetchRequests.removeAll()

    ensureFolderSelectionIsValid()
    let previousPage = preservingPage ? currentPageIndex : 0
    if selectsStandaloneFolder {
      documents = library.documents(in: nil)
    } else if let selectedFolderID {
      documents = library.documents(in: selectedFolderID)
    } else {
      documents = []
    }
    displayTiles = documents.enumerated().flatMap {
      pageIndex,
      document in
      document.tiles.enumerated().map { tileIndex, tile in
        DisplayTile(
          document: document,
          tile: tile,
          pageIndex: pageIndex,
          showsPageSeparator: pageIndex > 0 && tileIndex == 0
        )
      }
    }
    currentPageIndex = min(
      previousPage,
      max(0, documents.count - 1)
    )
    rebuildPageOffsets()
    collectionView.reloadData()
    updateEmptyState()
    updateOverlay()
    updateFolderSidebar()
  }

  private func updateEmptyState() {
    let isEmpty = documents.isEmpty
    emptyStateView.isHidden = !isEmpty
    emptyTitleLabel.text =
      sidebarItems.isEmpty
      ? L("empty.no_folders")
      : L("empty.folder_format", selectedCollectionTitle)
    emptySubtitleLabel.text =
      sidebarItems.isEmpty
      ? L("empty.browse_locations")
      : L("empty.switch_hint")
    overlayView.isHidden = false
    sortButton.isHidden = isEmpty
    addButton.isHidden = false
  }

  private func rebuildPageOffsets() {
    guard lastLaidOutWidth > 0 else {
      pageStartOffsets = Array(repeating: 0, count: documents.count)
      return
    }

    var nextOffset: CGFloat = 0
    pageStartOffsets = documents.map { document in
      let startOffset = nextOffset
      nextOffset +=
        CGFloat(document.pixelHeight)
        * lastLaidOutWidth
        / CGFloat(document.pixelWidth)
        - tileOverlap * CGFloat(document.tiles.count)
      return startOffset
    }
  }

  private func updateCurrentPage() {
    guard !documents.isEmpty else { return }

    let viewportAnchor = max(
      0,
      collectionView.contentOffset.y
        + collectionView.adjustedContentInset.top
        + 1
    )

    var low = 0
    var high = pageStartOffsets.count
    while low < high {
      let middle = (low + high) / 2
      if pageStartOffsets[middle] <= viewportAnchor {
        low = middle + 1
      } else {
        high = middle
      }
    }

    let pageIndex = max(0, min(low - 1, documents.count - 1))
    guard pageIndex != currentPageIndex else { return }
    currentPageIndex = pageIndex
    updateOverlay()
    if isSidebarVisible {
      updateFolderSidebar()
    }
  }

  private func updateOverlay() {
    guard documents.indices.contains(currentPageIndex) else {
      pageLabel.text = nil
      filenameLabel.text = nil
      return
    }

    pageLabel.text = "\(currentPageIndex + 1)/\(documents.count)"
    filenameLabel.text = documents[currentPageIndex].filename
  }

  private func scrollToPage(at pageIndex: Int, animated: Bool) {
    guard pageStartOffsets.indices.contains(pageIndex) else { return }
    currentPageIndex = pageIndex
    collectionView.setContentOffset(
      CGPoint(x: 0, y: pageStartOffsets[pageIndex]),
      animated: animated
    )
    updateOverlay()
  }

  private func setImporting(_ isImporting: Bool) {
    if isImporting {
      activityIndicator.startAnimating()
    } else {
      activityIndicator.stopAnimating()
    }
    view.isUserInteractionEnabled = !isImporting
    collectionView.alpha = isImporting ? 0.55 : 1
    emptyStateView.alpha = isImporting ? 0.35 : 1
  }

  private func presentError(_ error: Error) {
    let alert = UIAlertController(
      title: L("error.operation_failed"),
      message: error.localizedDescription,
      preferredStyle: .alert
    )
    alert.addAction(
      UIAlertAction(title: L("common.ok"), style: .default)
    )
    present(alert, animated: true)
  }

  #if DEBUG
    private func reportLocalizationStateIfRequested() {
      guard
        ProcessInfo.processInfo.arguments.contains(
          "--report-localization-state"
        )
      else {
        return
      }

      let language = AppLocalization.shared.language
      let result: [String: Any] = [
        "status": "passed",
        "language": language.rawValue,
        "sourceButton": addButton.configuration?.title ?? "",
        "emptyTitle": L("empty.no_folders"),
        "sortTitle": L("sort.title"),
        "imagesTab": L("sidebar.images_tab"),
        "videosTab": L("sidebar.videos_tab"),
        "languageTitle": L("language.title"),
        "lockTitle": L("lock.title"),
      ]
      let documentsURL = FileManager.default.urls(
        for: .documentDirectory,
        in: .userDomainMask
      )[0]
      let resultURL = documentsURL.appendingPathComponent(
        "localization-\(language.rawValue).json"
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

    private func runLanguageSwitchSmokeTestIfRequested() {
      guard
        ProcessInfo.processInfo.arguments.contains(
          "--language-switch-smoke-test"
        )
      else {
        return
      }

      let originalLanguage = AppLocalization.shared.language
      var sourceButtonTitles: [String: String] = [:]
      var sortMenuTitles: [String: String] = [:]
      var videoTabTitles: [String: String] = [:]
      for language in AppLanguage.allCases {
        AppLocalization.shared.setLanguage(language)
        sourceButtonTitles[language.rawValue] =
          addButton.configuration?.title ?? ""
        sortMenuTitles[language.rawValue] = sortButton.menu?.title ?? ""
        videoTabTitles[language.rawValue] = L("sidebar.videos_tab")
      }
      AppLocalization.shared.setLanguage(originalLanguage)

      let passed =
        sourceButtonTitles.values.filter { !$0.isEmpty }.count == 3
        && Set(sourceButtonTitles.values).count == 3
        && Set(sortMenuTitles.values).count == 3
        && Set(videoTabTitles.values).count == 3
      let result: [String: Any] = [
        "status": passed ? "passed" : "failed",
        "sourceButtonTitles": sourceButtonTitles,
        "sortMenuTitles": sortMenuTitles,
        "videoTabTitles": videoTabTitles,
      ]
      let documentsURL = FileManager.default.urls(
        for: .documentDirectory,
        in: .userDomainMask
      )[0]
      let resultURL = documentsURL.appendingPathComponent(
        "language-switch-result.json"
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

    private func importSimulatorFixturesIfRequested() {
      let arguments = ProcessInfo.processInfo.arguments
      guard
        arguments.contains("--import-simulator-fixtures"),
        !didProcessSimulatorFixtures
      else {
        return
      }
      didProcessSimulatorFixtures = true
      let syncStartTime = CACurrentMediaTime()
      let fixtureDirectories = simulatorFixtureDirectories(
        arguments: arguments
      )

      setImporting(true)
      library.addFolders(from: fixtureDirectories) {
        [weak self] result in
        guard let self else { return }
        self.smokeTestDirectorySyncDuration =
          CACurrentMediaTime() - syncStartTime
        self.setImporting(false)

        switch result {
        case .success:
          self.sidebarMode = .images
          UserDefaults.standard.set(
            SidebarMediaMode.images.rawValue,
            forKey: SelectionStorage.sidebarModeKey
          )
          self.selectPrimaryFixtureFolder(fixtureDirectories)
          self.reloadLibrary(preservingPage: false)
          self.scheduleSmokeTestIfRequested()
        case .failure(let error):
          self.writeSmokeTestResult([
            "status": "import-failed",
            "error": error.localizedDescription,
          ])
        }
      }
    }

    private func importSimulatorVideoFixturesIfRequested() {
      let arguments = ProcessInfo.processInfo.arguments
      guard
        arguments.contains("--import-simulator-video-fixtures"),
        !didProcessSimulatorVideoFixtures
      else {
        return
      }
      didProcessSimulatorVideoFixtures = true
      let fixtureURL = FileManager.default.urls(
        for: .documentDirectory,
        in: .userDomainMask
      )[0].appendingPathComponent(
        "SimulatorVideoFixtures",
        isDirectory: true
      )

      videoLibrary.addFolder(from: fixtureURL) {
        [weak self] result in
        guard let self else { return }
        switch result {
        case .success:
          self.sidebarMode = .videos
          UserDefaults.standard.set(
            SidebarMediaMode.videos.rawValue,
            forKey: SelectionStorage.sidebarModeKey
          )
          self.updateFolderSidebar()
          if arguments.contains("--video-library-smoke-test") {
            self.runVideoLibrarySmokeTest(fixtureURL: fixtureURL)
          } else if arguments.contains("--show-video-sidebar") {
            DispatchQueue.main.asyncAfter(
              deadline: .now() + 0.3
            ) { [weak self] in
              self?.showFolderSidebar()
            }
          }
        case .failure(let error):
          self.writeVideoLibraryResult([
            "status": "import-failed",
            "error": error.localizedDescription,
          ])
        }
      }
    }

    private func runVideoLibrarySmokeTest(fixtureURL: URL) {
      let initialVideos = videoLibrary.videos
      let initialItems = videoSidebarItems
      guard
        initialVideos.count == 4,
        let fileToHide = initialVideos.first(
          where: { $0.relativePath == "root_clip.mp4" }
        ),
        let directoryToHide = initialItems.first(
          where: {
            $0.kind == .folder
              && $0.relativePath == "Level_1"
          }
        )
      else {
        writeVideoLibraryResult([
          "status": "fixture-validation-failed",
          "videoCount": initialVideos.count,
          "sidebarItemCount": initialItems.count,
        ])
        return
      }

      let fileSourceURL = fixtureURL.appendingPathComponent(
        fileToHide.relativePath
      )
      let directorySourceURL = fixtureURL.appendingPathComponent(
        directoryToHide.relativePath ?? "",
        isDirectory: true
      )
      videoLibrary.hideItem(
        folderID: fileToHide.sourceFolderID,
        relativePath: fileToHide.relativePath,
        isDirectory: false
      ) { [weak self] hideFileResult in
        guard
          let self,
          case .success = hideFileResult
        else {
          self?.writeVideoLibraryResult([
            "status": "hide-file-failed"
          ])
          return
        }
        let fileHidden = self.videoLibrary.videos.count == 3
          && FileManager.default.fileExists(atPath: fileSourceURL.path)
          && self.videoLibrary.hasHiddenItems

        self.videoLibrary.restoreHiddenItems {
          [weak self] restoreFileResult in
          guard
            let self,
            case .success = restoreFileResult
          else {
            self?.writeVideoLibraryResult([
              "status": "restore-file-failed"
            ])
            return
          }
          self.videoLibrary.hideItem(
            folderID: directoryToHide.folderID,
            relativePath: directoryToHide.relativePath ?? "",
            isDirectory: true
          ) { [weak self] hideDirectoryResult in
            guard
              let self,
              case .success = hideDirectoryResult
            else {
              self?.writeVideoLibraryResult([
                "status": "hide-directory-failed"
              ])
              return
            }
            let directoryHidden =
              self.videoLibrary.videos.count == 2
              && FileManager.default.fileExists(
                atPath: directorySourceURL.path
              )

            self.videoLibrary.restoreHiddenItems {
              [weak self] restoreDirectoryResult in
              guard
                let self,
                case .success = restoreDirectoryResult,
                let folderID = self.videoLibrary.folderID(
                  for: fixtureURL
                )
              else {
                self?.writeVideoLibraryResult([
                  "status": "restore-directory-failed"
                ])
                return
              }
              self.videoLibrary.removeFolder(folderID) {
                [weak self] removeResult in
                guard
                  let self,
                  case .success = removeResult
                else {
                  self?.writeVideoLibraryResult([
                    "status": "remove-association-failed"
                  ])
                  return
                }
                let associationRemoved =
                  self.videoLibrary.folders.isEmpty
                  && self.videoLibrary.videos.isEmpty
                  && FileManager.default.fileExists(
                    atPath: fixtureURL.path
                  )
                self.videoLibrary.addFolder(from: fixtureURL) {
                  [weak self] relinkResult in
                  guard
                    let self,
                    case .success = relinkResult
                  else {
                    self?.writeVideoLibraryResult([
                      "status": "relink-failed"
                    ])
                    return
                  }
                  self.finishVideoLibrarySmokeTest(
                    fixtureURL: fixtureURL,
                    initialItems: initialItems,
                    fileHidden: fileHidden,
                    directoryHidden: directoryHidden,
                    associationRemoved: associationRemoved
                  )
                }
              }
            }
          }
        }
      }
    }

    private func finishVideoLibrarySmokeTest(
      fixtureURL: URL,
      initialItems: [VideoSidebarItem],
      fileHidden: Bool,
      directoryHidden: Bool,
      associationRemoved: Bool
    ) {
      let relinkedVideos = videoLibrary.videos
      let relinkedItems = videoSidebarItems
      guard
        let videoItem = relinkedItems.first(
          where: {
            $0.kind == .video
              && $0.relativePath == "root_clip.mp4"
          }
        )
      else {
        writeVideoLibraryResult([
          "status": "relinked-video-not-found"
        ])
        return
      }

      playVideo(videoItem)
      DispatchQueue.main.asyncAfter(
        deadline: .now() + 0.8
      ) { [weak self] in
        guard
          let self,
          let playerController =
            self.presentedViewController
              as? VideoPlayerViewController
        else {
          self?.writeVideoLibraryResult([
            "status": "player-not-presented"
          ])
          return
        }
        let rateBeforePause = playerController.player?.rate ?? 0
        NotificationCenter.default.post(
          name: UIApplication.willResignActiveNotification,
          object: nil
        )
        DispatchQueue.main.asyncAfter(
          deadline: .now() + 0.2
        ) { [weak self, weak playerController] in
          guard let self else { return }
          let rateAfterPause =
            playerController?.player?.rate ?? -1
          let extensions = Set(
            relinkedVideos.map {
              URL(fileURLWithPath: $0.filename)
                .pathExtension.lowercased()
            }
          ).sorted()
          let directoryPaths = Set(
            relinkedVideos.compactMap(\.directoryRelativePath)
          ).sorted()
          let sourceFilesStillExist =
            [
              "root_clip.mp4",
              "Level_1/child_clip.mov",
              "Level_1/Level_2/deep_clip.m4v",
              "Sibling/sibling_clip.ts",
            ].allSatisfy {
              FileManager.default.fileExists(
                atPath: fixtureURL.appendingPathComponent($0).path
              )
            }
          let passed =
            fileHidden
            && directoryHidden
            && associationRemoved
            && relinkedVideos.count == 4
            && extensions == ["m4v", "mov", "mp4", "ts"]
            && directoryPaths
              == ["Level_1", "Level_1/Level_2", "Sibling"]
            && initialItems.filter { $0.kind == .video }.count == 4
            && initialItems.filter { $0.kind == .folder }.count == 4
            && sourceFilesStillExist
            && rateBeforePause > 0
            && rateAfterPause == 0
          self.writeVideoLibraryResult([
            "status": passed ? "passed" : "failed",
            "videoCount": relinkedVideos.count,
            "sidebarItemCount": relinkedItems.count,
            "videoRowCount":
              relinkedItems.filter { $0.kind == .video }.count,
            "folderRowCount":
              relinkedItems.filter { $0.kind == .folder }.count,
            "maximumDepth":
              relinkedItems.map(\.depth).max() ?? 0,
            "formats": extensions,
            "directoryPaths": directoryPaths,
            "fileHiddenWithoutDeletion": fileHidden,
            "directoryHiddenWithoutDeletion": directoryHidden,
            "associationRemovedWithoutDeletion":
              associationRemoved,
            "sourceFilesStillExist": sourceFilesStillExist,
            "rateBeforeBackgroundPause": rateBeforePause,
            "rateAfterBackgroundPause": rateAfterPause,
          ])
        }
      }
    }

    private func writeVideoLibraryResult(
      _ result: [String: Any]
    ) {
      let documentsURL = FileManager.default.urls(
        for: .documentDirectory,
        in: .userDomainMask
      )[0]
      let resultURL = documentsURL.appendingPathComponent(
        "video-library-result.json"
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

    private func simulatorFixtureDirectories(
      arguments: [String]
    ) -> [URL] {
      let documentsURL = FileManager.default.urls(
        for: .documentDirectory,
        in: .userDomainMask
      )[0]
      var directories = [
        documentsURL.appendingPathComponent(
          "SimulatorFixtures",
          isDirectory: true
        )
      ]
      if arguments.contains("--import-secondary-simulator-fixture") {
        directories.append(
          documentsURL.appendingPathComponent(
            "SimulatorFixturesSecondary",
            isDirectory: true
          )
        )
      }
      return directories
    }

    private func selectPrimaryFixtureFolder(
      _ directories: [URL]
    ) {
      guard
        let primaryDirectory = directories.first,
        let folderID = library.folderID(for: primaryDirectory)
      else {
        return
      }
      selectedFolderID = folderID
      selectsStandaloneFolder = false
      persistFolderSelection()
    }

    private func handleDebugSidebarArgumentsIfNeeded() {
      let arguments = ProcessInfo.processInfo.arguments
      guard !didHandleDebugSidebarArguments else { return }
      didHandleDebugSidebarArguments = true

      if arguments.contains("--select-secondary-simulator-folder") {
        DispatchQueue.main.asyncAfter(
          deadline: .now() + 2
        ) { [weak self] in
          self?.selectSecondaryFixtureFolderForTesting(
            showsSidebar: arguments.contains(
              "--show-folder-sidebar"
            )
          )
        }
      } else if
        arguments.contains("--show-folder-sidebar"),
        !arguments.contains("--select-first-child-directory"),
        !arguments.contains("--collapse-primary-folder")
      {
        DispatchQueue.main.asyncAfter(
          deadline: .now() + 2
        ) { [weak self] in
          self?.showFolderSidebar()
        }
      }

      if arguments.contains("--debug-delete-secondary-folder") {
        DispatchQueue.main.asyncAfter(
          deadline: .now() + 2
        ) { [weak self] in
          self?.deleteSecondaryFixtureFolderForTesting()
        }
      }

      if arguments.contains("--show-folder-batch-progress") {
        DispatchQueue.main.asyncAfter(
          deadline: .now() + 2
        ) { [weak self] in
          self?.showFolderBatchProgressForTesting()
        }
      }

      if arguments.contains("--select-first-child-directory") {
        DispatchQueue.main.asyncAfter(
          deadline: .now() + 2
        ) { [weak self] in
          self?.selectFirstChildDirectoryForTesting(
            showsSidebar: arguments.contains(
              "--show-folder-sidebar"
            )
          )
        }
      }

      if arguments.contains("--collapse-primary-folder") {
        DispatchQueue.main.asyncAfter(
          deadline: .now() + 2
        ) { [weak self] in
          self?.collapsePrimaryFolderForTesting(
            showsSidebar: arguments.contains(
              "--show-folder-sidebar"
            )
          )
        }
      }
    }

    private func collapsePrimaryFolderForTesting(
      showsSidebar: Bool
    ) {
      guard
        let folderID = selectedFolderID,
        let childItem = sidebarItems.first(
          where: {
            $0.folderID == folderID
              && $0.directoryRelativePath != nil
              && $0.imageCount > 0
          }
        )
      else {
        writeFolderCollapseResult([
          "status": "collapsible-folder-not-found"
        ])
        return
      }

      selectCollection(childItem)
      updateFolderSidebar()
      let expandedItemCount =
        folderSidebarView.visibleItemCountForTesting
      folderSidebarView.setFolderCollapsedForTesting(
        true,
        folderID: folderID
      )
      let collapsedItemCount =
        folderSidebarView.visibleItemCountForTesting
      let collapsedParentTitle =
        folderSidebarView.selectedVisibleItemTitleForTesting ?? ""
      let pageAfterCollapse = currentPageIndex
      folderSidebarView.setFolderCollapsedForTesting(
        false,
        folderID: folderID
      )
      let reexpandedItemCount =
        folderSidebarView.visibleItemCountForTesting
      folderSidebarView.setFolderCollapsedForTesting(
        true,
        folderID: folderID
      )

      writeFolderCollapseResult([
        "status": "passed",
        "folderCollapsed":
          folderSidebarView.isFolderCollapsedForTesting(folderID),
        "totalItemCount":
          folderSidebarView.totalItemCountForTesting,
        "expandedItemCount": expandedItemCount,
        "collapsedItemCount": collapsedItemCount,
        "reexpandedItemCount": reexpandedItemCount,
        "selectedVisibleTitle": collapsedParentTitle,
        "pageAfterCollapse": pageAfterCollapse,
      ])
      if showsSidebar {
        showFolderSidebar()
      }
    }

    private func writeFolderCollapseResult(
      _ result: [String: Any]
    ) {
      let documentsURL = FileManager.default.urls(
        for: .documentDirectory,
        in: .userDomainMask
      )[0]
      let resultURL = documentsURL.appendingPathComponent(
        "folder-collapse-result.json"
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

    private func selectFirstChildDirectoryForTesting(
      showsSidebar: Bool
    ) {
      guard
        let item = sidebarItems.first(
          where: {
            $0.folderID == selectedFolderID
              && $0.directoryRelativePath != nil
              && $0.imageCount > 0
          }
        )
      else {
        writeChildDirectoryResult([
          "status": "child-directory-not-found"
        ])
        return
      }

      selectCollection(item)
      writeChildDirectoryResult([
        "status": "passed",
        "selectedDirectory": currentDirectoryRelativePath ?? "",
        "currentPageIndex": currentPageIndex,
        "documentCount": documents.count,
        "previousDirectory":
          currentPageIndex > 0
          ? documents[currentPageIndex - 1].directoryRelativePath
            ?? "__root__"
          : "",
      ])
      if showsSidebar {
        DispatchQueue.main.asyncAfter(
          deadline: .now() + 0.3
        ) { [weak self] in
          self?.showFolderSidebar()
        }
      }
    }

    private func writeChildDirectoryResult(
      _ result: [String: Any]
    ) {
      let documentsURL = FileManager.default.urls(
        for: .documentDirectory,
        in: .userDomainMask
      )[0]
      let resultURL = documentsURL.appendingPathComponent(
        "child-directory-result.json"
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

    private func showFolderBatchProgressForTesting() {
      let directories = simulatorFixtureDirectories(
        arguments: [
          "--import-secondary-simulator-fixture"
        ]
      )
      resetFolderBatchSelection()
      isSelectingFolderBatch = true
      appendPendingFolders(directories)
      presentFolderBatchProgress()
    }

    private func selectSecondaryFixtureFolderForTesting(
      showsSidebar: Bool
    ) {
      let directories = simulatorFixtureDirectories(
        arguments: [
          "--import-secondary-simulator-fixture"
        ]
      )
      guard
        directories.count > 1,
        let folderID = library.folderID(for: directories[1]),
        let item = sidebarItems.first(
          where: { $0.folderID == folderID }
        )
      else {
        return
      }

      selectCollection(item)
      writeFolderSelectionResult([
        "status": "passed",
        "selectedFolderTitle": selectedCollectionTitle,
        "selectedDocumentCount": documents.count,
        "pageCount": documents.count,
        "sidebarItemCount": sidebarItems.count,
      ])
      if showsSidebar {
        DispatchQueue.main.asyncAfter(
          deadline: .now() + 0.3
        ) { [weak self] in
          self?.showFolderSidebar()
        }
      }
    }

    private func deleteSecondaryFixtureFolderForTesting() {
      let directories = simulatorFixtureDirectories(
        arguments: [
          "--import-secondary-simulator-fixture"
        ]
      )
      guard
        directories.count > 1,
        let folderID = library.folderID(for: directories[1])
      else {
        writeFolderManagementResult([
          "status": "secondary-folder-not-found"
        ])
        return
      }

      library.removeCollection(folderID: folderID) {
        [weak self] result in
        guard let self else { return }
        switch result {
        case .success:
          self.ensureFolderSelectionIsValid()
          self.reloadLibrary(preservingPage: false)
          self.writeFolderManagementResult([
            "status": "passed",
            "folderCount": self.library.folders.count,
            "sidebarItemCount": self.sidebarItems.count,
            "selectedDocumentCount": self.documents.count,
            "sourceFolderStillExists":
              FileManager.default.fileExists(
                atPath: directories[1].path
              ),
          ])
        case .failure(let error):
          self.writeFolderManagementResult([
            "status": "delete-failed",
            "error": error.localizedDescription,
          ])
        }
      }
    }

    private func writeFolderManagementResult(
      _ result: [String: Any]
    ) {
      let documentsURL = FileManager.default.urls(
        for: .documentDirectory,
        in: .userDomainMask
      )[0]
      let resultURL = documentsURL.appendingPathComponent(
        "folder-management-result.json"
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

    private func writeFolderSelectionResult(
      _ result: [String: Any]
    ) {
      let documentsURL = FileManager.default.urls(
        for: .documentDirectory,
        in: .userDomainMask
      )[0]
      let resultURL = documentsURL.appendingPathComponent(
        "folder-selection-result.json"
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

    private func scheduleSmokeTestIfRequested() {
      guard
        ProcessInfo.processInfo.arguments.contains(
          "--auto-scroll-smoke-test"
        )
      else {
        return
      }
      DispatchQueue.main.asyncAfter(
        deadline: .now() + 2
      ) { [weak self] in
        self?.startSmokeTestIfRequested()
      }
    }

    private func startSmokeTestIfRequested() {
      guard
        ProcessInfo.processInfo.arguments.contains(
          "--auto-scroll-smoke-test"
        ),
        smokeTestDisplayLink == nil,
        !documents.isEmpty
      else {
        return
      }

      collectionView.layoutIfNeeded()
      smokeTestInitialTileCount = library.materializedTileCount
      smokeTestPeakMemoryBytes = ProcessMemoryMonitor.usedBytes ?? 0
      smokeTestStartTime = CACurrentMediaTime()
      smokeTestLastFrameTime = smokeTestStartTime
      smokeTestVisitedPages = [currentPageIndex]

      let displayLink = CADisplayLink(
        target: self,
        selector: #selector(runSmokeTestFrame(_:))
      )
      displayLink.preferredFrameRateRange = CAFrameRateRange(
        minimum: 60,
        maximum: 120,
        preferred: 120
      )
      displayLink.add(to: .main, forMode: .common)
      smokeTestDisplayLink = displayLink
    }

    @objc private func runSmokeTestFrame(_ displayLink: CADisplayLink) {
      let elapsed = displayLink.timestamp - smokeTestStartTime
      let frameDuration = displayLink.timestamp - smokeTestLastFrameTime
      smokeTestLastFrameTime = displayLink.timestamp
      smokeTestFrameCount += 1
      if frameDuration > (1.0 / 45.0) {
        smokeTestSlowFrameCount += 1
      }

      let maximumOffset = max(
        0,
        collectionView.contentSize.height
          - collectionView.bounds.height
      )
      let progress = min(1, elapsed / 18)
      collectionView.contentOffset.y = maximumOffset * progress
      updateCurrentPage()
      smokeTestVisitedPages.insert(currentPageIndex)
      if let usedBytes = ProcessMemoryMonitor.usedBytes {
        smokeTestPeakMemoryBytes = max(
          smokeTestPeakMemoryBytes,
          usedBytes
        )
      }

      guard progress >= 1 else { return }
      displayLink.invalidate()
      smokeTestDisplayLink = nil

      let averageFPS = Double(smokeTestFrameCount) / max(elapsed, 0.001)
      let sortOrders = Dictionary(
        uniqueKeysWithValues: ImageSortOption.allCases.map { option in
          (
            option.rawValue,
            selectsStandaloneFolder
              ? option.sort(documents).map(\.filename)
              : library.documents(
                in: selectedFolderID,
                sortedBy: option
              ).map(\.filename)
          )
        }
      )
      let directoryOrder = documents.map {
        $0.directoryRelativePath ?? "__root__"
      }
      let directorySummaries: [[String: Any]]
      if
        let selectedFolderID,
        let selectedFolder = library.folders.first(
          where: { $0.id == selectedFolderID }
        )
      {
        directorySummaries = library.directorySummaries(
          in: selectedFolder
        ).map { summary in
          [
            "relativePath": summary.relativePath ?? "__root__",
            "displayName": summary.displayName,
            "imageCount": summary.imageCount,
          ]
        }
      } else {
        directorySummaries = []
      }
      writeSmokeTestResult([
        "status": "passed",
        "documentCount": documents.count,
        "visitedPageCount": smokeTestVisitedPages.count,
        "frameCount": smokeTestFrameCount,
        "slowFrameCount": smokeTestSlowFrameCount,
        "durationSeconds": round(elapsed * 100) / 100,
        "averageFPS": round(averageFPS * 10) / 10,
        "contentHeight": round(collectionView.contentSize.height),
        "sortOrders": sortOrders,
        "directoryOrder": directoryOrder,
        "directoryCount": Set(directoryOrder).count,
        "directorySummaries": directorySummaries,
        "folderCount": library.folders.count,
        "sidebarItemCount": sidebarItems.count,
        "selectedFolderTitle": selectedCollectionTitle,
        "usedMemoryBytes": ProcessMemoryMonitor.usedBytes ?? 0,
        "peakMemoryBytes": smokeTestPeakMemoryBytes,
        "initialMaterializedTileCount": smokeTestInitialTileCount,
        "finalMaterializedTileCount": library.materializedTileCount,
        "expectedTileCount": displayTiles.count,
        "directorySyncDurationSeconds":
          round(smokeTestDirectorySyncDuration * 100) / 100,
      ])
    }

    private func writeSmokeTestResult(_ result: [String: Any]) {
      let documentsURL = FileManager.default.urls(
        for: .documentDirectory,
        in: .userDomainMask
      )[0]
      let resultURL = documentsURL.appendingPathComponent(
        "simulator-smoke-test-result.json"
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

extension ViewerViewController:
  UICollectionViewDataSource,
  UICollectionViewDelegateFlowLayout
{
  func collectionView(
    _ collectionView: UICollectionView,
    numberOfItemsInSection section: Int
  ) -> Int {
    displayTiles.count
  }

  func collectionView(
    _ collectionView: UICollectionView,
    cellForItemAt indexPath: IndexPath
  ) -> UICollectionViewCell {
    guard
      let cell = collectionView.dequeueReusableCell(
        withReuseIdentifier: ImageTileCell.reuseIdentifier,
        for: indexPath
      ) as? ImageTileCell
    else {
      return UICollectionViewCell()
    }

    let displayTile = displayTiles[indexPath.item]
    cell.configure(
      with: displayTile,
      imageURL: library.tileURL(for: displayTile.tile)
    ) { [library] in
      try library.materializeTile(for: displayTile)
    }
    return cell
  }

  func collectionView(
    _ collectionView: UICollectionView,
    layout collectionViewLayout: UICollectionViewLayout,
    sizeForItemAt indexPath: IndexPath
  ) -> CGSize {
    let tile = displayTiles[indexPath.item].tile
    let width = collectionView.bounds.width
    let height =
      CGFloat(tile.pixelHeight)
      * width
      / CGFloat(tile.pixelWidth)
    return CGSize(width: width, height: height)
  }

  func scrollViewDidScroll(_ scrollView: UIScrollView) {
    updateCurrentPage()
  }
}

extension ViewerViewController: FolderSidebarViewDelegate {
  func folderSidebar(
    _ sidebar: FolderSidebarView,
    didSelect item: FolderSidebarItem
  ) {
    selectCollection(item)
  }

  func folderSidebar(
    _ sidebar: FolderSidebarView,
    didRequestDelete item: FolderSidebarItem
  ) {
    let message: String
    if item.folderID == nil {
      message = L("collection.remove_manual_message")
    } else {
      message = L("collection.remove_folder_message")
    }
    let alert = UIAlertController(
      title: L("collection.remove_title_format", item.title),
      message: message,
      preferredStyle: .alert
    )
    alert.addAction(
      UIAlertAction(title: L("common.cancel"), style: .cancel)
    )
    alert.addAction(
      UIAlertAction(title: L("common.remove"), style: .destructive) {
        [weak self] _ in
        guard let self else { return }
        let removesCurrentCollection =
          item.folderID == self.selectedFolderID
          && (item.folderID != nil || self.selectsStandaloneFolder)
        self.library.removeCollection(
          folderID: item.folderID
        ) { result in
          switch result {
          case .success:
            if removesCurrentCollection {
              self.selectDefaultCollection()
            }
            ImagePipeline.shared.clearCache()
            self.reloadLibrary(preservingPage: false)
            self.updateFolderSidebar()
          case .failure(let error):
            self.presentError(error)
          }
        }
      }
    )
    present(alert, animated: true)
  }

  func folderSidebar(
    _ sidebar: FolderSidebarView,
    didChangeMode mode: SidebarMediaMode
  ) {
    sidebarMode = mode
    UserDefaults.standard.set(
      mode.rawValue,
      forKey: SelectionStorage.sidebarModeKey
    )
  }

  func folderSidebar(
    _ sidebar: FolderSidebarView,
    didSelectVideo item: VideoSidebarItem
  ) {
    playVideo(item)
  }

  func folderSidebar(
    _ sidebar: FolderSidebarView,
    didRequestDeleteVideo item: VideoSidebarItem
  ) {
    let isRoot = item.kind == .folder && item.relativePath == nil
    let message =
      isRoot
      ? L("video.remove_root_message")
      : item.kind == .folder
        ? L("video.hide_folder_message")
        : L("video.hide_file_message")
    let alert = UIAlertController(
      title: L("collection.remove_title_format", item.title),
      message: message,
      preferredStyle: .alert
    )
    alert.addAction(
      UIAlertAction(title: L("common.cancel"), style: .cancel)
    )
    alert.addAction(
      UIAlertAction(title: L("common.remove"), style: .destructive) {
        [weak self] _ in
        guard let self else { return }
        let completion: (Result<Void, Error>) -> Void = {
          [weak self] result in
          guard let self else { return }
          switch result {
          case .success:
            if
              self.selectedVideoFolderID == item.folderID,
              isRoot
                || self.videoItem(
                  item,
                  contains: self.selectedVideoRelativePath
                )
            {
              self.selectedVideoFolderID = nil
              self.selectedVideoRelativePath = nil
            }
            self.updateFolderSidebar()
          case .failure(let error):
            self.presentError(error)
          }
        }
        if isRoot {
          self.videoLibrary.removeFolder(
            item.folderID,
            completion: completion
          )
        } else if let relativePath = item.relativePath {
          self.videoLibrary.hideItem(
            folderID: item.folderID,
            relativePath: relativePath,
            isDirectory: item.kind == .folder,
            completion: completion
          )
        }
      }
    )
    present(alert, animated: true)
  }

  private func videoItem(
    _ item: VideoSidebarItem,
    contains selectedRelativePath: String?
  ) -> Bool {
    guard
      let itemPath = item.relativePath,
      let selectedRelativePath
    else {
      return false
    }
    if item.kind == .video {
      return itemPath == selectedRelativePath
    }
    return selectedRelativePath == itemPath
      || selectedRelativePath.hasPrefix(itemPath + "/")
  }

  func folderSidebarDidRequestClose(_ sidebar: FolderSidebarView) {
    hideFolderSidebar()
  }
}

extension ViewerViewController:
  UICollectionViewDataSourcePrefetching
{
  func collectionView(
    _ collectionView: UICollectionView,
    prefetchItemsAt indexPaths: [IndexPath]
  ) {
    for indexPath in indexPaths {
      guard displayTiles.indices.contains(indexPath.item) else {
        continue
      }
      let displayTile = displayTiles[indexPath.item]
      guard
        indexPath.item <= maximumVisibleItem + 2,
        prefetchRequests[indexPath] == nil
      else {
        continue
      }
      prefetchRequests[indexPath] = ImagePipeline.shared.prefetch(
        at: library.tileURL(for: displayTile.tile),
        cacheKey: displayTile.id
      ) { [library] in
        try library.materializeTile(for: displayTile)
      }
    }
  }

  func collectionView(
    _ collectionView: UICollectionView,
    cancelPrefetchingForItemsAt indexPaths: [IndexPath]
  ) {
    for indexPath in indexPaths {
      prefetchRequests.removeValue(forKey: indexPath)?.cancel()
    }
  }

  private var maximumVisibleItem: Int {
    collectionView.indexPathsForVisibleItems
      .map(\.item)
      .max() ?? 0
  }
}

extension ViewerViewController: UIDocumentPickerDelegate {
  func documentPicker(
    _ controller: UIDocumentPickerViewController,
    didPickDocumentsAt urls: [URL]
  ) {
    guard !urls.isEmpty else { return }

    if pickerMode == .imageFolder {
      appendPendingFolders(urls)
      DispatchQueue.main.asyncAfter(
        deadline: .now() + 0.25
      ) { [weak self] in
        self?.presentFolderBatchProgress()
      }
      return
    }

    if pickerMode == .videoFolder {
      guard let folderURL = urls.first else { return }
      setImporting(true)
      videoLibrary.addFolder(from: folderURL) {
        [weak self] result in
        guard let self else { return }
        self.setImporting(false)
        switch result {
        case .success(let summary):
          self.sidebarMode = .videos
          UserDefaults.standard.set(
            SidebarMediaMode.videos.rawValue,
            forKey: SelectionStorage.sidebarModeKey
          )
          self.updateFolderSidebar()
          self.showFolderSidebar()
          self.presentVideoSyncSummary(
            summary,
            title: L("video.folder_added")
          )
        case .failure(let error):
          self.presentError(error)
        }
      }
      return
    }

    setImporting(true)
    library.importImages(from: urls) { [weak self] result in
      guard let self else { return }
      self.setImporting(false)

      switch result {
      case .success(let summary):
        self.selectedFolderID = nil
        self.selectsStandaloneFolder = true
        self.persistFolderSelection()
        self.reloadLibrary(preservingPage: false)

        if let firstImported = summary.importedDocuments.first,
          let pageIndex = self.documents.firstIndex(
            where: { $0.id == firstImported.id }
          )
        {
          self.scrollToPage(at: pageIndex, animated: false)
        }

        guard !summary.failedFilenames.isEmpty else { return }
        let failedNames = summary.failedFilenames.joined(
          separator: "\n"
        )
        let alert = UIAlertController(
          title: L("import.partial_failed"),
          message: failedNames,
          preferredStyle: .alert
        )
        alert.addAction(
          UIAlertAction(title: L("common.ok"), style: .default)
        )
        self.present(alert, animated: true)

      case .failure(let error):
        self.presentError(error)
      }
    }
  }

  func documentPickerWasCancelled(
    _ controller: UIDocumentPickerViewController
  ) {
    guard
      pickerMode == .imageFolder,
      isSelectingFolderBatch
    else {
      return
    }

    if pendingFolderURLs.isEmpty {
      resetFolderBatchSelection()
    } else {
      DispatchQueue.main.asyncAfter(
        deadline: .now() + 0.25
      ) { [weak self] in
        self?.presentFolderBatchProgress()
      }
    }
  }
}
