import Photos
import SwiftUI

var slideTimer: Timer? = nil

@main
struct DigitalPictureFrameApp: App {
    @State private var currentImageIndex: Int = -1
    @State private var hasStarted: Bool = false
    @State private var photoAssets: [PHAsset] = []

    @State private var isLowPowerModeEnabled: Bool = false

    var body: some Scene {
        WindowGroup {
            ZStack {
                // Single ContentView to handle image display with fade transition
                ContentView(photoAssets: $photoAssets, currentImageIndex: $currentImageIndex, onSlideDisplayed: { index in
                    self.startNextSlideTimer()
                })
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
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
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
        print(result.count)
        self.photoAssets = processAssets(assets: result)
        print(self.photoAssets.count)
        self.currentImageIndex = 0
    }

    func interleavePortraitAndLandscapeAssets(portraitAssets: [PHAsset], landscapeAssets: [PHAsset]) -> [PHAsset] {
        let shuffledLandscape = landscapeAssets.shuffled()
        let shuffledPortrait = portraitAssets.shuffled()

        var portraitPairs: [[PHAsset]] = []
        var portraitIndex = 0

        while portraitIndex + 1 < shuffledPortrait.count {
            portraitPairs.append([shuffledPortrait[portraitIndex], shuffledPortrait[portraitIndex + 1]])
            portraitIndex += 2
        }

        var finalAssets: [PHAsset] = []
        var landscapeIndex = 0

        for pair in portraitPairs {
            if landscapeIndex < shuffledLandscape.count {
                finalAssets.append(shuffledLandscape[landscapeIndex])
                landscapeIndex += 1
            }
            finalAssets.append(contentsOf: pair)
        }

        while landscapeIndex < shuffledLandscape.count {
            finalAssets.append(shuffledLandscape[landscapeIndex])
            landscapeIndex += 1
        }

        return finalAssets
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
                self.jumpToNextSlide()
            }
        }
    }
}
