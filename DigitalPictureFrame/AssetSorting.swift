//
//  AssetSorting.swift
//  DigitalPictureFrame
//
//  Created by Andrew Hill on 10/09/2024.
//

import Foundation
import Photos

func processAssets(assets: PHFetchResult<PHAsset>) -> [PHAsset] {
    let biasStrength = 0.6
    
    let filteredAssets = filterDuplicates(assets: assets)

    // Step 1: Separate into landscape and portrait
    let (landscape, portrait) = separateAssets(assets: filteredAssets)

    // Step 2: Group portraits into pairs by date
    let portraitPairs = groupPortraits(assets: portrait)

    // Step 3: Shuffle portrait pairs and landscapes with bias
    let biasedPortraitPairs = biasAssets(assets: portraitPairs)
    let biasedLandscapes = biasAssets(assets: landscape.map { [$0] }).flatMap { $0 }

    // Step 4: Interleave the biased portrait pairs and landscapes
    return interleavePortraitsAndLandscapes(portraits: biasedPortraitPairs, landscapes: biasedLandscapes)
}

// 0
func filterDuplicates(assets: PHFetchResult<PHAsset>) -> [PHAsset] {
    var uniqueDates = Set<Date>()
    var filteredAssets = [PHAsset]()

    assets.enumerateObjects { (asset, _, _) in
        if let creationDate = asset.creationDate, !uniqueDates.contains(creationDate) {
            uniqueDates.insert(creationDate)
            filteredAssets.append(asset)
        }
    }
    return filteredAssets
}


// 1
func separateAssets(assets: [PHAsset]) -> (landscape: [PHAsset], portrait: [PHAsset]) {
    let landscapeAssets = assets.filter { $0.pixelWidth > $0.pixelHeight }
    let portraitAssets = assets.filter { $0.pixelWidth <= $0.pixelHeight }
    
    return (landscape: landscapeAssets, portrait: portraitAssets)
}

// 2.1
func groupPortraits(assets: [PHAsset]) -> [[PHAsset]] {
    let sortedAssets = sortAssetsByDate(assets: assets)
    var groupedAssets = [[PHAsset]]()
    var remainingAssets = [PHAsset]()

    // First pass: Try to form pairs based on the given criteria
    var i = 0
    while i < sortedAssets.count {
        if i + 1 < sortedAssets.count {
            let asset = sortedAssets[i]
            let nextAsset = sortedAssets[i + 1]
            if isWithinTimeFrame(asset, nextAsset, minutes: 2) || isSameDay(asset, nextAsset) {
                groupedAssets.append([asset, nextAsset])
                i += 2 // Skip the next asset since it's already paired
                continue
            }
        }
        remainingAssets.append(sortedAssets[i])
        i += 1
    }

    // Second pass: Handle any remaining assets by shuffling and forming pairs
    remainingAssets.shuffle()
    var finalGroups = groupedAssets
    var j = 0
    while j < remainingAssets.count - 1 { // Ensure there's at least one more asset to form a pair
        finalGroups.append([remainingAssets[j], remainingAssets[j + 1]])
        j += 2
    }

    // Any leftover single asset is discarded, as per requirements
    return finalGroups
}

// 2.2
func sortAssetsByDate(assets: [PHAsset]) -> [PHAsset] {
    return assets.sorted { $0.creationDate ?? Date.distantPast < $1.creationDate ?? Date.distantPast }
}


//2.3
func isWithinTimeFrame(_ asset1: PHAsset, _ asset2: PHAsset, minutes: Int) -> Bool {
    guard let date1 = asset1.creationDate, let date2 = asset2.creationDate else { return false }
    return abs(date1.timeIntervalSince(date2)) <= Double(minutes * 60)
}


//2.4
func isSameDay(_ asset1: PHAsset, _ asset2: PHAsset) -> Bool {
    let calendar = Calendar.current
    guard let date1 = asset1.creationDate, let date2 = asset2.creationDate else { return false }
    return calendar.isDate(date1, inSameDayAs: date2)
}

//3.1
func biasAssets(assets: [[PHAsset]]) -> [[PHAsset]] {
    let recencyBiasStrength: Double = 0.8
    let seasonBiasStrength: Double = 0.5
    
    let currentMonth = Calendar.current.component(.month, from: Date())
    let currentYear = Calendar.current.component(.year, from: Date())

    // Categorize assets based on whether they have been seen before
    var neverSeenAssets: [[PHAsset]] = []
    var seenAssets: [[PHAsset]] = []

    for assetGroup in assets {
        if let dateLastSeen = StorageManager.shared.getLastSeenTime(assetId: assetGroup.first?.localIdentifier) {
            seenAssets.append(assetGroup)
        } else {
            neverSeenAssets.append(assetGroup)
        }
    }

    // Shuffle the never seen before assets randomly
    neverSeenAssets.shuffle()

    // Shuffle and bias the seen assets
    seenAssets.shuffle()
    seenAssets.sort { group1, group2 in
        let dateLastSeen1 = StorageManager.shared.getLastSeenTime(assetId: group1.first?.localIdentifier)!
        let dateLastSeen2 = StorageManager.shared.getLastSeenTime(assetId: group2.first?.localIdentifier)!
        let assetMonth1 = Calendar.current.component(.month, from: dateLastSeen1)
        let assetMonth2 = Calendar.current.component(.month, from: dateLastSeen2)
        let assetYear1 = Calendar.current.component(.year, from: dateLastSeen1)
        let assetYear2 = Calendar.current.component(.year, from: dateLastSeen2)

        let olderBias1 = dateLastSeen1 < dateLastSeen2 ? recencyBiasStrength : 0
        let olderBias2 = dateLastSeen2 < dateLastSeen1 ? recencyBiasStrength : 0
        let seasonBias1 = (assetMonth1 == currentMonth && assetYear1 < currentYear) ? seasonBiasStrength : 0
        let seasonBias2 = (assetMonth2 == currentMonth && assetYear2 < currentYear) ? seasonBiasStrength : 0

        return olderBias1 + seasonBias1 > olderBias2 + seasonBias2
    }

    // Append the previously seen to the end of the never before seen
    return neverSeenAssets + seenAssets
}

// 4
func interleavePortraitsAndLandscapes(portraits: [[PHAsset]], landscapes: [PHAsset]) -> [PHAsset] {
    var interleaved = [PHAsset]()
    var portraitIndex = 0
    var landscapeIndex = 0

    let totalPortraits = portraits.count
    let totalLandscapes = landscapes.count
    
    // Alternate between portrait pairs and landscapes, but ensure we don't run out prematurely
    while portraitIndex < totalPortraits || landscapeIndex < totalLandscapes {
        if portraitIndex < totalPortraits {
            // Append portrait pairs only (discard single portraits)
            let portraitPair = portraits[portraitIndex]
            if portraitPair.count == 2 {
                interleaved.append(contentsOf: portraitPair)
            }
            portraitIndex += 1
        }
        
        if landscapeIndex < totalLandscapes {
            // Append a landscape image
            interleaved.append(landscapes[landscapeIndex])
            landscapeIndex += 1
        }
    }

    // No need to handle leftover portrait, as we are discarding any single portraits

    return interleaved
}


