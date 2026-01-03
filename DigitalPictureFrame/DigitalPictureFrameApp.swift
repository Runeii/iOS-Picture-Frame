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

    @State private var lightMonitor: LightMonitor?
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                if let album = selectedAlbum {
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
                            slideTimer?.invalidate()
                        } else {
                            self.startNextSlideTimer()
                        }
                    }, perform: {})
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
            
            print("Selected folder identifier reset.")
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
        self.hourlyFetchTimer?.invalidate()
        self.hourlyFetchTimer = Timer.scheduledTimer(withTimeInterval: UserDefaults.standard.double(forKey: "check_duration"), repeats: true) { _ in
            print("Timer fired: fetch photo updates")
            fetchPhotosFromAlbum()
        }
        RunLoop.main.add(self.hourlyFetchTimer!, forMode: .common)
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
                if (formattedResult.count != self.photoAssets.count) {
                    print("\(formattedResult.count - (self.photoAssets.count)) new photos found")
                    
                    self.photoAssets = formattedResult
                    self.currentImageIndex = 0
                    self.jumpToNextSlide()
                }
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
        print("Next slide: \(self.currentImageIndex) -> \(nextSlideIndex)")

        self.currentImageIndex = nextSlideIndex
    }

    // Start a timer for the next slide
    func startNextSlideTimer() {
        let assetManager = StorageManager.shared
        assetManager.storeOrUpdateAssetSeenTime(assetId: photoAssets[currentImageIndex].localIdentifier)

        // Invalidate any previous timer
        slideTimer?.invalidate()
        
        slideTimer = Timer.scheduledTimer(withTimeInterval: UserDefaults.standard.double(forKey: "slide_duration"), repeats: false) { _ in
            jumpToNextSlide()
        }

        RunLoop.main.add(slideTimer!, forMode: .common)
    }
}
