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
    @State private var appStartTime: Date = Date()

    @State private var currentImageIndex: Int = -1
    @State private var hasStarted: Bool = false
    @State private var photoAssets: [PHAsset] = []

    @State private var isLowPowerModeEnabled: Bool = false
    @State private var isUserTouching: Bool = false

    @State private var debugLog: [String] = []
    @State private var initialMemoryUsage: String? = nil

    @State private var hourlyFetchTimer: Timer? = nil
    @State private var slideTimer: Timer? = nil

    @State private var lightMonitor: LightMonitor?
    
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
                if isUserTouching {
                    DebugLogView(debugLog: debugLog, appStartTime: appStartTime)
                }
            }
            .statusBar(hidden: true)
            .onAppear {
                appStartTime = Date() 
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
        debug("Scheduling hourly photo fetch")
        self.hourlyFetchTimer?.invalidate()
        self.hourlyFetchTimer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { _ in
            debug("Timer fired: fetch photo updates")
            if !self.isLowPowerModeEnabled {
                fetchPhotosFromAlbum(albumName: "Picture Frame")
            }
        }
        RunLoop.main.add(self.hourlyFetchTimer!, forMode: .common)
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
            debug("\(formattedResult.count - photoAssets.count) new photos found")

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
        
        let nextSlideIndex = (self.currentImageIndex + increment) % self.photoAssets.count
        self.currentImageIndex = nextSlideIndex

        debug("Next slide: \(self.currentImageIndex) -> \(nextSlideIndex)")
        
        let memoryUsage = self.getMemoryUsage()
        if (initialMemoryUsage == nil) {
            self.initialMemoryUsage = memoryUsage
        }
        debug("Current memory usage: \(memoryUsage). \(self.initialMemoryUsage) at init")
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
        
        slideTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { _ in
            jumpToNextSlide()
        }

        RunLoop.main.add(slideTimer!, forMode: .common)
    }

    
    func handleLowPowerMode() {
        self.lightMonitor = LightMonitor()
        self.lightMonitor?.startLightMonitor(onPowerModeChanged: { isLowPower in
            debug("Light monitor update. isLowPower: \(isLowPower)")
            self.isLowPowerModeEnabled = isLowPower
            if !isLowPower {
                fetchPhotosFromAlbum(albumName: "Picture Frame")
            }
        }, onDebug: debug)
    }
}
