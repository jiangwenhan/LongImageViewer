import UIKit
import UniformTypeIdentifiers

final class ViewerViewController: UIViewController {
  private enum PickerMode {
    case images
    case folder
  }

  private let tileOverlap = 1 / UIScreen.main.scale
  private let library = ImageLibrary.shared
  private var documents: [ImageDocument] = []
  private var displayTiles: [DisplayTile] = []
  private var pageStartOffsets: [CGFloat] = []
  private var lastLaidOutWidth: CGFloat = 0
  private var currentPageIndex = 0
  private var pickerMode = PickerMode.images
  private var memoryTimer: Timer?
  private var isSynchronizingFolders = false
  private var prefetchRequests: [IndexPath: ImageRequestToken] = [:]

  #if DEBUG
    private var didProcessSimulatorFixtures = false
    private var smokeTestDisplayLink: CADisplayLink?
    private var smokeTestStartTime: CFTimeInterval = 0
    private var smokeTestLastFrameTime: CFTimeInterval = 0
    private var smokeTestFrameCount = 0
    private var smokeTestSlowFrameCount = 0
    private var smokeTestVisitedPages: Set<Int> = []
    private var smokeTestInitialTileCount = 0
    private var smokeTestPeakMemoryBytes: UInt64 = 0
    private var smokeTestDirectorySyncDuration: TimeInterval = 0
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
    button.accessibilityLabel = "排序"
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
    configuration.title = "来源"
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
    label.text = "还没有长图"
    label.font = .systemFont(ofSize: 22, weight: .bold)
    label.textColor = .white
    label.textAlignment = .center
    return label
  }()
  private let emptySubtitleLabel: UILabel = {
    let label = UILabel()
    label.text = "浏览“我的 iPhone”、iCloud Drive\n或 Mac 本地目录中的图片"
    label.font = .systemFont(ofSize: 15, weight: .regular)
    label.textColor = UIColor(white: 0.72, alpha: 1)
    label.textAlignment = .center
    label.numberOfLines = 0
    return label
  }()
  private let emptyImportButton: UIButton = {
    var configuration = UIButton.Configuration.filled()
    configuration.title = "浏览图片文件夹"
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

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    setupViews()
    setupActions()
    startMemoryUpdates()
    reloadLibrary(preservingPage: false)
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(applicationDidBecomeActive),
      name: UIApplication.didBecomeActiveNotification,
      object: nil
    )
  }

  deinit {
    memoryTimer?.invalidate()
    NotificationCenter.default.removeObserver(self)
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()

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
    view.bringSubviewToFront(activityIndicator)

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

      activityIndicator.centerXAnchor.constraint(
        equalTo: view.centerXAnchor
      ),
      activityIndicator.centerYAnchor.constraint(
        equalTo: view.centerYAnchor
      ),
    ])
  }

  private func setupActions() {
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
      title: "清空全部图片",
      image: UIImage(systemName: "trash"),
      attributes: .destructive
    ) { [weak self] _ in
      self?.confirmDeleteAll()
    }
    return UIMenu(
      title: "图片排序",
      children: actions + [deleteAction]
    )
  }

  @objc private func sourceButtonTapped() {
    let sheet = UIAlertController(
      title: "图片来源",
      message: folderStatusMessage,
      preferredStyle: .actionSheet
    )
    sheet.addAction(
      UIAlertAction(
        title: "浏览图片文件夹",
        style: .default
      ) { [weak self] _ in
        self?.presentFolderPicker()
      }
    )
    sheet.addAction(
      UIAlertAction(
        title: "选择图片文件",
        style: .default
      ) { [weak self] _ in
        self?.presentImagePicker()
      }
    )
    sheet.addAction(
      UIAlertAction(
        title: "同步已添加文件夹",
        style: .default
      ) { [weak self] _ in
        self?.syncFolders(showResult: true)
      }
    )
    sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
    sheet.popoverPresentationController?.sourceView = addButton
    sheet.popoverPresentationController?.sourceRect = addButton.bounds
    present(sheet, animated: true)
  }

  @objc private func selectFolderTapped() {
    presentFolderPicker()
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
    pickerMode = .folder
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

  private var folderStatusMessage: String {
    guard !library.folderDisplayNames.isEmpty else {
      return "可进入“我的 iPhone”、iCloud Drive，或 Mac 本地目录"
    }
    return "已添加：\(library.folderDisplayNames.joined(separator: "、"))"
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
    guard !library.folders.isEmpty else { return }
    syncFolders(showResult: false)
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
        if summary.addedCount > 0
          || summary.updatedCount > 0
          || summary.removedCount > 0
        {
          ImagePipeline.shared.clearCache()
          self.reloadLibrary(preservingPage: true)
        }
        if showResult {
          self.presentFolderSyncSummary(
            summary,
            title: "文件夹同步完成"
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
      "新增 \(summary.addedCount) 张",
      "更新 \(summary.updatedCount) 张",
      "移除 \(summary.removedCount) 张",
    ]
    if !summary.failedFilenames.isEmpty {
      lines.append("读取失败：\(summary.failedFilenames.joined(separator: "、"))")
    }
    if !summary.unavailableFolders.isEmpty {
      lines.append(
        "无法访问：\(summary.unavailableFolders.joined(separator: "、"))"
      )
    }

    let alert = UIAlertController(
      title: title,
      message: lines.joined(separator: "\n"),
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "好", style: .default))
    present(alert, animated: true)
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
      title: "清空全部图片？",
      message: "图片缓存和文件夹关联将从 App 中删除，此操作不会影响原文件。",
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.addAction(
      UIAlertAction(title: "清空", style: .destructive) {
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

    let previousPage = preservingPage ? currentPageIndex : 0
    documents = library.sortedDocuments
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
  }

  private func updateEmptyState() {
    let isEmpty = documents.isEmpty
    emptyStateView.isHidden = !isEmpty
    overlayView.isHidden = false
    sortButton.isHidden = isEmpty
    addButton.isHidden = isEmpty
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
      title: "操作失败",
      message: error.localizedDescription,
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "好", style: .default))
    present(alert, animated: true)
  }

  #if DEBUG
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

      guard documents.isEmpty else {
        library.syncFolders { [weak self] result in
          guard let self else { return }
          self.smokeTestDirectorySyncDuration =
            CACurrentMediaTime() - syncStartTime
          if case .success = result {
            ImagePipeline.shared.clearCache()
            self.reloadLibrary(preservingPage: false)
          }
          self.scheduleSmokeTestIfRequested()
        }
        return
      }

      let fixtureDirectory = FileManager.default.urls(
        for: .documentDirectory,
        in: .userDomainMask
      )[0].appendingPathComponent(
        "SimulatorFixtures",
        isDirectory: true
      )
      setImporting(true)
      library.addFolder(from: fixtureDirectory) { [weak self] result in
        guard let self else { return }
        self.smokeTestDirectorySyncDuration =
          CACurrentMediaTime() - syncStartTime
        self.setImporting(false)

        switch result {
        case .success:
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
            option.sort(documents).map(\.filename)
          )
        }
      )
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
        "folderCount": library.folders.count,
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

    if pickerMode == .folder {
      setImporting(true)
      library.addFolder(from: urls[0]) { [weak self] result in
        guard let self else { return }
        self.setImporting(false)

        switch result {
        case .success(let summary):
          ImagePipeline.shared.clearCache()
          self.reloadLibrary(preservingPage: false)
          self.presentFolderSyncSummary(
            summary,
            title: "文件夹已添加"
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
          title: "部分图片未导入",
          message: failedNames,
          preferredStyle: .alert
        )
        alert.addAction(
          UIAlertAction(title: "好", style: .default)
        )
        self.present(alert, animated: true)

      case .failure(let error):
        self.presentError(error)
      }
    }
  }
}
