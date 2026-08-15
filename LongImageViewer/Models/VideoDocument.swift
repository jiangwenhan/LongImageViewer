import Foundation

struct VideoDocument: Codable, Hashable {
  let id: UUID
  let sourceFolderID: UUID
  let relativePath: String
  let filename: String
  let directoryRelativePath: String?
  let modificationDate: Date
  let fileSize: Int64
}

struct VideoFolder: Codable, Hashable {
  let id: UUID
  let displayName: String
  let bookmarkData: Data
  let addedAt: Date
  let pathHint: String?
  var hiddenRelativePaths: [String]

  init(
    id: UUID,
    displayName: String,
    bookmarkData: Data,
    addedAt: Date,
    pathHint: String?,
    hiddenRelativePaths: [String] = []
  ) {
    self.id = id
    self.displayName = displayName
    self.bookmarkData = bookmarkData
    self.addedAt = addedAt
    self.pathHint = pathHint
    self.hiddenRelativePaths = hiddenRelativePaths
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case displayName
    case bookmarkData
    case addedAt
    case pathHint
    case hiddenRelativePaths
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    displayName = try container.decode(String.self, forKey: .displayName)
    bookmarkData = try container.decode(Data.self, forKey: .bookmarkData)
    addedAt = try container.decode(Date.self, forKey: .addedAt)
    pathHint = try container.decodeIfPresent(
      String.self,
      forKey: .pathHint
    )
    hiddenRelativePaths =
      try container.decodeIfPresent(
        [String].self,
        forKey: .hiddenRelativePaths
      ) ?? []
  }
}

struct VideoSyncSummary {
  let addedCount: Int
  let updatedCount: Int
  let removedCount: Int
  let unavailableFolders: [String]
}
