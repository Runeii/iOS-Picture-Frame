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
    
    @State private var locationName: String = "Loading..."
    
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
            if let currentLeftImage = currentLeftImage {
                VStack(alignment: .leading) {
                    Spacer()
                    Text("Slide \(displayImageIndex + 1) of \(photoAssets.count)")
                        .padding(.bottom, 2)
                    Text("Date taken: \(formatDate(photoAssets[currentImageIndex].creationDate))")
                        .padding(.bottom, 2)
                    Text("Location: \(locationName)")
                        .onAppear() { updatePlace() }
                        .onChange(of: currentImageIndex) { index in
                            updatePlace()
                        }
                }.font(.caption) // Customize the font as needed
                    .opacity(isUserTouching ? 1.0 : 0.0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding([.leading, .bottom], 16)
            }
        }
        .onAppear {
            displayImageIndex = currentImageIndex // Initialize display index
            if displayImageIndex >= 0 {
                loadImages(for: displayImageIndex)
            }
        }
        .onChange(of: currentImageIndex) { newIndex in
            crossfadeToNewImage(for: newIndex)
            
            self.locationName = "Loading..."
        }
    }

    // Function to handle crossfade to the new image(s)
    func crossfadeToNewImage(for newIndex: Int) {
        loadImages(for: newIndex) { // Load new images (both portrait and landscape cases)
            // Start crossfade animation
            withAnimation(.easeInOut(duration: 1.0)) {
                self.fadeProgress = 0.0 // Crossfade from current to next images
            }
            
            // After the crossfade is complete, switch images
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
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

    // Helper function to load both portrait and landscape images
    func loadImages(for index: Int, completion: (() -> Void)? = nil) {
        let targetSize = CGSize(width: UIScreen.main.bounds.width / 2, height: UIScreen.main.bounds.height)

        if isPortrait(asset: photoAssets[index]), index + 1 < photoAssets.count {
            // Load two portrait images side by side
            loadImage(for: photoAssets[index], targetSize: targetSize) { image in
                self.nextLeftImage = image
                if let _ = self.nextRightImage {
                    completion?()
                }
            }

            loadImage(for: photoAssets[index + 1], targetSize: targetSize) { image in
                self.nextRightImage = image
                if let _ = self.nextLeftImage {
                    completion?()
                }
            }
        } else {
            // Load a single landscape image
            loadImage(for: photoAssets[index], targetSize: UIScreen.main.bounds.size) { image in
                self.nextLeftImage = image
                self.nextRightImage = nil // Reset right image since it's landscape
                completion?()
            }
        }
    }

    // Check if the asset is portrait
    func isPortrait(asset: PHAsset) -> Bool {
        return asset.pixelHeight > asset.pixelWidth
    }

    // Helper function to load an image for a PHAsset
    func loadImage(for asset: PHAsset, targetSize: CGSize, handler: @escaping (UIImage?) -> Void) {
        let imageManager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .highQualityFormat  // Continue with high-quality format
        options.resizeMode = .none  // Avoid resizing to preserve quality
        options.version = .current  // Fetch the current version of the image
        options.isNetworkAccessAllowed = true  // Allow accessing images from iCloud

        imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            handler(image)
        }
    }

    // Helper view to display an image with specified width
    func imageView(image: UIImage?, width: CGFloat) -> some View {
        Image(uiImage: image ?? UIImage())
            .resizable()
            .scaledToFill()
            .frame(width: width, height: UIScreen.main.bounds.height, alignment: .center)
            .clipped()
    }
    
    func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "Unknown" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    func updatePlace() {
        guard let location = self.photoAssets[self.currentImageIndex].location else {
            self.locationName = "No location"
            return
        }
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            guard let place = placemarks?.first, error == nil else {
                self.locationName = "Unknown"
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
            
            self.locationName = placeName.isEmpty ? "Unknown" : placeName
        }
    }

}
