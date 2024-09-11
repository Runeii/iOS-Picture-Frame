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
    let biasedPortraitPairs = biasAssets(assets: portraitPairs, biasStrength: biasStrength)
    let biasedLandscapes = biasAssets(assets: landscape.map { [$0] }, biasStrength: biasStrength).flatMap { $0 }

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
func sortAssetsByDate(assets: [PHAsset]) -> [PHAsset] {
    return assets.sorted { (asset1, asset2) -> Bool in
        guard let date1 = asset1.creationDate, let date2 = asset2.creationDate else { return false }
        return date1 > date2
    }
}

// 2.2
func groupPortraits(assets: [PHAsset]) -> [[PHAsset]] {
    let sortedAssets = sortAssetsByDate(assets: assets) // Sort by date first

    guard sortedAssets.count > 1 else { return sortedAssets.map { [$0] } }

    let groupedAssets = sortedAssets.reduce(into: [[PHAsset]]()) { result, asset in
        if let lastGroup = result.last, let lastAsset = lastGroup.last, isWithinTimeFrame(asset, lastAsset, minutes: 2) {
            result[result.count - 1].append(asset)
        } else if let lastGroup = result.last, let lastAsset = lastGroup.last, isSameDay(asset, lastAsset) {
            result[result.count - 1].append(asset)
        } else {
            result.append([asset])
        }
    }
    
    return groupedAssets
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
func biasAssets(assets: [[PHAsset]], biasStrength: Double) -> [[PHAsset]] {
    // Separate bias strengths for recency and seasonality
    let recencyBiasStrength = 0.7
    let seasonBiasStrength = 0.5
    let currentSeason = getCurrentSeason()

    return assets.shuffled().sorted { assetGroup1, assetGroup2 in
        let dateAdded1 = assetGroup1.first?.modificationDate ?? Date.distantPast
        let dateAdded2 = assetGroup2.first?.modificationDate ?? Date.distantPast

        let isRecent1 = isRecent(date: dateAdded1)
        let isRecent2 = isRecent(date: dateAdded2)

        let isInCurrentSeason1 = isInCurrentSeason(assetGroup1, season: currentSeason)
        let isInCurrentSeason2 = isInCurrentSeason(assetGroup2, season: currentSeason)

        // Apply recency bias and seasonal bias (only for previous years' images)
        let currentYear = Calendar.current.component(.year, from: Date())
        let assetYear1 = Calendar.current.component(.year, from: assetGroup1.first?.creationDate ?? Date.distantPast)
        let assetYear2 = Calendar.current.component(.year, from: assetGroup2.first?.creationDate ?? Date.distantPast)

        let recencyBias1 = isRecent1 ? recencyBiasStrength : 0
        let recencyBias2 = isRecent2 ? recencyBiasStrength : 0

        let seasonBias1 = (assetYear1 < currentYear && isInCurrentSeason1) ? seasonBiasStrength : 0
        let seasonBias2 = (assetYear2 < currentYear && isInCurrentSeason2) ? seasonBiasStrength : 0

        // Calculate total bias
        let totalBias1 = recencyBias1 * biasStrength + seasonBias1 * biasStrength
        let totalBias2 = recencyBias2 * biasStrength + seasonBias2 * biasStrength

        // Add some randomness to the bias to allow for shuffling feel
        let randomFactor1 = Double.random(in: 0...1)
        let randomFactor2 = Double.random(in: 0...1)

        // Combine bias and randomness to get a final "weighted" score
        let finalScore1 = totalBias1 + (1 - biasStrength) * randomFactor1
        let finalScore2 = totalBias2 + (1 - biasStrength) * randomFactor2

        // Sort based on the final score
        return finalScore1 > finalScore2
    }
}

// Modify the recency function to check if an asset was added to the album in the last week
func isRecent(date: Date) -> Bool {
    let calendar = Calendar.current
    // Calculate the number of days since the asset was added to the album
    let daysSinceAdded = calendar.dateComponents([.day], from: date, to: Date()).day ?? Int.max
    return daysSinceAdded <= 7 // Consider recent if added in the last week
}

// Seasonal bias only for assets from previous years
func isInCurrentSeason(_ assets: [PHAsset], season: String) -> Bool {
    guard let creationDate = assets.first?.creationDate else { return false }
    let assetYear = Calendar.current.component(.year, from: creationDate)
    let currentYear = Calendar.current.component(.year, from: Date())

    if assetYear == currentYear {
        // No seasonal bias for current year images
        return false
    }

    let month = Calendar.current.component(.month, from: creationDate)
    switch season {
    case "Spring":
        return (3...5).contains(month)
    case "Summer":
        return (6...8).contains(month)
    case "Autumn":
        return (9...11).contains(month)
    case "Winter":
        return month == 12 || (1...2).contains(month)
    default:
        return false
    }
}

func getCurrentSeason() -> String {
    let month = Calendar.current.component(.month, from: Date())
    switch month {
    case 3...5:
        return "Spring"
    case 6...8:
        return "Summer"
    case 9...11:
        return "Autumn"
    default:
        return "Winter"
    }
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


