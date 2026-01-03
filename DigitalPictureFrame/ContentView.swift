import SwiftUI
import Photos
import UIKit
import CoreLocation

struct ContentView: View {
    @Binding var photoAssets: [PHAsset]
    @Binding var currentImageIndex: Int
    @Binding var isUserTouching: Bool

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
                            .padding(.bottom, 2)
                    }
                    if locationName != nil {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin.and.ellipse") // Location marker icon
                            Text(locationName!)
                        }.onAppear {
                            updatePlace()
                        }.onChange(of: currentImageIndex) { _ in
                            updatePlace()
                        }
                    }
                }.font(.body) // Customize the font as needed
                    .opacity(isUserTouching || UserDefaults.standard.bool(forKey: "always_show_labels") ? 1.0 : 0.0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding([.leading, .bottom], 16)
            }
        }
        .onAppear {
            print("currentImageIndex", currentImageIndex)
            displayImageIndex = currentImageIndex // Initialize display index
            if displayImageIndex >= 0 {
                print("displayImageIndex", displayImageIndex)
                loadImages(for: displayImageIndex)
            }
        }
        .onChange(of: currentImageIndex) { newIndex in
            crossfadeToNewImage(for: newIndex)
            
            self.locationName = "Loading..."
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

    func updatePlace() {
        // Cancel any pending geocoding
        currentGeocoder?.cancelGeocode()
        
        guard let location = self.photoAssets[self.currentImageIndex].location else {
            self.locationName = nil
            return
        }
        
        currentGeocoder = CLGeocoder()
        currentGeocoder?.reverseGeocodeLocation(location) { placemarks, error in
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
    
    // Helper function to clean up old images and free memory
    private func cleanupOldImages() {
        // Allow previous images to be deallocated
        currentLeftImage = nil
        currentRightImage = nil
    }

}
