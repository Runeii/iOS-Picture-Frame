//
//  StorageManager.swift
//  DigitalPictureFrame
//
//  Created by Andrew Hill on 11/09/2024.
//

import Foundation
import Foundation
import Photos

class StorageManager {
    static let shared = StorageManager()  // Singleton instance for global access

    private var storage: [String: Date] = [:]  // Dictionary to store asset IDs and dates

    // Method to store or update an asset's ID with the current date
    func storeOrUpdateAssetSeenTime(asset: PHAsset) {
        let assetID = asset.localIdentifier  // Get the unique identifier of the PHAsset
        storage[assetID] = Date()  // Store or update the date to now
    }

    // Method to get the date an asset was added, if available
    func getLastSeenTime(asset: PHAsset) -> Date? {
        let assetID = asset.localIdentifier
        return storage[assetID]
    }
}
