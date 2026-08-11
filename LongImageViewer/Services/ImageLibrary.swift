import CoreImage
import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

struct ImageImportSummary {
  let importedDocuments: [ImageDocument]
  let failedFilenames: [String]
}

struct FolderSyncSummary {
  let addedCount: Int
  let updatedCount: Int
  let removedCount: Int
  let failedFilenames: [String]
  let unavailableFolders: [String]
}

enum ImageLibraryError: LocalizedError {
  case invalidImage(String)
  case tileEncodingFailed(String)
  case noImagesImported
  case noFolders
  case folderAccessFailed(String)

  var errorDescription: String? {
    switch self {
    case .invalidImage(let filename):
      return L("error.invalid_image_format", filename)
    case .tileEncodingFailed(let filename):
      return L("error.tile_encoding_format", filename)
    case .noImagesImported:
      return L("error.no_images_imported")
    case .noFolders:
      return L("error.no_folders")
    case .folderAccessFailed(let folderName):
      return L("error.folder_access_format", folderName)
    }
  }
}

final class ImageLibrary {
  static let shared = ImageLibrary()

  private enum Constants {
    static let targetPixelWidth = 1_284
    static let tilePixelHeight = 1_536
    static let manifestFilename = "manifest.json"
    static let folderManifestFilename = "folders.json"
    static let sortDefaultsKey = "imageSortOption"
  }

  private let fileManager = FileManager.default
  private let importQueue = DispatchQueue(
    label: "com.trae.LongImageViewer.import",
    qos: .userInitiated
  )
  private let storageURL: URL
  private let sourceStorageURL: URL
  private let manifestURL: URL
  private let folderManifestURL: URL
  private let ciContext = CIContext(
    options: [
      .cacheIntermediates: false,
      .useSoftwareRenderer: false,
    ]
  )

  private(set) var documents: [ImageDocument]
  private(set) var folders: [ImageFolder]
  private(set) var sortOption: ImageSortOption

  var sortedDocuments: [ImageDocument] {
    sortOption.sort(documents)
  }

  var hasStandaloneDocuments: Bool {
    documents.contains { $0.sourceFolderID == nil }
  }

  var folderDisplayNames: [String] {
    folders.map(\.displayName)
  }

  func documents(in folderID: UUID?) -> [ImageDocument] {
    sortOption.sort(
      documents.filter { $0.sourceFolderID == folderID }
    )
  }

  func imageCount(in folderID: UUID?) -> Int {
    documents.lazy.filter { $0.sourceFolderID == folderID }.count
  }

  func folderID(for url: URL) -> UUID? {
    let path = url.standardizedFileURL.path
    return folders.first { $0.pathHint == path }?.id
  }

  var materializedTileCount: Int {
    guard
      let enumerator = fileManager.enumerator(
        at: storageURL,
        includingPropertiesForKeys: nil
      )
    else {
      return 0
    }
    return enumerator.compactMap { $0 as? URL }
      .filter { $0.pathExtension.lowercased() == "png" }
      .count
  }

  private init() {
    let applicationSupport = fileManager.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    )[0]
    storageURL =
      applicationSupport
      .appendingPathComponent("LongImageViewer", isDirectory: true)
      .appendingPathComponent("Pages", isDirectory: true)
    sourceStorageURL =
      storageURL
      .deletingLastPathComponent()
      .appendingPathComponent("Sources", isDirectory: true)
    manifestURL =
      storageURL
      .deletingLastPathComponent()
      .appendingPathComponent(Constants.manifestFilename)
    folderManifestURL =
      storageURL
      .deletingLastPathComponent()
      .appendingPathComponent(Constants.folderManifestFilename)

    let savedSort = UserDefaults.standard.string(
      forKey: Constants.sortDefaultsKey
    )
    sortOption =
      savedSort
      .flatMap(ImageSortOption.init(rawValue:))
      ?? .creationAscending

    do {
      try fileManager.createDirectory(
        at: storageURL,
        withIntermediateDirectories: true
      )
      try fileManager.createDirectory(
        at: sourceStorageURL,
        withIntermediateDirectories: true
      )
      let data = try Data(contentsOf: manifestURL)
      documents = try JSONDecoder().decode(
        [ImageDocument].self,
        from: data
      )
    } catch {
      documents = []
    }

