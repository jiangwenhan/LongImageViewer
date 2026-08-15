import AVFoundation
import AVKit
import UIKit

final class VideoPlayerViewController: AVPlayerViewController {
  private var playbackAccess: VideoPlaybackAccess?
  private var statusObservation: NSKeyValueObservation?
  private var didShowPlaybackError = false

  init(
    playbackAccess: VideoPlaybackAccess,
    title: String
  ) {
    self.playbackAccess = playbackAccess
    super.init(nibName: nil, bundle: nil)

    self.title = title
    modalPresentationStyle = .fullScreen
    allowsPictureInPicturePlayback = false
    canStartPictureInPictureAutomaticallyFromInline = false
    updatesNowPlayingInfoCenter = false

    let item = AVPlayerItem(url: playbackAccess.url)
    player = AVPlayer(playerItem: item)
    statusObservation = item.observe(
      \.status,
      options: [.initial, .new]
    ) { [weak self] item, _ in
      guard item.status == .failed else { return }
      DispatchQueue.main.async {
        self?.showPlaybackError(item.error)
      }
    }

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(pauseForAppTransition),
      name: UIApplication.willResignActiveNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(pauseForAppTransition),
      name: UIApplication.didEnterBackgroundNotification,
      object: nil
    )
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
    statusObservation?.invalidate()
    player?.pause()
    playbackAccess?.releaseAccess()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    guard UIApplication.shared.applicationState == .active else {
      return
    }
    player?.play()
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    player?.pause()
    if isBeingDismissed || presentingViewController == nil {
      playbackAccess?.releaseAccess()
      playbackAccess = nil
    }
  }

  @objc private func pauseForAppTransition() {
    player?.pause()
  }

  private func showPlaybackError(_ error: Error?) {
    guard !didShowPlaybackError, presentedViewController == nil else {
      return
    }
    didShowPlaybackError = true
    player?.pause()

    let detail = error?.localizedDescription ?? L(
      "video.playback_unsupported"
    )
    let alert = UIAlertController(
      title: L("video.playback_failed"),
      message: detail,
      preferredStyle: .alert
    )
    alert.addAction(
      UIAlertAction(title: L("common.ok"), style: .default)
    )
    present(alert, animated: true)
  }
}
