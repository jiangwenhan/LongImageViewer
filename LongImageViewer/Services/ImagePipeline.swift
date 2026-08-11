import ImageIO
import UIKit

final class ImageRequestToken {
  private let lock = NSLock()
  private var cancelled = false

  var isCancelled: Bool {
    lock.lock()
    defer { lock.unlock() }
    return cancelled
  }

  func cancel() {
    lock.lock()
    cancelled = true
    lock.unlock()
  }
}

final class ImagePipeline {
  static let shared = ImagePipeline()

  private struct PendingCallback {
    let token: ImageRequestToken
    let completion: (UIImage?) -> Void
  }

  private let cache = NSCache<NSString, UIImage>()
  private let pendingLock = NSLock()
  private var pendingCallbacks: [String: [PendingCallback]] = [:]
  private var lastPressureTrim = Date.distantPast
  private let decodeQueue: OperationQueue = {
    let queue = OperationQueue()
    queue.name = "com.trae.LongImageViewer.decode"
    queue.qualityOfService = .userInitiated
    queue.maxConcurrentOperationCount = 2
    return queue
  }()

  private init() {
    let physicalMemory = ProcessInfo.processInfo.physicalMemory
    let dynamicLimit = physicalMemory / 128
    let minimumLimit = UInt64(32 * 1_024 * 1_024)
    let maximumLimit = UInt64(64 * 1_024 * 1_024)
    cache.totalCostLimit = Int(
      min(max(dynamicLimit, minimumLimit), maximumLimit)
    )
    cache.countLimit = 8

    NotificationCenter.default.addObserver(
      forName: UIApplication.didReceiveMemoryWarningNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.clearCache()
    }
    NotificationCenter.default.addObserver(
      forName: UIApplication.didEnterBackgroundNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.clearCache()
    }
  }

  @discardableResult
  func loadImage(
    at url: URL,
    cacheKey: String,
    prepare: (() throws -> Void)? = nil,
    completion: @escaping (UIImage?) -> Void
  ) -> ImageRequestToken? {
    let key = cacheKey as NSString
    if let cachedImage = cache.object(forKey: key) {
      completion(cachedImage)
      return nil
    }

    let token = ImageRequestToken()
    let callback = PendingCallback(
      token: token,
      completion: completion
    )

    pendingLock.lock()
    if pendingCallbacks[cacheKey] != nil {
      pendingCallbacks[cacheKey, default: []].append(callback)
      pendingLock.unlock()
      return token
    }
    pendingCallbacks[cacheKey] = [callback]
    pendingLock.unlock()

    decodeQueue.addOperation { [weak self] in
      guard let self else { return }
      self.pendingLock.lock()
      let shouldProceed =
        self.pendingCallbacks[cacheKey]?.contains {
          !$0.token.isCancelled
        } == true
      if !shouldProceed {
        self.pendingCallbacks.removeValue(forKey: cacheKey)
      }
      self.pendingLock.unlock()
      guard shouldProceed else { return }

      if !FileManager.default.fileExists(atPath: url.path) {
        try? prepare?()
      }
      let image = Self.decodeImage(at: url)
      if let image {
        let cost = Int(
          image.size.width
            * image.size.height
            * image.scale
            * image.scale
            * 4
        )
        self.cache.setObject(image, forKey: key, cost: cost)
      }

      self.pendingLock.lock()
      let callbacks =
        self.pendingCallbacks.removeValue(
          forKey: cacheKey
        ) ?? []
      self.pendingLock.unlock()

      DispatchQueue.main.async {
        for callback in callbacks where !callback.token.isCancelled {
          callback.completion(image)
        }
      }
    }
    return token
  }

  func prefetch(
    at url: URL,
    cacheKey: String,
    prepare: (() throws -> Void)? = nil
  ) -> ImageRequestToken? {
    guard cache.object(forKey: cacheKey as NSString) == nil else {
      return nil
    }
    return loadImage(
      at: url,
      cacheKey: cacheKey,
      prepare: prepare
    ) { _ in }
  }

  func clearCache() {
    cache.removeAllObjects()
  }

  func trimIfNeeded(usedBytes: UInt64) {
    let physicalMemory = ProcessInfo.processInfo.physicalMemory
    let proportionalLimit = physicalMemory / 24
    let minimumLimit = UInt64(192 * 1_024 * 1_024)
    let maximumLimit = UInt64(320 * 1_024 * 1_024)
    let pressureLimit = min(
      max(proportionalLimit, minimumLimit),
      maximumLimit
    )

    guard
      usedBytes > pressureLimit,
      Date().timeIntervalSince(lastPressureTrim) > 10
    else {
      return
    }
    lastPressureTrim = Date()
    clearCache()
  }

  private static func decodeImage(at url: URL) -> UIImage? {
    guard
      let source = CGImageSourceCreateWithURL(
        url as CFURL,
        [kCGImageSourceShouldCache: false] as CFDictionary
      )
    else {
      return nil
    }

    let options =
      [
        kCGImageSourceShouldCache: true,
        kCGImageSourceShouldCacheImmediately: true,
      ] as CFDictionary
    guard
      let image = CGImageSourceCreateImageAtIndex(
        source,
        0,
        options
      )
    else {
      return nil
    }
    return UIImage(cgImage: image)
  }
}
