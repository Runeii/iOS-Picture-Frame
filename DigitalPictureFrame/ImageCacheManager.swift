import Foundation
import Photos
import UIKit

class ImageCacheManager: ObservableObject {
    static let shared = ImageCacheManager()
    
    private var downloadQueue = DispatchQueue(label: "imageDownloadQueue", qos: .utility)
    private var isCaching = false
    
    @Published var cachingProgress: Float = 0.0
    @Published var isCachingComplete = false
    
    // Disk cache directory
    private let diskCacheURL: URL = {
        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        let cacheURL = paths[0].appendingPathComponent("ImageCache")
        try? FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)
        return cacheURL
    }()
    
    private init() {}
    
    // Helper to sanitize asset identifiers for filenames
    private func sanitizedFilename(for assetId: String) -> String {
        // Remove all invalid filename characters
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|")
        return assetId.components(separatedBy: invalid).joined(separator: "_")
    }
    
    // Pre-download all images for offline use
    func preloadImages(assets: [PHAsset], completion: @escaping () -> Void) {
        guard !isCaching else { return }
        isCaching = true
        isCachingComplete = false
        cachingProgress = 0.0
        
        let totalAssets = assets.count
        var completedAssets = 0
        
        print("Starting pre-cache of \(totalAssets) images to disk...")
        
        downloadQueue.async {
            let group = DispatchGroup()
            
            for (index, asset) in assets.enumerated() {
                group.enter()
                
                // Check if already cached on disk
                if self.isImageCachedOnDisk(for: asset.localIdentifier) {
                    completedAssets += 1
                    DispatchQueue.main.async {
                        self.cachingProgress = Float(completedAssets) / Float(totalAssets)
                        if completedAssets % 10 == 0 || completedAssets == totalAssets {
                            print("Cached \(completedAssets)/\(totalAssets) images (\(Int(self.cachingProgress * 100))%)")
                        }
                    }
                    group.leave()
                    continue
                }
                
                let targetSize: CGSize
                let scale: CGFloat = 3.0
                let screenPixelSize = CGSize(
                    width: UIScreen.main.bounds.width * UIScreen.main.scale * scale,
                    height: UIScreen.main.bounds.height * UIScreen.main.scale * scale
                )
                
                if asset.pixelHeight > asset.pixelWidth {
                    targetSize = CGSize(width: screenPixelSize.width / 2, height: screenPixelSize.height)
                } else {
                    targetSize = screenPixelSize
                }
                
                self.downloadAndCacheImageToDisk(asset: asset, targetSize: targetSize) { success in
                    completedAssets += 1
                    DispatchQueue.main.async {
                        self.cachingProgress = Float(completedAssets) / Float(totalAssets)
                        if completedAssets % 10 == 0 || completedAssets == totalAssets {
                            print("Cached \(completedAssets)/\(totalAssets) images (\(Int(self.cachingProgress * 100))%)")
                        }
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
                let stats = self.getCacheStats()
                print("Image pre-caching complete! Cached \(stats.count) images on disk (\(stats.diskSize))")
                completion()
            }
        }
    }
    private func downloadAndCacheImageToDisk(asset: PHAsset, targetSize: CGSize, completion: @escaping (Bool) -> Void) {
        let imageManager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .highQualityFormat
        options.version = .current
        options.isNetworkAccessAllowed = true
        
        // Create sanitized filename
        let filename = self.sanitizedFilename(for: asset.localIdentifier)
        let fileURL = self.diskCacheURL.appendingPathComponent("\(filename).jpg")
        
        // Request image data directly (not UIImage) to avoid memory allocation
        imageManager.requestImageDataAndOrientation(for: asset, options: options) { imageData, dataUTI, orientation, info in
            guard let imageData = imageData else {
                print("Failed to load image data for asset: \(asset.localIdentifier)")
                completion(false)
                return
            }
            
            do {
                // Write raw image data directly to disk
                try imageData.write(to: fileURL)
                completion(true)
            } catch {
                print("Failed to write image to disk: \(error)")
                print("Attempted path: \(fileURL.path)")
                completion(false)
            }
        }
    }
    // Get cached image from disk
    func getCachedImage(for assetId: String) -> UIImage? {
        let filename = sanitizedFilename(for: assetId)
        let fileURL = diskCacheURL.appendingPathComponent("\(filename).jpg")
        return UIImage(contentsOfFile: fileURL.path)
    }
    
    // Check if image is cached on disk
    func isImageCached(for assetId: String) -> Bool {
        return isImageCachedOnDisk(for: assetId)
    }
    
    private func isImageCachedOnDisk(for assetId: String) -> Bool {
        let filename = sanitizedFilename(for: assetId)
        let fileURL = diskCacheURL.appendingPathComponent("\(filename).jpg")
        return FileManager.default.fileExists(atPath: fileURL.path)
    }
    
    // Incremental cache update - only cache missing images
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
        preloadImages(assets: uncachedAssets, completion: completion)
    }
    
    // Remove images from cache that are no longer in the asset list
    func cleanupRemovedAssets(currentAssets: [PHAsset]) {
        let currentAssetIds = Set(currentAssets.map { $0.localIdentifier })
        let sanitizedCurrentIds = Set(currentAssetIds.map { sanitizedFilename(for: $0) })
        
        var removedCount = 0
        
        // Clean disk cache
        if let diskFiles = try? FileManager.default.contentsOfDirectory(at: diskCacheURL, includingPropertiesForKeys: nil) {
            for fileURL in diskFiles {
                let filename = fileURL.deletingPathExtension().lastPathComponent
                if !sanitizedCurrentIds.contains(filename) {
                    try? FileManager.default.removeItem(at: fileURL)
                    removedCount += 1
                }
            }
        }
        
        if removedCount > 0 {
            print("Cleaned up \(removedCount) removed images from cache")
        }
    }
    
    // Clear cache
    func clearCache() {
        try? FileManager.default.removeItem(at: diskCacheURL)
        try? FileManager.default.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
        isCachingComplete = false
        cachingProgress = 0.0
        print("Image cache cleared")
    }
    
    // Get cache statistics
    func getCacheStats() -> (count: Int, diskSize: String) {
        var diskCount = 0
        var totalBytes: Int64 = 0
        
        if let diskFiles = try? FileManager.default.contentsOfDirectory(at: diskCacheURL, includingPropertiesForKeys: [.fileSizeKey]) {
            diskCount = diskFiles.count
            for fileURL in diskFiles {
                if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                   let fileSize = resourceValues.fileSize {
                    totalBytes += Int64(fileSize)
                }
            }
        }
        
        let mb = Double(totalBytes) / (1024 * 1024)
        let diskSize = String(format: "%.1f MB", mb)
        
        return (diskCount, diskSize)
    }
}