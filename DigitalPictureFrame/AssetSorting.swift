//
//  AssetSorting.swift
//  DigitalPictureFrame
//
//  Created by Andrew Hill on 10/09/2024.
//

import Foundation
import Photos

extension PHAsset {
    // Computed property that attempts to extract a custom date from the filename or falls back to creationDate
    var customDate: Date {
        if let filename = self.filename, let dateFromFilename = extractDateFromFilename(filename) {
            return dateFromFilename
        } else {
            return self.creationDate ?? Date.distantPast
        }
    }
    
    // Helper to retrieve the filename of the asset
    var filename: String? {
        let resources = PHAssetResource.assetResources(for: self)
        return resources.first?.originalFilename
    }
    
    // Helper function to extract date from filename in YYYYMMDD format
    private func extractDateFromFilename(_ filename: String) -> Date? {
        let regexPattern = "\\b(\\d{8})([-_\\.])"
        let regex = try? NSRegularExpression(pattern: regexPattern)
        
        if let match = regex?.firstMatch(in: filename, range: NSRange(filename.startIndex..., in: filename)),
           let dateRange = Range(match.range(at: 1), in: filename) {
            
            let dateString = String(filename[dateRange])
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyyMMdd"
            
            return dateFormatter.date(from: dateString)
        }
        return nil
    }
    // Computed property to check if customDate has the default time of 00:00:00
    var hasDefaultTime: Bool {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute, .second], from: self.customDate)
        return components.hour == 0 && components.minute == 0 && components.second == 0
    }
}

func processAssets(assets: PHFetchResult<PHAsset>) -> [PHAsset] {
    let filteredAssets = filterDuplicates(assets: assets)

    let timeframedAssets = restrictToTimeFrame(assets: filteredAssets)

    // Step 1: Separate into landscape and portrait
    let (landscape, portrait) = separateAssets(assets: timeframedAssets)

    // Step 2: Group portraits into pairs by date
    let portraitPairs = groupPortraits(assets: portrait)

    // Step 3: Shuffle portrait pairs and landscapes with bias
    let biasedPortraitPairs = biasAssets(assets: portraitPairs)
    let biasedLandscapes = biasAssets(assets: landscape.map { [$0] }).flatMap { $0 }

    // Step 4: Interleave the biased portrait pairs and landscapes
    return interleavePortraitsAndLandscapes(portraits: biasedPortraitPairs, landscapes: biasedLandscapes)
}

// New function to print a timeline of assets grouped by month and year
func printTimeline(assets: PHFetchResult<PHAsset>) {
    // Dictionary to store counts by year and month
    var timelineCounts: [DateComponents: Int] = [:]
    let calendar = Calendar.current

    // Process each asset
    assets.enumerateObjects { (asset, _, _) in
        // Extract year and month from creationDate
        let components = calendar.dateComponents([.year, .month], from: asset.customDate)
        
        // Increment count for the respective month and year
        if let existingCount = timelineCounts[components] {
            timelineCounts[components] = existingCount + 1
        } else {
            timelineCounts[components] = 1
        }
    }

    // Sort by year and month
    let sortedTimeline = timelineCounts.sorted {
        if $0.key.year == $1.key.year {
            return $0.key.month ?? 0 < $1.key.month ?? 0
        }
        return $0.key.year ?? 0 < $1.key.year ?? 0
    }

    // Print the timeline in the desired format
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "MMM"

    for (components, count) in sortedTimeline {
        if let year = components.year, let month = components.month {
            let monthName = dateFormatter.monthSymbols[month - 1] // Get month name
            print("\(year) – \(monthName) – \(count)")
        }
    }
}


// 0
func filterDuplicates(assets: PHFetchResult<PHAsset>) -> [PHAsset] {
    var uniqueDates = Set<Date>()
    var uniqueFilenames = Set<String>()
    var filteredAssets = [PHAsset]()

    assets.enumerateObjects { (asset, _, _) in
        guard let filename = asset.value(forKey: "filename") as? String else {
            return
        }
        
        // If there's no time component or if the date is unique, proceed
        if asset.hasDefaultTime || !uniqueDates.contains(asset.customDate) {
            // Check if the filename is unique
            if !uniqueFilenames.contains(filename) {
                uniqueDates.insert(asset.customDate)
                uniqueFilenames.insert(filename)
                filteredAssets.append(asset)
            }
        }
    }
    return filteredAssets
}

func restrictToTimeFrame(assets: [PHAsset]) -> [PHAsset] {
    return assets.filter { !$0.hasDefaultTime }
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
    let calendar = Calendar.current
    let currentMonth = calendar.component(.month, from: Date())

    // Define acceptable months (previous, current, and next)
    let previousMonth = currentMonth == 1 ? 12 : currentMonth - 1
    let nextMonth = currentMonth == 12 ? 1 : currentMonth + 1
    let validMonths = [previousMonth, currentMonth, nextMonth]
    
    if !UserDefaults.standard.bool(forKey: "filter_seasonal_photos") {
        return assets
    }
    
    // Filter assets to only include those within ±1 month of the current month
    let filteredAssets = assets.filter {
        let assetMonth = calendar.component(.month, from: $0.customDate)
        return validMonths.contains(assetMonth)
    }
    
    // Sort the filtered assets by customDate
    return filteredAssets.sorted { $0.customDate < $1.customDate }
}

//2.3
func isWithinTimeFrame(_ asset1: PHAsset, _ asset2: PHAsset, minutes: Int) -> Bool {
    return abs(asset1.customDate.timeIntervalSince(asset2.customDate)) <= Double(minutes * 60)
}


//2.4
func isSameDay(_ asset1: PHAsset, _ asset2: PHAsset) -> Bool {
    let calendar = Calendar.current
    return calendar.isDate(asset1.customDate, inSameDayAs: asset2.customDate)
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
        if StorageManager.shared.getLastSeenTime(assetId: assetGroup.first?.localIdentifier) != nil {
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


