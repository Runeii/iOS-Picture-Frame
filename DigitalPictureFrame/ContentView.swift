import SwiftUI
import Photos
import UIKit

struct ContentView: View {
    @Binding var photoAssets: [PHAsset]
    @Binding var currentImageIndex: Int

    var onSlideDisplayed: (Int) -> Void

    @State private var displayImageIndex: Int = 0;

    @State private var currentLeftImage: UIImage? = nil
    @State private var currentRightImage: UIImage? = nil
    @State private var nextLeftImage: UIImage? = nil
    @State private var nextRightImage: UIImage? = nil
    @State private var fadeProgress: Double = 1.0

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
            // Text indicator for the current slide index
            Text("Slide \(displayImageIndex + 1) of \(photoAssets.count)")
                .font(.caption) // Customize the font as needed
                .padding([.leading, .bottom], 16) // Padding to offset from bottom left corner
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .onAppear {
            displayImageIndex = currentImageIndex // Initialize display index
            if displayImageIndex >= 0 {
                loadImages(for: displayImageIndex)
            }
        }
        .onChange(of: currentImageIndex) { newIndex in
            crossfadeToNewImage(for: newIndex)
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
}
