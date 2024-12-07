import UIKit
import Photos
import CoreLocation

class DigitalPictureFrameViewController: UIViewController {
    private var loadingLabel: UILabel!

    private var appStartTime: Date = Date()

    private var currentImageIndex: Int = -1
    private var hasStarted: Bool = false
    private var photoAssets: [PHAsset] = []

    private var isLowPowerModeEnabled: Bool = false
    private var isUserTouching: Bool = false

    private var debugLog: [String] = []
    private var initialMemoryUsage: String? = nil

    private var hourlyFetchTimer: Timer? = nil
    private var slideTimer: Timer? = nil

    private var lightMonitor: LightMonitor?

    private var imageViewLeft: UIImageView!
    private var imageViewRight: UIImageView!

    private var dateLabel: UILabel!
    private var locationLabel: UILabel!

    private var currentLeftImage: UIImage?
    private var currentRightImage: UIImage?
    private var nextLeftImage: UIImage?
    private var nextRightImage: UIImage?

    private var incomingImageViewLeft: UIImageView?
    private var incomingImageViewRight: UIImageView?

    private var locationName: String? = nil

    override func viewDidLoad() {
        super.viewDidLoad()

        appStartTime = Date()
        setupViews()
        requestPhotoLibraryPermission()
        keepScreenOn()
        scheduleHourlyPhotoFetch()
        handleLowPowerMode()

        setupLoadingLabel()
        showLoadingLabel()
    
        // Add touch gesture recognizer
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPressGesture.minimumPressDuration = 0.1
        view.addGestureRecognizer(longPressGesture)
    }

