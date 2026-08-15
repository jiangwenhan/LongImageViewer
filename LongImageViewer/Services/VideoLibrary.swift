import Foundation
import UniformTypeIdentifiers

enum VideoLibraryError: LocalizedError {
  case noFolders
  case folderAccessFailed(String)
  case videoUnavailable(String)

  var errorDescription: String? {
    switch self {
    case .noFolders:
      return L("video.error.no_folders")
    case .folderAccessFailed(let folderName):
      return L("video.error.folder_access_format", folderName)
    case .videoUnavailable(let filename):
      return L("video.error.unavailable_format", filename)
    }
  }
}

final class VideoPlaybackAccess {
  let url: URL

  private let accessRootURL: URL
  private let startedSecurityScope: Bool
  private var isReleased = false

  init(
    url: URL,
    accessRootURL: URL,
    startedSecurityScope: Bool
  ) {
    self.url = url
    self.accessRootURL = accessRootURL
    self.startedSecurityScope = startedSecurityScope
  }

  func releaseAccess() {
    guard !isReleased else { return }
    isReleased = true
    if startedSecurityScope {
      accessRootURL.stopAccessingSecurityScopedResource()
    }
  }

  deinit {
    releaseAccess()
  }
}

final class VideoLibrary {
  static let shared = VideoLibrary()

  private enum Constants {
    static let folderManifestFilename = "video-folders.json"
    static let videoManifestFilename = "videos.json"
    static let supportedExtensions: Set<String> = [
      "3g2", "3gp", "m2ts", "m3u8", "m4v", "mov", "mp4", "mpeg",
      "mpg", "mts", "ts",
    ]
  }

  private let fileManager = FileManager.default
  private let scanQueue = DispatchQueue(
    label: "com.trae.LongImageViewer.video-scan",
    qos: .userInitiated
  )
  private let folderManifestURL: URL
  private let videoManifestURL: URL

  private(set) var folders: [VideoFolder]
  private(set) var videos: [VideoDocument]

  var folderDisplayNames: [String] {
    folders.map(\.displayName)
  }

  var hasHiddenItems: Bool {
    folders.contains { !$0.hiddenRelativePaths.isEmpty }
  }

  private init() {
    let applicationSupport = fileManager.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    )[0].appendingPathComponent(
      "LongImageViewer",
      isDirectory: true
    )
    try? fileManager.createDirectory(
      at: applicationSupport,
      withIntermediateDirectories: true
    )
    folderManifestURL = applicationSupport.appendingPathComponent(
      Constants.folderManifestFilename
    )
    videoManifestURL = applicationSupport.appendingPathComponent(
      Constants.videoManifestFilename
    )

    if
      let data = try? Data(contentsOf: folderManifestURL),
      let decoded = try? JSONDecoder().decode(
        [VideoFolder].self,
        from: data
      )
    {
      folders = decoded
    } else {
      folders = []
    }

