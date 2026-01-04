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
    @State private var nextCheckTime: Date? = nil
    
    @StateObject private var imageCache = ImageCacheManager.shared
    @State private var showingCacheProgress = false
    @State private var showingLoadingProgress = false
    @State private var loadingProgress: Float = 0.0
    @State private var loadingStep: String = ""
    @State private var isInitialLoad = true
    
    // Track album state for change detection (now using filtered count)
    @State private var lastFilteredAssetCount: Int = 0
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                if let album = selectedAlbum {
                    if imageCache.isCachingComplete && !photoAssets.isEmpty {
                        ContentView(
                            photoAssets: $photoAssets,
                            currentImageIndex: $currentImageIndex,
                            isUserTouching: $isUserTouching,
                            nextCheckTime: nextCheckTime,
                            totalSlides: photoAssets.count,
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
                    } else if showingLoadingProgress {
                        LoadingProgressView(progress: loadingProgress, currentStep: loadingStep, isInitialLoad: isInitialLoad)
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
        nextCheckTime = Date().addingTimeInterval(interval)
        
        self.hourlyFetchTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            print("Timer fired: checking for photo updates")
            isInitialLoad = false // Subsequent fetches are incremental
            checkForAlbumChanges()
            // Update next check time
            nextCheckTime = Date().addingTimeInterval(interval)
        }
        
        if let timer = self.hourlyFetchTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    // Check if albums have changed before doing expensive fetch operations
    // Now uses filtered asset count (after time frame filtering) for better change detection
    func checkForAlbumChanges() {
        guard let album = selectedAlbum else {
            return
        }
        
        DispatchQueue.global(qos: .utility).async {
            var allAssets: [PHAsset] = []
            
            // Fetch main album
            let mainAlbumAssets = PHAsset.fetchAssets(in: album, options: PHFetchOptions())
            print("Main album asset count: \(mainAlbumAssets.count)")
            
            // Add assets from main album
            mainAlbumAssets.enumerateObjects { (asset, _, _) in
                allAssets.append(asset)
            }

            // Check secondary album if configured
            let secondaryAlbumName = UserDefaults.standard.string(forKey: "secondary_album")
            
            if let secondaryName = secondaryAlbumName, !secondaryName.isEmpty {
                let sharedAlbumOptions = PHFetchOptions()
                sharedAlbumOptions.predicate = NSPredicate(format: "title = %@", secondaryName)
                let sharedAlbums = PHAssetCollection.fetchAssetCollections(
                    with: .album,
                    subtype: .albumCloudShared,
                    options: sharedAlbumOptions
                )
                
                if let sharedAlbum = sharedAlbums.firstObject {
                    let secondaryAssets = PHAsset.fetchAssets(in: sharedAlbum, options: PHFetchOptions())
                    print("Secondary album asset count: \(secondaryAssets.count)")
                    
                    // Add assets from secondary album
                    secondaryAssets.enumerateObjects { (asset, _, _) in
                        allAssets.append(asset)
                    }
                }
            }
            
            // Apply time frame filtering to get the actual count that will be processed
            let filteredAssets = restrictToTimeFrame(assets: allAssets)
            let filteredAssetCount = filteredAssets.count
            
            print("Total raw asset count: \(allAssets.count)")
            print("Filtered asset count (after time frame): \(filteredAssetCount)")
            
            DispatchQueue.main.async {
                let hasCountChanged = filteredAssetCount != self.lastFilteredAssetCount
                
                if hasCountChanged || self.lastFilteredAssetCount == 0 {
                    if self.lastFilteredAssetCount == 0 {
                        print("Album changes detected - first run")
                    } else {
                        print("Album changes detected - filtered count changed (\(self.lastFilteredAssetCount) → \(filteredAssetCount))")
                    }
                    
                    // Update our tracking variable
                    self.lastFilteredAssetCount = filteredAssetCount
                    
                    // Proceed with full fetch
                    self.fetchPhotosFromAlbum()
                } else {
                    print("No album changes detected - skipping fetch")
                }
            }
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
        
        // Show loading progress only on initial load
        if isInitialLoad {
            showingLoadingProgress = true
            loadingProgress = 0.0
            loadingStep = "Fetching album contents..."
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let assetFetchOptions = PHFetchOptions()
            assetFetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
            assetFetchOptions.fetchLimit = 0
            
            var allAssets: [PHAsset] = []
            
            // Fetch from selected album
            let selectedAlbumResults = PHAsset.fetchAssets(in: album, options: assetFetchOptions)
            print("Found \(selectedAlbumResults.count) photos in selected album")
            
            if self.isInitialLoad {
                DispatchQueue.main.async {
                    self.loadingProgress = 0.1
                    self.loadingStep = "Loading \(selectedAlbumResults.count) photos..."
                }
            }
            
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
                    
                    if self.isInitialLoad {
                        DispatchQueue.main.async {
                            self.loadingProgress = 0.15
                            self.loadingStep = "Loading secondary album..."
                        }
                    }
                    
                    // Add assets from shared album
                    sharedAlbumResults.enumerateObjects { (asset, _, _) in
                        allAssets.append(asset)
                    }
                } else {
                    print("Shared album \(secondaryAlbumName!) not found")
                }
                
                print("Total photos after merge: \(allAssets.count)")
            }
            
            let progressCallback: (Float, String) -> Void = { progress, step in
                if self.isInitialLoad {
                    DispatchQueue.main.async {
                        // Map progress from 0-1 to 0.2-0.8 range (leaving room for fetch and cache phases)
                        self.loadingProgress = 0.2 + (progress * 0.6)
                        self.loadingStep = step
                    }
                }
            }
            
            let formattedResult = processAssets(assets: allAssets, progressCallback: progressCallback)
            
            print("Formatted \(formattedResult.count) photos")
            
            DispatchQueue.main.async {
                let oldCount = self.photoAssets.count
                let newCount = formattedResult.count
                
                if newCount != oldCount || self.isInitialLoad {
                    if self.isInitialLoad {
                        print("Initial load: caching \(newCount) photos")
                        // Hide loading progress and show cache progress
                        self.showingLoadingProgress = false
                        self.showingCacheProgress = true
                    } else {
                        print("Change detected: \(newCount - oldCount) photos difference")
                        self.showingCacheProgress = true
                    }
                    
                    self.photoAssets = formattedResult
                    
                    // Clean up any removed assets from cache
                    self.imageCache.cleanupRemovedAssets(currentAssets: formattedResult)
                    
                    // Start caching (incremental for updates, full for initial load)
                    
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
        self.currentImageIndex = 0
        print("Image caching complete.")
        
        self.jumpToNextSlide()
        
        let stats = self.imageCache.getCacheStats()
        print("✅ Cache updated! Disk size: \(stats.diskSize), Disk count: \(stats.count)")
        
        // Update tracking variables after successful fetch and cache
        updateAlbumTrackingState()
    }
    
    // Update our tracking variables to reflect current album state
    private func updateAlbumTrackingState() {
        guard let album = selectedAlbum else { return }
        
        DispatchQueue.global(qos: .utility).async {
            var allAssets: [PHAsset] = []
            
            // Fetch main album
            let mainAlbumAssets = PHAsset.fetchAssets(in: album, options: PHFetchOptions())
            mainAlbumAssets.enumerateObjects { (asset, _, _) in
                allAssets.append(asset)
            }
            
            // Fetch secondary album if configured
            let secondaryAlbumName = UserDefaults.standard.string(forKey: "secondary_album")
            if let secondaryName = secondaryAlbumName, !secondaryName.isEmpty {
                let sharedAlbumOptions = PHFetchOptions()
                sharedAlbumOptions.predicate = NSPredicate(format: "title = %@", secondaryName)
                let sharedAlbums = PHAssetCollection.fetchAssetCollections(
                    with: .album,
                    subtype: .albumCloudShared,
                    options: sharedAlbumOptions
                )
                
                if let sharedAlbum = sharedAlbums.firstObject {
                    let secondaryAssets = PHAsset.fetchAssets(in: sharedAlbum, options: PHFetchOptions())
                    secondaryAssets.enumerateObjects { (asset, _, _) in
                        allAssets.append(asset)
                    }
                }
            }
            
            // Apply time frame filtering to match what will actually be processed
            let filteredAssets = restrictToTimeFrame(assets: allAssets)
            let filteredAssetCount = filteredAssets.count
            
            DispatchQueue.main.async {
                self.lastFilteredAssetCount = filteredAssetCount
                print("📊 Album state tracking initialized - Raw count: \(allAssets.count), Filtered count: \(filteredAssetCount)")
            }
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
        
        let nextSlideIndex = (self.currentImageIndex + increment) % self.photoAssets.count

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