    func setupLoadingLabel() {
        loadingLabel = UILabel()
        loadingLabel.text = "Grouping images...."
        loadingLabel.textColor = .white
        loadingLabel.font = UIFont.systemFont(ofSize: 20, weight: .medium)
        loadingLabel.textAlignment = .center
        loadingLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(loadingLabel)

        NSLayoutConstraint.activate([
            loadingLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    func showLoadingLabel() {
        loadingLabel.isHidden = false
    }

    func hideLoadingLabel() {
        loadingLabel.isHidden = true
    }

    func debug(_ text: String) {
        debugLog.append("\(Date().string(format: "HH:mm:ss")) – \(text)")

        if debugLog.count > 20 {
            debugLog.removeFirst(debugLog.count - 20)
        }
    }

    func getMemoryUsage() -> String {
        var taskInfo = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: taskInfo)) / 4

        let kerr: kern_return_t = withUnsafeMutablePointer(to: &taskInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        if kerr == KERN_SUCCESS {
            let usedMB = taskInfo.resident_size / 1024 / 1024
            return "\(usedMB) MB"
        } else {
            let errorString = String(cString: mach_error_string(kerr), encoding: .ascii) ?? "Unknown error"
            return "Error: \(errorString)"
        }
    }

    func requestPhotoLibraryPermission() {
        PHPhotoLibrary.requestAuthorization { status in
            switch status {
            case .authorized:
                self.fetchPhotosFromAlbum(albumName: "Picture Frame")
            default:
                print("Denied access to photos.")
            }
        }
    }

    func scheduleHourlyPhotoFetch() {
        debug("Scheduling hourly photo fetch")
        self.hourlyFetchTimer?.invalidate()
        self.hourlyFetchTimer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { _ in
            self.debug("Timer fired: fetch photo updates")
            if !self.isLowPowerModeEnabled {
                self.fetchPhotosFromAlbum(albumName: "Picture Frame")
            }
        }
        RunLoop.main.add(self.hourlyFetchTimer!, forMode: .common)
    }

    func keepScreenOn() {
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func fetchPhotosFromAlbum(albumName: String) {
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "title = %@", albumName)
        fetchOptions.fetchLimit = 0

        let collectionResult: PHFetchResult<PHAssetCollection> = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .any,
            options: fetchOptions
        )

        guard let album = collectionResult.firstObject else {
            print("Album not found")
            return
        }

        let assetFetchOptions = PHFetchOptions()
        assetFetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        assetFetchOptions.fetchLimit = 0

        let result: PHFetchResult<PHAsset> = PHAsset.fetchAssets(in: album, options: assetFetchOptions)

        let formattedResult = processAssets(assets: result)

        if formattedResult.count != photoAssets.count {
            print("\(formattedResult.count - photoAssets.count) new photos found")

            self.photoAssets = formattedResult
            self.currentImageIndex = 0

            if !hasStarted && !isLowPowerModeEnabled {
                hasStarted = true
                DispatchQueue.main.async {
                    self.jumpToNextSlide()
                }
            }
        }
        
        hideLoadingLabel()
    }

    func jumpToNextSlide() {
        guard !self.photoAssets.isEmpty else { return }

        let currentAsset = self.photoAssets[self.currentImageIndex]
        let increment: Int
        if currentAsset.pixelWidth > currentAsset.pixelHeight {
            increment = 1  // Landscape
        } else {
            increment = 2  // Portrait
        }

        let nextSlideIndex = (self.currentImageIndex + increment) % self.photoAssets.count
        self.currentImageIndex = nextSlideIndex

        debug("Next slide: \(self.currentImageIndex)")

        let memoryUsage = self.getMemoryUsage()
        if initialMemoryUsage == nil {
            self.initialMemoryUsage = memoryUsage
        }
        debug("Current memory usage: \(memoryUsage). \(self.initialMemoryUsage ?? "") at init")

        loadImages(for: currentImageIndex)
    }

    func startNextSlideTimer() {
        guard !isLowPowerModeEnabled else {
            return
        }

        // Invalidate any previous timer
        slideTimer?.invalidate()

        slideTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { _ in
            self.jumpToNextSlide()
        }
        RunLoop.main.add(slideTimer!, forMode: .common)
    }

    func handleLowPowerMode() {
        self.lightMonitor = LightMonitor()
        self.lightMonitor?.startLightMonitor(onPowerModeChanged: { isLowPower in
            self.debug("Light monitor update. isLowPower: \(isLowPower)")
            self.isLowPowerModeEnabled = isLowPower
            if !isLowPower {
                self.fetchPhotosFromAlbum(albumName: "Picture Frame")
            }
        }, onDebug: self.debug)
    }

    func setupViews() {
        view.backgroundColor = .black

        imageViewLeft = UIImageView()
        imageViewLeft.contentMode = .scaleAspectFill
        imageViewLeft.clipsToBounds = true
        view.addSubview(imageViewLeft)

        imageViewRight = UIImageView()
        imageViewRight.contentMode = .scaleAspectFill
        imageViewRight.clipsToBounds = true
        view.addSubview(imageViewRight)

        dateLabel = UILabel()
        dateLabel.textColor = .white
        dateLabel.font = UIFont.systemFont(ofSize: 17)
        dateLabel.numberOfLines = 1
        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        dateLabel.alpha = 0.0
        view.addSubview(dateLabel)

        locationLabel = UILabel()
        locationLabel.textColor = .white
        locationLabel.font = UIFont.systemFont(ofSize: 17)
        locationLabel.numberOfLines = 1
        locationLabel.translatesAutoresizingMaskIntoConstraints = false
        locationLabel.alpha = 0.0
        view.addSubview(locationLabel)

        let safeArea = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            dateLabel.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: 16),
            dateLabel.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor, constant: -16),
            locationLabel.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: 16),
            locationLabel.bottomAnchor.constraint(equalTo: dateLabel.topAnchor, constant: -8)
        ])
    }

    @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            self.isUserTouching = true
            // Show labels
            dateLabel.alpha = 1.0
            locationLabel.alpha = 1.0
        } else if gesture.state == .ended || gesture.state == .cancelled {
            self.isUserTouching = false
            // Hide labels
            dateLabel.alpha = 0.0
            locationLabel.alpha = 0.0
        }
    }

    func loadImages(for index: Int) {
        let targetSize = CGSize(width: view.bounds.width / 2, height: view.bounds.height)

        if isPortrait(asset: photoAssets[index]), index + 1 < photoAssets.count {
            // Load two portrait images side by side
            loadImage(for: photoAssets[index], targetSize: targetSize) { image in
                self.nextLeftImage = image
            }

            loadImage(for: photoAssets[index + 1], targetSize: targetSize) { image in
                self.nextRightImage = image
                self.crossfadeToNewImages()
            }
        } else {
            // Load a single landscape image
            loadImage(for: photoAssets[index], targetSize: view.bounds.size) { image in
                self.nextLeftImage = image
                self.nextRightImage = nil
                self.crossfadeToNewImages()
            }
        }
    }

    func checkAndProceedWithCrossfade() {
        if let _ = nextLeftImage, (nextRightImage != nil || nextRightImage == nil) {
            DispatchQueue.main.async {
                self.crossfadeToNewImages()
            }
        }
    }

    func crossfadeToNewImages() {
        let halfWidth = view.bounds.width / 2
        var newLeftFrame = CGRect(x: 0, y: 0, width: halfWidth, height: view.bounds.height)
        var newRightFrame = CGRect(x: halfWidth, y: 0, width: halfWidth, height: view.bounds.height)

        if nextRightImage == nil {
            newLeftFrame = view.bounds
            newRightFrame = CGRect(x: view.bounds.width, y: 0, width: halfWidth, height: view.bounds.height)
        }

        // Create incoming image views with the same frames as the current ones
        incomingImageViewLeft?.removeFromSuperview()
        incomingImageViewRight?.removeFromSuperview()
        incomingImageViewLeft = UIImageView(frame: newLeftFrame)
        incomingImageViewLeft!.image = nextLeftImage
        incomingImageViewLeft!.contentMode = .scaleAspectFill
        incomingImageViewLeft!.clipsToBounds = true
        incomingImageViewLeft!.alpha = 0

        incomingImageViewRight = UIImageView(frame: newRightFrame)
        incomingImageViewRight!.image = nextRightImage ?? nextLeftImage
        incomingImageViewRight!.contentMode = .scaleAspectFill
        incomingImageViewRight!.clipsToBounds = true
        incomingImageViewRight!.alpha = 0

        view.addSubview(incomingImageViewLeft!)
        view.addSubview(incomingImageViewRight!)

        // Animate the crossfade without changing frames
        UIView.animate(withDuration: 1.0, animations: {
            self.incomingImageViewLeft?.alpha = 1.0
            self.incomingImageViewRight?.alpha = 1.0
        }, completion: { _ in
            self.imageViewLeft.frame = newLeftFrame
            self.imageViewRight.frame = newRightFrame

            self.imageViewLeft.image = self.nextLeftImage
            self.imageViewRight.image = self.nextRightImage

            // Remove incoming image views
            self.incomingImageViewLeft?.removeFromSuperview()
            self.incomingImageViewRight?.removeFromSuperview()
            self.incomingImageViewLeft = nil
            self.incomingImageViewRight = nil

            // Update current images and reset next images
            self.currentLeftImage = self.nextLeftImage
            self.currentRightImage = self.nextRightImage
            self.nextLeftImage = nil
            self.nextRightImage = nil

            // Update labels and start next slide timer
            self.updateLabels()
            self.startNextSlideTimer()
        })
    }


    func isPortrait(asset: PHAsset) -> Bool {
        return asset.pixelHeight > asset.pixelWidth
    }

    func loadImage(for asset: PHAsset, targetSize: CGSize, completion: @escaping (UIImage?) -> Void) {
        let imageManager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .none
        options.version = .current
        options.isNetworkAccessAllowed = true

        imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            completion(image)
        }
    }

    func formatDate(_ date1: Date?, _ date2: Date? = nil) -> String? {
        guard let date1 = date1 else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        if date2 == nil || date1 == date2 {
            return formatter.string(from: date1)
        }

        return "\(formatter.string(from: date1)) / \(formatter.string(from: date2!))"
    }

    func updateLabels() {
        let asset1 = photoAssets[currentImageIndex]
        var asset2: PHAsset?
        if currentRightImage != nil, currentImageIndex + 1 < photoAssets.count {
            asset2 = photoAssets[currentImageIndex + 1]
        }

        let formattedDate = formatDate(asset1.creationDate, asset2?.creationDate)
        dateLabel.text = formattedDate

        updatePlace()
    }

    func updatePlace() {
        guard let location = self.photoAssets[self.currentImageIndex].location else {
            self.locationName = nil
            self.locationLabel.text = nil
            return
        }
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            guard let place = placemarks?.first, error == nil else {
                self.locationName = nil
                self.locationLabel.text = nil
                return
            }

            var placeName = ""

            if let locality = place.locality {
                placeName += locality
            }

            if let adminRegion = place.administrativeArea {
                placeName += ", \(adminRegion)"
            }

            if let country = place.country {
                placeName += ", \(country)"
            }

            self.locationName = placeName.isEmpty ? nil : placeName

            DispatchQueue.main.async {
                self.locationLabel.text = self.locationName
            }
        }
    }
}

extension Date {
    func string(format: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        return formatter.string(from: self)
    }
}