    if
      let data = try? Data(contentsOf: videoManifestURL),
      let decoded = try? JSONDecoder().decode(
        [VideoDocument].self,
        from: data
      )
    {
      videos = decoded
    } else {
      videos = []
    }
  }

  func videos(in folderID: UUID) -> [VideoDocument] {
    videos.filter { $0.sourceFolderID == folderID }.sorted {
      $0.relativePath.localizedStandardCompare($1.relativePath)
        == .orderedAscending
    }
  }

  func folderID(for url: URL) -> UUID? {
    let path = url.standardizedFileURL.path
    return folders.first { $0.pathHint == path }?.id
  }

  func addFolder(
    from url: URL,
    completion: @escaping (Result<VideoSyncSummary, Error>) -> Void
  ) {
    let currentFolders = folders
    scanQueue.async { [weak self] in
      guard let self else { return }

      let hasAccess = url.startAccessingSecurityScopedResource()
      defer {
        if hasAccess {
          url.stopAccessingSecurityScopedResource()
        }
      }

      do {
        let bookmarkData = try url.bookmarkData(
          options: self.bookmarkCreationOptions,
          includingResourceValuesForKeys: nil,
          relativeTo: nil
        )
        let pathHint = url.standardizedFileURL.path
        var nextFolders = currentFolders
        if let index = nextFolders.firstIndex(
          where: { $0.pathHint == pathHint }
        ) {
          let existing = nextFolders[index]
          nextFolders[index] = VideoFolder(
            id: existing.id,
            displayName: url.lastPathComponent,
            bookmarkData: bookmarkData,
            addedAt: existing.addedAt,
            pathHint: pathHint,
            hiddenRelativePaths: []
          )
        } else {
          nextFolders.append(
            VideoFolder(
              id: UUID(),
              displayName: url.lastPathComponent,
              bookmarkData: bookmarkData,
              addedAt: Date(),
              pathHint: pathHint
            )
          )
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
    completion: @escaping (Result<VideoSyncSummary, Error>) -> Void
  ) {
    let currentFolders = folders
    let currentVideos = videos
    guard !currentFolders.isEmpty else {
      completion(.failure(VideoLibraryError.noFolders))
      return
    }

    scanQueue.async { [weak self] in
      guard let self else { return }

      var nextVideos = currentVideos
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
          let hasAccess =
            folderURL.startAccessingSecurityScopedResource()
          defer {
            if hasAccess {
              folderURL.stopAccessingSecurityScopedResource()
            }
          }

          let scannedFiles: [ScannedVideo]
          do {
            scannedFiles = try self.scanFolder(
              at: folderURL,
              hiddenRelativePaths: Set(folder.hiddenRelativePaths)
            )
          } catch {
            unavailableFolders.append(folder.displayName)
            return
          }

          let existingVideos = currentVideos.filter {
            $0.sourceFolderID == folder.id
          }
          let existingByPath = Dictionary(
            uniqueKeysWithValues: existingVideos.map {
              ($0.relativePath, $0)
            }
          )
          let scannedPaths = Set(scannedFiles.map(\.relativePath))

          for file in scannedFiles {
            if let existing = existingByPath[file.relativePath] {
              if
                existing.modificationDate == file.modificationDate,
                existing.fileSize == file.fileSize
              {
                continue
              }
              nextVideos.removeAll {
                $0.sourceFolderID == folder.id
                  && $0.relativePath == file.relativePath
              }
              nextVideos.append(
                VideoDocument(
                  id: existing.id,
                  sourceFolderID: folder.id,
                  relativePath: file.relativePath,
                  filename: file.filename,
                  directoryRelativePath:
                    file.directoryRelativePath,
                  modificationDate: file.modificationDate,
                  fileSize: file.fileSize
                )
              )
              updatedCount += 1
            } else {
              nextVideos.append(
                VideoDocument(
                  id: UUID(),
                  sourceFolderID: folder.id,
                  relativePath: file.relativePath,
                  filename: file.filename,
                  directoryRelativePath:
                    file.directoryRelativePath,
                  modificationDate: file.modificationDate,
                  fileSize: file.fileSize
                )
              )
              addedCount += 1
            }
          }

          let removed = existingVideos.filter {
            !scannedPaths.contains($0.relativePath)
          }
          if !removed.isEmpty {
            let removedIDs = Set(removed.map(\.id))
            nextVideos.removeAll { removedIDs.contains($0.id) }
            removedCount += removed.count
          }
        }
      }

      do {
        try self.saveVideos(nextVideos)
        DispatchQueue.main.async {
          self.videos = nextVideos
          completion(
            .success(
              VideoSyncSummary(
                addedCount: addedCount,
                updatedCount: updatedCount,
                removedCount: removedCount,
                unavailableFolders: unavailableFolders
              )
            )
          )
        }
      } catch {
        DispatchQueue.main.async {
          completion(.failure(error))
        }
      }
    }
  }

  func removeFolder(
    _ folderID: UUID,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    let nextFolders = folders.filter { $0.id != folderID }
    let nextVideos = videos.filter { $0.sourceFolderID != folderID }
    persist(
      folders: nextFolders,
      videos: nextVideos,
      completion: completion
    )
  }

  func hideItem(
    folderID: UUID,
    relativePath: String,
    isDirectory: Bool,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    let normalizedPath = normalize(relativePath)
    guard
      !normalizedPath.isEmpty,
      let folderIndex = folders.firstIndex(
        where: { $0.id == folderID }
      )
    else {
      completion(.failure(VideoLibraryError.noFolders))
      return
    }

    var nextFolders = folders
    var folder = nextFolders[folderIndex]
    if !folder.hiddenRelativePaths.contains(normalizedPath) {
      folder.hiddenRelativePaths.append(normalizedPath)
      folder.hiddenRelativePaths.sort()
    }
    nextFolders[folderIndex] = folder
    let nextVideos = videos.filter { video in
      guard video.sourceFolderID == folderID else { return true }
      if isDirectory {
        return !isPath(
          video.relativePath,
          insideDirectory: normalizedPath
        )
      }
      return video.relativePath != normalizedPath
    }
    persist(
      folders: nextFolders,
      videos: nextVideos,
      completion: completion
    )
  }

  func restoreHiddenItems(
    completion: @escaping (Result<VideoSyncSummary, Error>) -> Void
  ) {
    let previousFolders = folders
    let restoredFolders = folders.map { folder in
      VideoFolder(
        id: folder.id,
        displayName: folder.displayName,
        bookmarkData: folder.bookmarkData,
        addedAt: folder.addedAt,
        pathHint: folder.pathHint,
        hiddenRelativePaths: []
      )
    }
    do {
      try saveFolders(restoredFolders)
      folders = restoredFolders
      syncFolders { [weak self] result in
        if case .failure = result {
          try? self?.saveFolders(previousFolders)
          self?.folders = previousFolders
        }
        completion(result)
      }
    } catch {
      completion(.failure(error))
    }
  }

  func playbackAccess(
    for video: VideoDocument
  ) throws -> VideoPlaybackAccess {
    guard
      let folder = folders.first(
        where: { $0.id == video.sourceFolderID }
      ),
      let folderURL = resolveFolder(folder)
    else {
      throw VideoLibraryError.folderAccessFailed(video.filename)
    }

    let started = folderURL.startAccessingSecurityScopedResource()
    let videoURL = folderURL.appendingPathComponent(
      video.relativePath
    )
    guard fileManager.fileExists(atPath: videoURL.path) else {
      if started {
        folderURL.stopAccessingSecurityScopedResource()
      }
      throw VideoLibraryError.videoUnavailable(video.filename)
    }

    if
      let values = try? videoURL.resourceValues(
        forKeys: [
          .isUbiquitousItemKey,
          .ubiquitousItemDownloadingStatusKey,
        ]
      ),
      values.isUbiquitousItem == true,
      values.ubiquitousItemDownloadingStatus != .current
    {
      try? fileManager.startDownloadingUbiquitousItem(at: videoURL)
    }

    return VideoPlaybackAccess(
      url: videoURL,
      accessRootURL: folderURL,
      startedSecurityScope: started
    )
  }

  private func persist(
    folders nextFolders: [VideoFolder],
    videos nextVideos: [VideoDocument],
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    let previousFolders = folders
    let previousVideos = videos
    do {
      try saveFolders(nextFolders)
      try saveVideos(nextVideos)
      folders = nextFolders
      videos = nextVideos
      completion(.success(()))
    } catch {
      try? saveFolders(previousFolders)
      try? saveVideos(previousVideos)
      completion(.failure(error))
    }
  }

  private func scanFolder(
    at folderURL: URL,
    hiddenRelativePaths: Set<String>
  ) throws -> [ScannedVideo] {
    let resourceKeys: Set<URLResourceKey> = [
      .isDirectoryKey,
      .isPackageKey,
      .isRegularFileKey,
      .isSymbolicLinkKey,
      .contentTypeKey,
      .creationDateKey,
      .contentModificationDateKey,
      .fileSizeKey,
    ]
    guard
      let enumerator = fileManager.enumerator(
        at: folderURL,
        includingPropertiesForKeys: Array(resourceKeys),
        options: [
          .skipsHiddenFiles,
          .skipsPackageDescendants,
        ]
      )
    else {
      throw VideoLibraryError.folderAccessFailed(
        folderURL.lastPathComponent
      )
    }

    var files: [ScannedVideo] = []
    for case let itemURL as URL in enumerator {
      guard
        let values = try? itemURL.resourceValues(
          forKeys: resourceKeys
        ),
        values.isSymbolicLink != true
      else {
        continue
      }
      let relativePath = relativePath(
        for: itemURL,
        inside: folderURL
      )
      if isHidden(relativePath, by: hiddenRelativePaths) {
        if values.isDirectory == true {
          enumerator.skipDescendants()
        }
        continue
      }
      guard
        values.isRegularFile == true,
        isSupportedVideo(itemURL, contentType: values.contentType)
      else {
        continue
      }

      let pathComponents = relativePath.split(separator: "/")
      let directoryRelativePath =
        pathComponents.count > 1
        ? pathComponents.dropLast().joined(separator: "/")
        : nil
      files.append(
        ScannedVideo(
          relativePath: relativePath,
          filename: itemURL.lastPathComponent,
          directoryRelativePath: directoryRelativePath,
          modificationDate:
            values.contentModificationDate
            ?? values.creationDate
            ?? .distantPast,
          fileSize: Int64(values.fileSize ?? 0)
        )
      )
    }
    return files.sorted {
      $0.relativePath.localizedStandardCompare($1.relativePath)
        == .orderedAscending
    }
  }

  private func isSupportedVideo(
    _ url: URL,
    contentType: UTType?
  ) -> Bool {
    if contentType?.conforms(to: .movie) == true {
      return true
    }
    let fileExtension = url.pathExtension.lowercased()
    if Constants.supportedExtensions.contains(fileExtension) {
      return true
    }
    return UTType(filenameExtension: fileExtension)?
      .conforms(to: .movie) == true
  }

  private func isHidden(
    _ relativePath: String,
    by hiddenRelativePaths: Set<String>
  ) -> Bool {
    hiddenRelativePaths.contains { hiddenPath in
      relativePath == hiddenPath
        || relativePath.hasPrefix(hiddenPath + "/")
    }
  }

  private func isPath(
    _ path: String,
    insideDirectory directory: String
  ) -> Bool {
    path == directory || path.hasPrefix(directory + "/")
  }

  private func normalize(_ path: String) -> String {
    path.split(separator: "/").joined(separator: "/")
  }

  private func relativePath(
    for fileURL: URL,
    inside folderURL: URL
  ) -> String {
    let rootComponents = folderURL.standardizedFileURL.pathComponents
    let fileComponents = fileURL.standardizedFileURL.pathComponents
    guard fileComponents.starts(with: rootComponents) else {
      return fileURL.lastPathComponent
    }
    return fileComponents.dropFirst(rootComponents.count)
      .joined(separator: "/")
  }

  private func resolveFolder(_ folder: VideoFolder) -> URL? {
    var isStale = false
    return try? URL(
      resolvingBookmarkData: folder.bookmarkData,
      options: bookmarkResolutionOptions,
      relativeTo: nil,
      bookmarkDataIsStale: &isStale
    )
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

  private func saveFolders(_ folders: [VideoFolder]) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(folders).write(
      to: folderManifestURL,
      options: .atomic
    )
  }

  private func saveVideos(_ videos: [VideoDocument]) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(videos).write(
      to: videoManifestURL,
      options: .atomic
    )
  }

  private struct ScannedVideo {
    let relativePath: String
    let filename: String
    let directoryRelativePath: String?
    let modificationDate: Date
    let fileSize: Int64
  }
}
