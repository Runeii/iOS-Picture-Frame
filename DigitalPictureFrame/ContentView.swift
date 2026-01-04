import SwiftUI
import Photos
import UIKit
import CoreLocation

struct ContentView: View {
    @Binding var photoAssets: [PHAsset]
    @Binding var currentImageIndex: Int
    @Binding var isUserTouching: Bool
    let nextCheckTime: Date?
    let totalSlides: Int

    var onSlideDisplayed: (Int) -> Void

    @State private var displayImageIndex: Int = 0;

    @State private var currentLeftImage: UIImage? = nil
    @State private var currentRightImage: UIImage? = nil
    @State private var nextLeftImage: UIImage? = nil
    @State private var nextRightImage: UIImage? = nil
    @State private var fadeProgress: Double = 1.0
    
    @State private var locationName: String? = nil
    @State private var currentGeocoder: CLGeocoder?
    
    private let imageCache = ImageCacheManager.shared
    
    var body: some View {
        ZStack {
            // For portrait mode with two images side by side
            if let currentLeftImage = currentLeftImage, let currentRightImage = currentRightImage {
                HStack(spacing: 0) {
                    imageView(image: currentLeftImage, width: UIScreen.main.bounds.width / 2)
                    imageView(image: currentRightImage, width: UIScreen.main.bounds.width / 2)
                }
                .opacity(fadeProgress) // Fade out with progress
            } else if let currentLeftImage = currentLeftImage { // Landscape or single image
                Image(uiImage: currentLeftImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
                    .clipped()
                    .opacity(fadeProgress)
            }
            
            // For next portrait mode images side by side
            if let nextLeftImage = nextLeftImage, let nextRightImage = nextRightImage {
                HStack(spacing: 0) {
                    imageView(image: nextLeftImage, width: UIScreen.main.bounds.width / 2)
                    imageView(image: nextRightImage, width: UIScreen.main.bounds.width / 2)
                }
                .opacity(1.0 - fadeProgress) // Fade in with progress
            } else if let nextLeftImage = nextLeftImage { // Next landscape or single image
                Image(uiImage: nextLeftImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
                    .clipped()
                    .opacity(1.0 - fadeProgress)
            }
            if currentLeftImage != nil {
                VStack(alignment: .leading) {
                    Spacer()
                    if let formattedDate = formatDate(photoAssets[currentImageIndex].customDate, currentRightImage != nil ? photoAssets[currentImageIndex + 1].customDate : nil) {
                        Text(formattedDate)
                            .foregroundColor(.white)
                            .padding(.bottom, 2)
                    }
                    if locationName != nil {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin.and.ellipse") // Location marker icon
                                .foregroundColor(.white)
                            Text(locationName!)
                                .foregroundColor(.white)
                        }
                    }
                }.font(.body) // Customize the font as needed
                    .opacity(isUserTouching || UserDefaults.standard.bool(forKey: "always_show_labels") ? 1.0 : 0.0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding([.leading, .bottom], 16)
                
                // Bottom-right info overlay
                if currentLeftImage != nil && UserDefaults.standard.bool(forKey: "debug_info") {
                    VStack(alignment: .trailing) {
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            if let nextCheck = nextCheckTime {
                                Text("Next check at: \(formatTime(nextCheck))")
                                    .foregroundColor(.white)
                                    .font(.caption)
                            }
                            Text("Current index: \(getCurrentSlideNumber()) / \(totalSlides)")
                                .foregroundColor(.white)
                                .font(.caption)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding([.trailing, .bottom], 16)
                }
            }
        }
        .onAppear {
            print("ContentView appeared - currentImageIndex: \(currentImageIndex)")
            displayImageIndex = currentImageIndex
            if displayImageIndex >= 0 && displayImageIndex < photoAssets.count {
                print("Loading initial images for displayImageIndex: \(displayImageIndex)")
                loadImages(for: displayImageIndex) {
                    // Set current images immediately (no crossfade for initial load)
                    self.currentLeftImage = self.nextLeftImage
                    self.currentRightImage = self.nextRightImage
                    self.nextLeftImage = nil
                    self.nextRightImage = nil
                    self.fadeProgress = 1.0
                    
                    // Start the slideshow timer for the first image
                    self.onSlideDisplayed(displayImageIndex)
                    
                    // Load location for initial image
                    self.updateLocationForCurrentImage()
                }
            }
        }
        .onChange(of: currentImageIndex) { newIndex in
            crossfadeToNewImage(for: newIndex)
            updateLocationForCurrentImage()
        }
        .onDisappear {
            cleanupOldImages()
        }
    }

    // Function to handle crossfade to the new image(s)
    func crossfadeToNewImage(for newIndex: Int) {
        loadImages(for: newIndex) { // Load new images (both portrait and landscape cases)
            // Start crossfade animation
            withAnimation(.easeInOut(duration: UserDefaults.standard.double(forKey: "fade_duration"))) {
                self.fadeProgress = 0.0 // Crossfade from current to next images
            }
            
            // After the crossfade is complete, switch images
            DispatchQueue.main.asyncAfter(deadline: .now() + UserDefaults.standard.double(forKey: "fade_duration")) {
                // Clean up old images to free memory
                self.cleanupOldImages()
                
                self.currentLeftImage = self.nextLeftImage // Update current left image
                self.currentRightImage = self.nextRightImage // Update current right image (for portrait mode)
                
                // Log details about the newly set images
                //self.logImageDetails(for: newIndex)
                
                self.nextLeftImage = nil
                self.nextRightImage = nil
                self.fadeProgress = 1.0 // Reset fade progress for the next crossfade
                self.displayImageIndex = newIndex // Update display index
                self.onSlideDisplayed(newIndex) // Notify parent that slide has changed
            }
        }
    }

    // Helper function to load both portrait and landscape images FROM CACHE
    func loadImages(for index: Int, completion: (() -> Void)? = nil) {
        guard index < photoAssets.count else {
            completion?()
            return
        }
        
        if isPortrait(asset: photoAssets[index]), index + 1 < photoAssets.count {
            // Load two portrait images side by side from cache
            let leftAsset = photoAssets[index]
            let rightAsset = photoAssets[index + 1]
            
            self.nextLeftImage = imageCache.getCachedImage(for: leftAsset.localIdentifier)
            self.nextRightImage = imageCache.getCachedImage(for: rightAsset.localIdentifier)
            
            if nextLeftImage == nil {
                print("Warning: Left portrait image not in cache: \(leftAsset.localIdentifier)")
            }
            if nextRightImage == nil {
                print("Warning: Right portrait image not in cache: \(rightAsset.localIdentifier)")
            }
            
            completion?()
        } else {
            // Load a single landscape image from cache
            let asset = photoAssets[index]
            self.nextLeftImage = imageCache.getCachedImage(for: asset.localIdentifier)
            self.nextRightImage = nil
            
            if nextLeftImage == nil {
                print("Warning: Landscape image not in cache: \(asset.localIdentifier)")
            }
            
            completion?()
        }
    }

    // Check if the asset is portrait
    func isPortrait(asset: PHAsset) -> Bool {
        return asset.pixelHeight > asset.pixelWidth
    }

    // Helper view to display an image with specified width
    func imageView(image: UIImage?, width: CGFloat) -> some View {
        Image(uiImage: image ?? UIImage())
            .resizable()
            .scaledToFill()
            .frame(width: width, height: UIScreen.main.bounds.height, alignment: .center)
            .clipped()
    }

    func formatDate(_ date1: Date, _ date2: Date? = nil) -> String? {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        
        // If date2 is nil or if date1 and date2 are the same, return the formatted single date
        if date2 == nil || date1 == date2 {
            return formatter.string(from: date1)
        }
        
        // If date1 and date2 are different, format and return "date1 / date2"
        return "\(formatter.string(from: date1)) / \(formatter.string(from: date2!))"
    }
    
    func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    func getCurrentSlideNumber() -> Int {
        return currentImageIndex + 1
    }

    func updateLocationForCurrentImage() {
        // Cancel any pending geocoding
        currentGeocoder?.cancelGeocode()
        
        guard currentImageIndex < photoAssets.count else {
            locationName = nil
            return
        }
        
        guard let location = photoAssets[currentImageIndex].location else {
            locationName = nil
            return
        }
        
        // Set loading state
        locationName = "Loading..."
        
        currentGeocoder = CLGeocoder()
        currentGeocoder?.reverseGeocodeLocation(location) { placemarks, error in
            DispatchQueue.main.async {
                
                // Check if this is still the current image (user might have moved on)
                guard self.currentImageIndex < self.photoAssets.count,
                      self.photoAssets[self.currentImageIndex].location?.coordinate.latitude == location.coordinate.latitude,
                      self.photoAssets[self.currentImageIndex].location?.coordinate.longitude == location.coordinate.longitude else {
                    return // Ignore outdated results
                }
                
                guard let place = placemarks?.first, error == nil else {
                    self.locationName = nil
                    return
                }
                
                // Create a string from the placemark
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
            }
        }
        
        // Add timeout to prevent indefinite "Loading..."
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
            if self.locationName == "Loading..." {
                self.locationName = nil
            }
        }
    }

    // Helper function to log image details
    private func logImageDetails(for index: Int) {
        guard index < photoAssets.count else { return }
        
        let asset = photoAssets[index]
        
        print("=== Setting Current Images ===")
        print("Left Image - Index: \(index)")
        print("  Filename: \(asset.value(forKey: "filename") ?? "Unknown")")
        print("  Creation Date: \(asset.creationDate?.description ?? "Unknown")")
        print(" Custom Date: \(asset.customDate.description ?? "Unknown")")
        print("  Dimensions: \(asset.pixelWidth) x \(asset.pixelHeight)")
        print("  Duration: \(asset.duration) seconds")
        print("  Media Type: \(asset.mediaType.rawValue == 1 ? "Image" : "Video")")
        print("  Local Identifier: \(asset.localIdentifier)")
        
        if let location = asset.location {
            print("  Location: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        } else {
            print("  Location: None")
        }
        
        // If we're in portrait mode with two images, log the right image too
        if isPortrait(asset: asset), index + 1 < photoAssets.count {
            let rightAsset = photoAssets[index + 1]
            print("Right Image - Index: \(index + 1)")
            print("  Filename: \(rightAsset.value(forKey: "filename") ?? "Unknown")")
            print("  Creation Date: \(rightAsset.creationDate?.description ?? "Unknown")")
            print(" Custom Date: \(rightAsset.customDate.description ?? "Unknown")")
            print("  Dimensions: \(rightAsset.pixelWidth) x \(rightAsset.pixelHeight)")
            print("  Duration: \(rightAsset.duration) seconds")
            print("  Media Type: \(rightAsset.mediaType.rawValue == 1 ? "Image" : "Video")")
            print("  Local Identifier: \(rightAsset.localIdentifier)")
            
            if let location = rightAsset.location {
                print("  Location: \(location.coordinate.latitude), \(location.coordinate.longitude)")
            } else {
                print("  Location: None")
            }
        }
        print("============================")
    }

    // Helper function to clean up old images and free memory
    private func cleanupOldImages() {
        // Allow previous images to be deallocated
        currentLeftImage = nil
        currentRightImage = nil
    }

}
