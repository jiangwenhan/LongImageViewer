import UIKit

final class ImageTileCell: UICollectionViewCell {
  static let reuseIdentifier = "ImageTileCell"

  private let imageView = UIImageView()
  private let separatorView = UIView()
  private var imageRequest: ImageRequestToken?
  private var representedIdentifier: String?

  override init(frame: CGRect) {
    super.init(frame: frame)

    backgroundColor = .black
    clipsToBounds = true

    imageView.contentMode = .scaleToFill
    imageView.backgroundColor = .black
    imageView.translatesAutoresizingMaskIntoConstraints = false

    separatorView.backgroundColor = UIColor(
      white: 0.72,
      alpha: 0.88
    )
    separatorView.translatesAutoresizingMaskIntoConstraints = false

    contentView.addSubview(imageView)
    contentView.addSubview(separatorView)

    NSLayoutConstraint.activate([
      imageView.leadingAnchor.constraint(
        equalTo: contentView.leadingAnchor
      ),
      imageView.trailingAnchor.constraint(
        equalTo: contentView.trailingAnchor
      ),
      imageView.topAnchor.constraint(
        equalTo: contentView.topAnchor
      ),
      imageView.bottomAnchor.constraint(
        equalTo: contentView.bottomAnchor
      ),
      separatorView.leadingAnchor.constraint(
        equalTo: contentView.leadingAnchor
      ),
      separatorView.trailingAnchor.constraint(
        equalTo: contentView.trailingAnchor
      ),
      separatorView.topAnchor.constraint(
        equalTo: contentView.topAnchor
      ),
      separatorView.heightAnchor.constraint(
        equalToConstant: 1 / UIScreen.main.scale
      ),
    ])
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    imageRequest?.cancel()
    imageRequest = nil
    representedIdentifier = nil
    imageView.image = nil
    separatorView.isHidden = true
  }

  func configure(
    with displayTile: DisplayTile,
    imageURL: URL,
    prepareImage: @escaping () throws -> Void
  ) {
    representedIdentifier = displayTile.id
    separatorView.isHidden = !displayTile.showsPageSeparator

    imageRequest = ImagePipeline.shared.loadImage(
      at: imageURL,
      cacheKey: displayTile.id,
      prepare: prepareImage
    ) { [weak self] image in
      guard
        let self,
        self.representedIdentifier == displayTile.id
      else {
        return
      }
      self.imageView.image = image
    }
  }
}