    do {
      let data = try Data(contentsOf: folderManifestURL)
      folders = try JSONDecoder().decode(
        [ImageFolder].self,
        from: data
      )
    } catch {
      folders = []
    }
  }

  func setSortOption(_ option: ImageSortOption) {
    sortOption = option
    UserDefaults.standard.set(
      option.rawValue,
      forKey: Constants.sortDefaultsKey
    )
  }

  func tileURL(for tile: ImageTile) -> URL {
    storageURL.appendingPathComponent(tile.relativePath)
  }

  func materializeTile(for displayTile: DisplayTile) throws {
    let document = displayTile.document
    let tile = displayTile.tile
    let outputURL = tileURL(for: tile)
    guard !fileManager.fileExists(atPath: outputURL.path) else {
      return
    }
    guard
      let relativePath = document.sourceRelativePath
    else {
      throw ImageLibraryError.invalidImage(document.filename)
    }

    let accessRootURL: URL
    let sourceURL: URL
    if let folderID = document.sourceFolderID,
      let folder = folders.first(where: { $0.id == folderID }),
      let folderURL = resolveFolder(folder)
    {
      accessRootURL = folderURL
      sourceURL = folderURL.appendingPathComponent(relativePath)
    } else {
      accessRootURL = sourceStorageURL
      sourceURL = sourceStorageURL.appendingPathComponent(relativePath)
    }

    let hasAccess = accessRootURL.startAccessingSecurityScopedResource()
    defer {
      if hasAccess {
        accessRootURL.stopAccessingSecurityScopedResource()
      }
    }

    var coordinationError: NSError?
    var generationError: Error?
    let coordinator = NSFileCoordinator(filePresenter: nil)
    coordinator.coordinate(
      readingItemAt: sourceURL,
      options: .withoutChanges,
      error: &coordinationError
    ) { coordinatedURL in
      do {
        try generateTile(
          from: coordinatedURL,
          document: document,
          tile: tile,
          outputURL: outputURL
        )
      } catch {
        generationError = error
      }
    }
    if let coordinationError {
      throw coordinationError
    }
    if let generationError {
      throw generationError
    }
  }

  func importImages(
    from urls: [URL],
    completion: @escaping (Result<ImageImportSummary, Error>) -> Void
  ) {
    importQueue.async { [weak self] in
      guard let self else { return }

      var imported: [ImageDocument] = []
      var failed: [String] = []

      for url in urls {
        autoreleasepool {
          do {
            imported.append(
              try self.copyStandaloneDocument(from: url)
            )
          } catch {
            failed.append(url.lastPathComponent)
          }
        }
      }

      DispatchQueue.main.async {
        guard !imported.isEmpty else {
          completion(.failure(ImageLibraryError.noImagesImported))
          return
        }

        self.documents.append(contentsOf: imported)
        do {
          try self.saveManifest()
          completion(
            .success(
              ImageImportSummary(
                importedDocuments: imported,
                failedFilenames: failed
              )
            )
          )
        } catch {
          let importedIDs = Set(imported.map(\.id))
          self.documents.removeAll { importedIDs.contains($0.id) }
          self.importQueue.async {
            self.removeDirectories(for: imported)
          }
          completion(.failure(error))
        }
      }
    }
  }

  func addFolder(
    from url: URL,
    completion: @escaping (Result<FolderSyncSummary, Error>) -> Void
  ) {
    addFolders(from: [url], completion: completion)
  }

  func addFolders(
    from urls: [URL],
    completion: @escaping (Result<FolderSyncSummary, Error>) -> Void
  ) {
    guard !urls.isEmpty else {
      completion(.failure(ImageLibraryError.noFolders))
      return
    }

    let currentFolders = folders

    importQueue.async { [weak self] in
      guard let self else { return }

      do {
        var nextFolders = currentFolders

        for url in urls {
          let hasAccess = url.startAccessingSecurityScopedResource()
          defer {
            if hasAccess {
              url.stopAccessingSecurityScopedResource()
            }
          }

          let bookmarkData = try url.bookmarkData(
            options: self.bookmarkCreationOptions,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
          )
          let pathHint = url.standardizedFileURL.path

          if let index = nextFolders.firstIndex(
            where: { $0.pathHint == pathHint }
          ) {
            let existing = nextFolders[index]
            nextFolders[index] = ImageFolder(
              id: existing.id,
              displayName: url.lastPathComponent,
              bookmarkData: bookmarkData,
              addedAt: existing.addedAt,
              pathHint: pathHint
            )
          } else {
            nextFolders.append(
              ImageFolder(
                id: UUID(),
                displayName: url.lastPathComponent,
                bookmarkData: bookmarkData,
                addedAt: Date(),
                pathHint: pathHint
              )
            )
          }
        }

        try self.saveFolders(nextFolders)
        DispatchQueue.main.async {
          self.folders = nextFolders
          self.syncFolders(completion: completion)
        }
      } catch {
        DispatchQueue.main.async {
          completion(.failure(error))
        }
      }
    }
  }

  func syncFolders(
    completion: @escaping (Result<FolderSyncSummary, Error>) -> Void
  ) {
    let currentFolders = folders
    let currentDocuments = documents

    guard !currentFolders.isEmpty else {
      completion(.failure(ImageLibraryError.noFolders))
      return
    }

    importQueue.async { [weak self] in
      guard let self else { return }

      var nextDocuments = currentDocuments
      var generatedDocuments: [ImageDocument] = []
      var obsoleteDocuments: [ImageDocument] = []
      var failedFilenames: [String] = []
      var unavailableFolders: [String] = []
      var addedCount = 0
      var updatedCount = 0
      var removedCount = 0

      for folder in currentFolders {
        autoreleasepool {
          guard let folderURL = self.resolveFolder(folder) else {
            unavailableFolders.append(folder.displayName)
            return
          }

          let hasAccess = folderURL.startAccessingSecurityScopedResource()
          defer {
            if hasAccess {
              folderURL.stopAccessingSecurityScopedResource()
            }
          }

          let scannedFiles: [FolderFile]
          do {
            scannedFiles = try self.imageFiles(in: folderURL)
          } catch {
            unavailableFolders.append(folder.displayName)
            return
          }

          let existingDocuments = currentDocuments.filter {
            $0.sourceFolderID == folder.id
          }
          let existingByPath = Dictionary(
            uniqueKeysWithValues: existingDocuments.compactMap { document in
              document.sourceRelativePath.map { ($0, document) }
            }
          )
          let scannedPaths = Set(scannedFiles.map(\.relativePath))

          for file in scannedFiles {
            let existing = existingByPath[file.relativePath]
            if let existing,
              existing.sourceModificationDate == file.modificationDate,
              existing.sourceFileSize == file.fileSize
            {
              continue
            }

            do {
              let document = try self.makeCoordinatedMetadataDocument(
                from: file.url,
                sourceFolderID: folder.id,
                sourceRelativePath: file.relativePath,
                sourceModificationDate: file.modificationDate,
                sourceFileSize: file.fileSize
              )
              generatedDocuments.append(document)
              nextDocuments.removeAll {
                $0.sourceFolderID == folder.id
                  && $0.sourceRelativePath == file.relativePath
              }
              nextDocuments.append(document)

              if let existing {
                obsoleteDocuments.append(existing)
                updatedCount += 1
              } else {
                addedCount += 1
              }
            } catch {
              failedFilenames.append(file.url.lastPathComponent)
            }
          }

          let removedDocuments = existingDocuments.filter { document in
            guard let relativePath = document.sourceRelativePath else {
              return true
            }
            return !scannedPaths.contains(relativePath)
          }
          if !removedDocuments.isEmpty {
            let removedIDs = Set(removedDocuments.map(\.id))
            nextDocuments.removeAll { removedIDs.contains($0.id) }
            obsoleteDocuments.append(contentsOf: removedDocuments)
            removedCount += removedDocuments.count
          }
        }
      }

      do {
        try self.saveManifest(nextDocuments)
        self.removeDirectories(for: obsoleteDocuments)
        DispatchQueue.main.async {
          self.documents = nextDocuments
          completion(
            .success(
              FolderSyncSummary(
                addedCount: addedCount,
                updatedCount: updatedCount,
                removedCount: removedCount,
                failedFilenames: failedFilenames,
                unavailableFolders: unavailableFolders
              )
            )
          )
        }
      } catch {
        self.removeDirectories(for: generatedDocuments)
        DispatchQueue.main.async {
          completion(.failure(error))
        }
      }
    }
  }

  func deleteAll(completion: @escaping (Result<Void, Error>) -> Void) {
    let oldDocuments = documents
    let oldFolders = folders
    documents = []
    folders = []

    do {
      try saveManifest()
      try saveFolders([])
    } catch {
      documents = oldDocuments
      folders = oldFolders
      completion(.failure(error))
      return
    }

    importQueue.async { [weak self] in
      guard let self else { return }
      self.removeDirectories(for: oldDocuments)
      DispatchQueue.main.async {
        completion(.success(()))
      }
    }
  }

  func removeCollection(
    folderID: UUID?,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    let removedDocuments = documents.filter {
      $0.sourceFolderID == folderID
    }
    let previousDocuments = documents
    let previousFolders = folders
    let nextDocuments = documents.filter {
      $0.sourceFolderID != folderID
    }
    let nextFolders: [ImageFolder]
    if let folderID {
      nextFolders = folders.filter { $0.id != folderID }
    } else {
      nextFolders = folders
    }

    do {
      try saveManifest(nextDocuments)
      try saveFolders(nextFolders)
    } catch {
      try? saveManifest(previousDocuments)
      try? saveFolders(previousFolders)
      completion(.failure(error))
      return
    }

    documents = nextDocuments
    folders = nextFolders
    importQueue.async { [weak self] in
      guard let self else { return }
      self.removeDirectories(for: removedDocuments)
      DispatchQueue.main.async {
        completion(.success(()))
      }
    }
  }

  private func copyStandaloneDocument(
    from url: URL
  ) throws -> ImageDocument {
    let hasAccess = url.startAccessingSecurityScopedResource()
    defer {
      if hasAccess {
        url.stopAccessingSecurityScopedResource()
      }
    }

    let sourceID = UUID()
    let relativePath = "\(sourceID.uuidString)/\(url.lastPathComponent)"
    let sourceDirectory = sourceStorageURL.appendingPathComponent(
      sourceID.uuidString,
      isDirectory: true
    )
    let copiedURL = sourceStorageURL.appendingPathComponent(
      relativePath
    )
    try fileManager.createDirectory(
      at: sourceDirectory,
      withIntermediateDirectories: true
    )

    do {
      let values = try url.resourceValues(
        forKeys: [
          .creationDateKey,
          .contentModificationDateKey,
          .fileSizeKey,
        ]
      )
      try fileManager.copyItem(at: url, to: copiedURL)
      let creationDate =
        values.creationDate
        ?? values.contentModificationDate
        ?? Date()
      let modificationDate =
        values.contentModificationDate
        ?? creationDate
      try? fileManager.setAttributes(
        [
          .creationDate: creationDate,
          .modificationDate: modificationDate,
        ],
        ofItemAtPath: copiedURL.path
      )
      return try makeMetadataDocument(
        from: copiedURL,
        sourceFolderID: nil,
        sourceRelativePath: relativePath,
        sourceModificationDate: modificationDate,
        sourceFileSize: Int64(values.fileSize ?? 0)
      )
    } catch {
      try? fileManager.removeItem(at: sourceDirectory)
      throw error
    }
  }

  private func makeCoordinatedMetadataDocument(
    from url: URL,
    sourceFolderID: UUID,
    sourceRelativePath: String,
    sourceModificationDate: Date,
    sourceFileSize: Int64
  ) throws -> ImageDocument {
    let values = try? url.resourceValues(
      forKeys: [
        .isUbiquitousItemKey,
        .ubiquitousItemDownloadingStatusKey,
      ]
    )
    if values?.isUbiquitousItem == true,
      values?.ubiquitousItemDownloadingStatus != .current
    {
      try? fileManager.startDownloadingUbiquitousItem(at: url)
    }

    var coordinationError: NSError?
    var result: Result<ImageDocument, Error>?
    let coordinator = NSFileCoordinator(filePresenter: nil)
    coordinator.coordinate(
      readingItemAt: url,
      options: .withoutChanges,
      error: &coordinationError
    ) { coordinatedURL in
      result = Result {
        try makeMetadataDocument(
          from: coordinatedURL,
          sourceFolderID: sourceFolderID,
          sourceRelativePath: sourceRelativePath,
          sourceModificationDate: sourceModificationDate,
          sourceFileSize: sourceFileSize
        )
      }
    }

    if let coordinationError {
      throw coordinationError
    }
    guard let result else {
      throw ImageLibraryError.invalidImage(url.lastPathComponent)
    }
    return try result.get()
  }

  private func makeMetadataDocument(
    from url: URL,
    sourceFolderID: UUID?,
    sourceRelativePath: String,
    sourceModificationDate: Date,
    sourceFileSize: Int64
  ) throws -> ImageDocument {
    guard
      let source = CGImageSourceCreateWithURL(
        url as CFURL,
        [kCGImageSourceShouldCache: false] as CFDictionary
      ),
      let properties = CGImageSourceCopyPropertiesAtIndex(
        source,
        0,
        nil
      ) as? [CFString: Any],
      let rawWidth = properties[kCGImagePropertyPixelWidth] as? NSNumber,
      let rawHeight = properties[kCGImagePropertyPixelHeight] as? NSNumber
    else {
      throw ImageLibraryError.invalidImage(url.lastPathComponent)
    }

    let orientation =
      (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue
      ?? 1
    let swapsDimensions = (5...8).contains(orientation)
    let displayWidth =
      swapsDimensions
      ? rawHeight.intValue
      : rawWidth.intValue
    let displayHeight =
      swapsDimensions
      ? rawWidth.intValue
      : rawHeight.intValue
    guard displayWidth > 0, displayHeight > 0 else {
      throw ImageLibraryError.invalidImage(url.lastPathComponent)
    }

    let outputWidth = min(displayWidth, Constants.targetPixelWidth)
    let outputHeight = max(
      1,
      Int(
        (Double(displayHeight) * Double(outputWidth)
          / Double(displayWidth)).rounded()
      )
    )
    let documentID = UUID()
    let tileCount = Int(
      ceil(Double(outputHeight) / Double(Constants.tilePixelHeight))
    )
    let tiles = (0..<tileCount).map { index in
      let tileOriginY = index * Constants.tilePixelHeight
      let tileHeight = min(
        Constants.tilePixelHeight,
        outputHeight - tileOriginY
      )
      let filename = String(format: "tile_%05d.png", index)
      return ImageTile(
        relativePath: "\(documentID.uuidString)/\(filename)",
        pixelWidth: outputWidth,
        pixelHeight: tileHeight
      )
    }
    let values = try? url.resourceValues(
      forKeys: [.creationDateKey]
    )

    return ImageDocument(
      id: documentID,
      filename: url.lastPathComponent,
      creationDate: values?.creationDate ?? sourceModificationDate,
      importedAt: Date(),
      pixelWidth: outputWidth,
      pixelHeight: outputHeight,
      tiles: tiles,
      sourceFolderID: sourceFolderID,
      sourceRelativePath: sourceRelativePath,
      sourceModificationDate: sourceModificationDate,
      sourceFileSize: sourceFileSize
    )
  }

  private func generateTile(
    from sourceURL: URL,
    document: ImageDocument,
    tile: ImageTile,
    outputURL: URL
  ) throws {
    guard
      let tileIndex = document.tiles.firstIndex(of: tile),
      let sourceImage = CIImage(
        contentsOf: sourceURL,
        options: [
          .applyOrientationProperty: true,
          .cacheImmediately: false,
        ]
      )
    else {
      throw ImageLibraryError.invalidImage(document.filename)
    }

    let sourceExtent = sourceImage.extent.integral
    let normalizedImage = sourceImage.transformed(
      by: CGAffineTransform(
        translationX: -sourceExtent.minX,
        y: -sourceExtent.minY
      )
    )
    let scale =
      CGFloat(document.pixelWidth)
      / normalizedImage.extent.width
    let scaledImage = normalizedImage.transformed(
      by: CGAffineTransform(scaleX: scale, y: scale)
    )
    let tileOriginY = tileIndex * Constants.tilePixelHeight
    let cropRect = CGRect(
      x: 0,
      y: CGFloat(
        document.pixelHeight - tileOriginY - tile.pixelHeight
      ),
      width: CGFloat(tile.pixelWidth),
      height: CGFloat(tile.pixelHeight)
    )
    guard
      let cgImage = ciContext.createCGImage(
        scaledImage,
        from: cropRect,
        format: .RGBA8,
        colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
      )
    else {
      throw ImageLibraryError.tileEncodingFailed(document.filename)
    }

    let directory = outputURL.deletingLastPathComponent()
    try fileManager.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    guard !fileManager.fileExists(atPath: outputURL.path) else {
      return
    }

    let temporaryURL = directory.appendingPathComponent(
      "\(UUID().uuidString).tmp"
    )
    defer {
      try? fileManager.removeItem(at: temporaryURL)
      ciContext.clearCaches()
    }
    guard
      let destination = CGImageDestinationCreateWithURL(
        temporaryURL as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
      )
    else {
      throw ImageLibraryError.tileEncodingFailed(document.filename)
    }
    CGImageDestinationAddImage(destination, cgImage, nil)
    guard CGImageDestinationFinalize(destination) else {
      throw ImageLibraryError.tileEncodingFailed(document.filename)
    }
    try fileManager.moveItem(at: temporaryURL, to: outputURL)
  }

  private func imageFiles(in folderURL: URL) throws -> [FolderFile] {
    let resourceKeys: Set<URLResourceKey> = [
      .isRegularFileKey,
      .contentTypeKey,
      .creationDateKey,
      .contentModificationDateKey,
      .fileSizeKey,
      .isUbiquitousItemKey,
      .ubiquitousItemDownloadingStatusKey,
    ]
    guard
      let enumerator = fileManager.enumerator(
        at: folderURL,
        includingPropertiesForKeys: Array(resourceKeys),
        options: [.skipsHiddenFiles, .skipsPackageDescendants]
      )
    else {
      throw ImageLibraryError.folderAccessFailed(
        folderURL.lastPathComponent
      )
    }

    var files: [FolderFile] = []
    for case let fileURL as URL in enumerator {
      let values = try fileURL.resourceValues(forKeys: resourceKeys)
      guard values.isRegularFile == true else { continue }

      let isImage =
        values.contentType?.conforms(to: .image) == true
        || UTType(filenameExtension: fileURL.pathExtension)?
          .conforms(to: .image) == true
      guard isImage else { continue }

      let modificationDate =
        values.contentModificationDate
        ?? values.creationDate
        ?? .distantPast
      let fileSize = Int64(values.fileSize ?? 0)
      let relativePath = relativePath(
        for: fileURL,
        inside: folderURL
      )
      files.append(
        FolderFile(
          url: fileURL,
          relativePath: relativePath,
          modificationDate: modificationDate,
          fileSize: fileSize
        )
      )
    }
    return files
  }

  private func relativePath(
    for fileURL: URL,
    inside folderURL: URL
  ) -> String {
    let folderComponents = folderURL.standardizedFileURL.pathComponents
    let fileComponents = fileURL.standardizedFileURL.pathComponents
    guard fileComponents.starts(with: folderComponents) else {
      return fileURL.lastPathComponent
    }
    return fileComponents.dropFirst(folderComponents.count)
      .joined(separator: "/")
  }

  private func resolveFolder(_ folder: ImageFolder) -> URL? {
    var isStale = false
    guard
      let url = try? URL(
        resolvingBookmarkData: folder.bookmarkData,
        options: bookmarkResolutionOptions,
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      )
    else {
      return nil
    }

    return url
  }

  private var bookmarkCreationOptions: URL.BookmarkCreationOptions {
    #if targetEnvironment(macCatalyst)
      return [.withSecurityScope]
    #else
      return [.minimalBookmark]
    #endif
  }

  private var bookmarkResolutionOptions: URL.BookmarkResolutionOptions {
    #if targetEnvironment(macCatalyst)
      return [.withSecurityScope, .withoutUI]
    #else
      return [.withoutUI]
    #endif
  }

  private struct FolderFile {
    let url: URL
    let relativePath: String
    let modificationDate: Date
    let fileSize: Int64
  }

  private func saveManifest() throws {
    try saveManifest(documents)
  }

  private func saveManifest(_ documents: [ImageDocument]) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(documents)
    try data.write(to: manifestURL, options: .atomic)
  }

  private func saveFolders(_ folders: [ImageFolder]) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(folders)
    try data.write(to: folderManifestURL, options: .atomic)
  }

  private func removeDirectories(for documents: [ImageDocument]) {
    for document in documents {
      let directory = storageURL.appendingPathComponent(
        document.id.uuidString,
        isDirectory: true
      )
      try? fileManager.removeItem(at: directory)

      if document.sourceFolderID == nil,
        let relativePath = document.sourceRelativePath,
        let sourceDirectoryName = relativePath.split(
          separator: "/"
        ).first
      {
        let sourceDirectory = sourceStorageURL.appendingPathComponent(
          String(sourceDirectoryName),
          isDirectory: true
        )
        try? fileManager.removeItem(at: sourceDirectory)
      }
    }
  }
}
