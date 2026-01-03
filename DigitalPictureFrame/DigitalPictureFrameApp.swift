import Photos
import SwiftUI

extension Date {
    func string(format: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        return formatter.string(from: self)
    }
}

@main
struct DigitalPictureFrameApp: App {
    @State private var hasPermission: Bool = false

    @State private var selectedAlbum: PHAssetCollection?
    @State private var showingAlbumSelector = true

    @State private var appStartTime: Date = Date()

    @State private var currentImageIndex: Int = -1
    @State private var hasStarted: Bool = false
    @State private var photoAssets: [PHAsset] = []

    @State private var isUserTouching: Bool = false

    @State private var debugLog: [String] = []
    @State private var initialMemoryUsage: String? = nil

    @State private var hourlyFetchTimer: Timer? = nil
    @State private var slideTimer: Timer? = nil
    
    @StateObject private var imageCache = ImageCacheManager.shared
    @State private var showingCacheProgress = false
    @State private var isInitialLoad = true
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                if let album = selectedAlbum {
                    if imageCache.isCachingComplete && !photoAssets.isEmpty {
                        ContentView(
                            photoAssets: $photoAssets,
                            currentImageIndex: $currentImageIndex,
                            isUserTouching: $isUserTouching,
                            onSlideDisplayed: { index in
                                self.startNextSlideTimer()
                            }
                        )
                        .edgesIgnoringSafeArea(.all)
                        .onLongPressGesture(minimumDuration: .infinity, pressing: { isTouching in
                            self.isUserTouching = isTouching

                            if isTouching {
                                cleanupTimers()
                            } else {
                                self.startNextSlideTimer()
                            }
                        }, perform: {})
                    } else if showingCacheProgress {
                        CacheProgressView(progress: imageCache.cachingProgress, isInitialLoad: isInitialLoad)
                    }
                } else if (hasPermission) {
                    AlbumSelectionView(selectedAlbum: $selectedAlbum)
                }
            }
            .statusBar(hidden: true)
            .onAppear {
                clearFolderIfRequired()
                registerUserDefaults()
                requestPhotoLibraryPermission()

                // Try to restore previously selected album
                if let savedAlbumId = UserDefaults.standard.string(forKey: "selectedAlbumId") {
                    let options = PHFetchOptions()
                    let result = PHAssetCollection.fetchAssetCollections(
                        withLocalIdentifiers: [savedAlbumId],
                        options: options
                    )
                    selectedAlbum = result.firstObject
                }

                appStartTime = Date()
                keepScreenOn()
                scheduleHourlyPhotoFetch()
            }
            .onDisappear {
                cleanupTimers()
            }
            .onChange(of: selectedAlbum) { album in
                fetchPhotosFromAlbum()
            }
        }
    }
    
    func clearFolderIfRequired() {
        let resetKey = "reset_selected_folder"
        if UserDefaults.standard.bool(forKey: resetKey) {
            // Reset the selected folder
            UserDefaults.standard.removeObject(forKey: "selectedAlbumId")
            
            // Reset the toggle to off (so it doesn't reset repeatedly)
            UserDefaults.standard.set(false, forKey: resetKey)
            
            // Also clear image cache when resetting folder
            imageCache.clearCache()
            
            print("Selected folder identifier reset and cache cleared.")
        }
    }

    // Request permission to access photo library
    func requestPhotoLibraryPermission() {
        PHPhotoLibrary.requestAuthorization { status in
            switch status {
            case .authorized, .limited:
                self.hasPermission = true
                return
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
        print("Scheduling hourly photo fetch")
        cleanupTimers()
        
        let interval = UserDefaults.standard.double(forKey: "check_duration")
        self.hourlyFetchTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            print("Timer fired: fetch photo updates")
            isInitialLoad = false // Subsequent fetches are incremental
            fetchPhotosFromAlbum()
        }
        
        if let timer = self.hourlyFetchTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func registerUserDefaults() {
        if let settingsBundle = Bundle.main.url(forResource: "Settings", withExtension: "bundle"),
           let settings = NSDictionary(contentsOf: settingsBundle.appendingPathComponent("Root.plist")),
           let preferences = settings["PreferenceSpecifiers"] as? [[String: Any]] {
            
            for preference in preferences {
                if let key = preference["Key"] as? String,
                   let defaultValue = preference["DefaultValue"],
                   UserDefaults.standard.object(forKey: key) == nil {
                    UserDefaults.standard.set(defaultValue, forKey: key)
                }
            }
        }
    }
    // Prevent screen from turning off
    func keepScreenOn() {
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func fetchPhotosFromAlbum() {
        guard let album = selectedAlbum else {
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let assetFetchOptions = PHFetchOptions()
            assetFetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
            assetFetchOptions.fetchLimit = 0
            
            var allAssets: [PHAsset] = []
            
            // Fetch from selected album
            let selectedAlbumResults = PHAsset.fetchAssets(in: album, options: assetFetchOptions)
            print("Found \(selectedAlbumResults.count) photos in selected album")
            
            // Add assets from selected album
            selectedAlbumResults.enumerateObjects { (asset, _, _) in
                allAssets.append(asset)
            }

            let secondaryAlbumName = UserDefaults.standard.string(forKey: "secondary_album")
            
            if secondaryAlbumName != nil && secondaryAlbumName != "" {
                print("Has secondary album defined", secondaryAlbumName!)
                // Fetch shared albums
                let sharedAlbumOptions = PHFetchOptions()
                sharedAlbumOptions.predicate = NSPredicate(format: "title = %@", secondaryAlbumName!)
                let sharedAlbums = PHAssetCollection.fetchAssetCollections(
                    with: .album,
                    subtype: .albumCloudShared,
                    options: sharedAlbumOptions
                )
                
                // Fetch from shared album if found
                if let sharedAlbum = sharedAlbums.firstObject {
                    let sharedAlbumResults = PHAsset.fetchAssets(in: sharedAlbum, options: assetFetchOptions)
                    print("Found \(sharedAlbumResults.count) photos in secondary album")
                    
                    // Add assets from shared album
                    sharedAlbumResults.enumerateObjects { (asset, _, _) in
                        allAssets.append(asset)
                    }
                } else {
                    print("Shared album \(secondaryAlbumName!) not found")
                }
                
                print("Total photos after merge: \(allAssets.count)")
            }
            
            
            let formattedResult = processAssets(assets: allAssets)
            
            print("Formatted \(formattedResult.count) photos")
            
            DispatchQueue.main.async {
                let oldCount = self.photoAssets.count
                let newCount = formattedResult.count
                
                if newCount != oldCount || self.isInitialLoad {
                    if self.isInitialLoad {
                        print("Initial load: caching \(newCount) photos")
                    } else {
                        print("Change detected: \(newCount - oldCount) photos difference")
                    }
                    
                    self.photoAssets = formattedResult
                    
                    // Clean up any removed assets from cache
                    self.imageCache.cleanupRemovedAssets(currentAssets: formattedResult)
                    
                    // Start caching (incremental for updates, full for initial load)
                    self.showingCacheProgress = true
                    
                    if self.isInitialLoad {
                        // Full cache for initial load
                        self.imageCache.preloadImages(assets: formattedResult) {
                            self.handleCacheComplete()
                        }
                    } else {
                        // Incremental cache for updates
                        self.imageCache.updateCache(newAssets: formattedResult) {
                            self.handleCacheComplete()
                        }
                    }
                }
            }
        }
    }
    
    private func handleCacheComplete() {
        self.showingCacheProgress = false
        self.isInitialLoad = false
        print("Image caching complete.")
        if self.currentImageIndex < 0 || self.currentImageIndex >= self.photoAssets.count {
            self.currentImageIndex = 0
        }
        
        self.jumpToNextSlide()
        
        let stats = self.imageCache.getCacheStats()
        print("✅ Cache updated! Count: \(stats.count), Memory: \(stats.memoryUsage)")
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
        print("Next slide: \(self.currentImageIndex) -> \(nextSlideIndex)")

        self.currentImageIndex = nextSlideIndex
    }

    // Start a timer for the next slide
    func startNextSlideTimer() {
        let assetManager = StorageManager.shared
        assetManager.storeOrUpdateAssetSeenTime(assetId: photoAssets[currentImageIndex].localIdentifier)

        // Invalidate any previous timer
        slideTimer?.invalidate()
        slideTimer = nil
        
        slideTimer = Timer.scheduledTimer(withTimeInterval: UserDefaults.standard.double(forKey: "slide_duration"), repeats: false) { _ in
            jumpToNextSlide()
        }

        if let timer = slideTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }
    
    // Clean up timers properly when the app terminates
    private func cleanupTimers() {
        hourlyFetchTimer?.invalidate()
        hourlyFetchTimer = nil
        slideTimer?.invalidate()
        slideTimer = nil
    }
}
