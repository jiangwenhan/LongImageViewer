import Foundation

struct ImageTile: Codable, Hashable {
  let relativePath: String
  let pixelWidth: Int
  let pixelHeight: Int
}

struct ImageDocument: Codable, Hashable {
  let id: UUID
  let filename: String
  let creationDate: Date
  let importedAt: Date
  let pixelWidth: Int
  let pixelHeight: Int
  let tiles: [ImageTile]
  let sourceFolderID: UUID?
  let sourceRelativePath: String?
  let sourceDirectoryRelativePath: String?
  let sourceModificationDate: Date?
  let sourceFileSize: Int64?

  init(
    id: UUID,
    filename: String,
    creationDate: Date,
    importedAt: Date,
    pixelWidth: Int,
    pixelHeight: Int,
    tiles: [ImageTile],
    sourceFolderID: UUID? = nil,
    sourceRelativePath: String? = nil,
    sourceDirectoryRelativePath: String? = nil,
    sourceModificationDate: Date? = nil,
    sourceFileSize: Int64? = nil
  ) {
    self.id = id
    self.filename = filename
    self.creationDate = creationDate
    self.importedAt = importedAt
    self.pixelWidth = pixelWidth
    self.pixelHeight = pixelHeight
    self.tiles = tiles
    self.sourceFolderID = sourceFolderID
    self.sourceRelativePath = sourceRelativePath
    self.sourceDirectoryRelativePath = sourceDirectoryRelativePath
    self.sourceModificationDate = sourceModificationDate
    self.sourceFileSize = sourceFileSize
  }

  var directoryRelativePath: String? {
    if let sourceDirectoryRelativePath {
      return sourceDirectoryRelativePath
    }
    guard
      sourceFolderID != nil,
      let sourceRelativePath
    else {
      return nil
    }
    let components = sourceRelativePath.split(separator: "/")
    guard components.count > 1 else { return nil }
    return components.dropLast().joined(separator: "/")
  }
}

struct ImageFolder: Codable, Hashable {
  let id: UUID
  let displayName: String
  let bookmarkData: Data
  let addedAt: Date
  let pathHint: String?
  let childDirectoryNames: [String]?

  init(
    id: UUID,
    displayName: String,
    bookmarkData: Data,
    addedAt: Date,
    pathHint: String?,
    childDirectoryNames: [String]? = nil
  ) {
    self.id = id
    self.displayName = displayName
    self.bookmarkData = bookmarkData
    self.addedAt = addedAt
    self.pathHint = pathHint
    self.childDirectoryNames = childDirectoryNames
  }

  var directChildDirectoryNames: [String] {
    childDirectoryNames ?? []
  }
}

struct ImageDirectorySummary: Hashable {
  let folderID: UUID
  let relativePath: String?
  let displayName: String
  let imageCount: Int
}

enum ImageSortOption: String, CaseIterable {
  case creationAscending
  case creationDescending
  case filenameAscending
  case filenameDescending

  var title: String {
    switch self {
    case .creationAscending:
      return L("sort.creation_ascending")
    case .creationDescending:
      return L("sort.creation_descending")
    case .filenameAscending:
      return L("sort.filename_ascending")
    case .filenameDescending:
      return L("sort.filename_descending")
    }
  }

  var systemImageName: String {
    switch self {
    case .creationAscending:
      return "calendar.badge.clock"
    case .creationDescending:
      return "calendar.badge.clock"
    case .filenameAscending:
      return "textformat.abc"
    case .filenameDescending:
      return "textformat.abc"
    }
  }

  func sort(_ documents: [ImageDocument]) -> [ImageDocument] {
    documents.sorted { lhs, rhs in
      switch self {
      case .creationAscending:
        return compareDates(lhs, rhs, ascending: true)
      case .creationDescending:
        return compareDates(lhs, rhs, ascending: false)
      case .filenameAscending:
        return compareNames(lhs, rhs, ascending: true)
      case .filenameDescending:
        return compareNames(lhs, rhs, ascending: false)
      }
    }
  }

  private func compareDates(
    _ lhs: ImageDocument,
    _ rhs: ImageDocument,
    ascending: Bool
  ) -> Bool {
    if lhs.creationDate == rhs.creationDate {
      return compareNames(lhs, rhs, ascending: true)
    }
    return ascending
      ? lhs.creationDate < rhs.creationDate
      : lhs.creationDate > rhs.creationDate
  }

  private func compareNames(
    _ lhs: ImageDocument,
    _ rhs: ImageDocument,
    ascending: Bool
  ) -> Bool {
    let comparison = lhs.filename.localizedStandardCompare(rhs.filename)
    if comparison == .orderedSame {
      return lhs.importedAt < rhs.importedAt
    }
    return ascending
      ? comparison == .orderedAscending
      : comparison == .orderedDescending
  }
}

struct DisplayTile: Hashable {
  let document: ImageDocument
  let tile: ImageTile
  let pageIndex: Int
  let showsPageSeparator: Bool

  var id: String {
    "\(document.id.uuidString)/\(tile.relativePath)"
  }
}
