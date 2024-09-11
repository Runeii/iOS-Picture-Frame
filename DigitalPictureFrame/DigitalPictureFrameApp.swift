import Photos
import SwiftUI

var slideTimer: Timer? = nil

@main
struct DigitalPictureFrameApp: App {
    @State private var currentImageIndex: Int = -1
    @State private var hasStarted: Bool = false
    @State private var photoAssets: [PHAsset] = []

    @State private var isLowPowerModeEnabled: Bool = false
    @State private var isUserTouching: Bool = false

    var body: some Scene {
        WindowGroup {
            ZStack {
                // Single ContentView to handle image display with fade transition
                ContentView(
                    photoAssets: $photoAssets,
                    currentImageIndex: $currentImageIndex,
                    isUserTouching: $isUserTouching,
                    onSlideDisplayed: { index in
                        self.startNextSlideTimer()
                    }
                )
                .transition(.opacity)  // Apply fading transition between slides
                .edgesIgnoringSafeArea(.all)  // Extend content to the screen edges
            }
            .statusBar(hidden: true)
            .onAppear {
                requestPhotoLibraryPermission()
                keepScreenOn()
                scheduleHourlyPhotoFetch()
                handleLowPowerMode()
            }
            .onChange(of: photoAssets) { _ in
                if !hasStarted && !isLowPowerModeEnabled {
                    hasStarted = true
                    self.startNextSlideTimer()
                }
            }
            .onLongPressGesture(minimumDuration: .infinity, pressing: { isTouching in
                self.isUserTouching = isTouching
                if isTouching {
                    slideTimer?.invalidate()
                } else {
                    self.startNextSlideTimer()
                }
            }, perform: {})
        }
    }

    // Request permission to access photo library
    func requestPhotoLibraryPermission() {
        PHPhotoLibrary.requestAuthorization { status in
            switch status {
            case .authorized, .limited:
                fetchPhotosFromAlbum(albumName: "Picture Frame")
            case .denied, .restricted:
                print("Denied access to photos.")
            case .notDetermined:
                print("Photo access not determined.")
            @unknown default:
                break
            }
        }
    }

    // Schedule hourly refresh of the album to fetch new photos
    func scheduleHourlyPhotoFetch() {
        Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { _ in
            if !self.isLowPowerModeEnabled {
                fetchPhotosFromAlbum(albumName: "Picture Frame")
            }
        }
    }

    // Prevent screen from turning off
    func keepScreenOn() {
        UIApplication.shared.isIdleTimerDisabled = true
    }

    // Fetch photos from the album and shuffle them
    func fetchPhotosFromAlbum(albumName: String) {
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "title = %@", albumName)
        fetchOptions.fetchLimit = 0

        let collectionResult: PHFetchResult<PHAssetCollection> = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: fetchOptions)

        guard let album = collectionResult.firstObject else {
            print("Album not found")
            return
        }

        let assetFetchOptions = PHFetchOptions()
        assetFetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        assetFetchOptions.fetchLimit = 0

        let result: PHFetchResult<PHAsset> = PHAsset.fetchAssets(in: album, options: assetFetchOptions)
        let formattedResult = processAssets(assets: result)
        
        if (formattedResult.count != photoAssets.count) {
            self.photoAssets = formattedResult
            self.currentImageIndex = 0
        }
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
        
        self.currentImageIndex = (self.currentImageIndex + increment) % self.photoAssets.count
    }

    // Start a timer for the next slide
    func startNextSlideTimer() {
        guard !isLowPowerModeEnabled else {
            return
        }
        
        let assetManager = StorageManager.shared
        assetManager.storeOrUpdateAssetSeenTime(assetId: photoAssets[currentImageIndex].localIdentifier)

        // Invalidate any previous timer
        slideTimer?.invalidate()

        slideTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { _ in
            jumpToNextSlide()
        }

        RunLoop.main.add(slideTimer!, forMode: .common)
    }

    
    func handleLowPowerMode() {
        let lightMonitor = LightMonitor()

        lightMonitor.startLightMonitor { isLowPower in
            self.isLowPowerModeEnabled = isLowPower
            if !isLowPower {
                fetchPhotosFromAlbum(albumName: "Picture Frame")
            }
        }
    }
}
