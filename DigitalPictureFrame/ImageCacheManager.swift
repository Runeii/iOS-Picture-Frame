import Foundation
import Photos
import UIKit

class ImageCacheManager: ObservableObject {
    static let shared = ImageCacheManager()
    
    private var imageCache: [String: UIImage] = [:]
    private var downloadQueue = DispatchQueue(label: "imageDownloadQueue", qos: .utility)
    private var isCaching = false
    
    @Published var cachingProgress: Float = 0.0
    @Published var isCachingComplete = false
    
    private init() {}
    
    // Pre-download all images for offline use
    func preloadImages(assets: [PHAsset], completion: @escaping () -> Void) {
        guard !isCaching else { return }
        
        isCaching = true
        isCachingComplete = false
        cachingProgress = 0.0
        
        let totalAssets = assets.count
        var completedAssets = 0
        
        print("Starting pre-cache of \(totalAssets) images...")
        
        downloadQueue.async {
            let group = DispatchGroup()
            
            for (index, asset) in assets.enumerated() {
                group.enter()
                
                // Determine target size based on orientation
                let targetSize: CGSize
                if asset.pixelHeight > asset.pixelWidth {
                    // Portrait - half screen width
                    targetSize = CGSize(width: UIScreen.main.bounds.width / 2, height: UIScreen.main.bounds.height)
                } else {
                    // Landscape - full screen
                    targetSize = UIScreen.main.bounds.size
                }
                
                self.downloadAndCacheImage(asset: asset, targetSize: targetSize) { success in
                    completedAssets += 1
                    
                    DispatchQueue.main.async {
                        self.cachingProgress = Float(completedAssets) / Float(totalAssets)
                        print("Cached \(completedAssets)/\(totalAssets) images (\(Int(self.cachingProgress * 100))%)")
                    }
                    
                    group.leave()
                }
                
                // Add small delay to prevent overwhelming the system
                if index % 10 == 0 {
                    Thread.sleep(forTimeInterval: 0.1)
                }
            }
            
            group.wait()
            
            DispatchQueue.main.async {
                self.isCaching = false
                self.isCachingComplete = true
                print("Image pre-caching complete! Cached \(self.imageCache.count) images")
                completion()
            }
        }
    }
    
    // NEW: Incremental cache update - only cache missing images
    func updateCache(newAssets: [PHAsset], completion: @escaping () -> Void) {
        let uncachedAssets = newAssets.filter { !isImageCached(for: $0.localIdentifier) }
        
        if uncachedAssets.isEmpty {
            print("All images already cached - no update needed")
            DispatchQueue.main.async {
                completion()
            }
            return
        }
        
        print("Incrementally caching \(uncachedAssets.count) new images (out of \(newAssets.count) total)...")
        
        // Use the existing preloadImages method for the uncached assets
        preloadImages(assets: uncachedAssets, completion: completion)
    }
    
    // NEW: Remove images from cache that are no longer in the asset list
    func cleanupRemovedAssets(currentAssets: [PHAsset]) {
        let currentAssetIds = Set(currentAssets.map { $0.localIdentifier })
        let cachedAssetIds = Set(imageCache.keys)
        
        let removedAssetIds = cachedAssetIds.subtracting(currentAssetIds)
        
        if !removedAssetIds.isEmpty {
            print("Removing \(removedAssetIds.count) images from cache (no longer in album)")
            for removedId in removedAssetIds {
                imageCache.removeValue(forKey: removedId)
            }
        }
    }
    
    private func downloadAndCacheImage(asset: PHAsset, targetSize: CGSize, completion: @escaping (Bool) -> Void) {
        let imageManager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.version = .current
        options.isNetworkAccessAllowed = true // Allow iCloud downloads
        
        imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { image, info in
            if let image = image {
                // Cache the image
                self.imageCache[asset.localIdentifier] = image
                completion(true)
            } else {
                print("Failed to cache image for asset: \(asset.localIdentifier)")
                completion(false)
            }
        }
    }
    
    // Get cached image
    func getCachedImage(for assetId: String) -> UIImage? {
        return imageCache[assetId]
    }
    
    // Check if image is cached
    func isImageCached(for assetId: String) -> Bool {
        return imageCache[assetId] != nil
    }
    
    // Clear cache (for memory management)
    func clearCache() {
        imageCache.removeAll()
        isCachingComplete = false
        cachingProgress = 0.0
        print("Image cache cleared")
    }
    
    // Get cache statistics
    func getCacheStats() -> (count: Int, memoryUsage: String) {
        let count = imageCache.count
        
        // Estimate memory usage (rough calculation)
        var totalBytes = 0
        for image in imageCache.values {
            totalBytes += Int(image.size.width * image.size.height * 4) // 4 bytes per pixel (RGBA)
        }
        
        let mb = Double(totalBytes) / (1024 * 1024)
        let memoryUsage = String(format: "%.1f MB", mb)
        
        return (count, memoryUsage)
    }
}