//
//  AlbumSelectionView.swift
//  DigitalPictureFrame
//
//  Created by Andrew Hill on 21/12/2024.
//

import Photos
import SwiftUI

struct AlbumSelectionView: View {
    @Binding var selectedAlbum: PHAssetCollection?
    @State private var albums: [PHAssetCollection] = []
    
    var body: some View {
        NavigationView {
            List(albums, id: \.localIdentifier) { album in
                Button(action: {
                    self.selectedAlbum = album
                    UserDefaults.standard.set(album.localIdentifier, forKey: "selectedAlbumId")
                }) {
                    HStack {
                        Text(album.localizedTitle ?? "Untitled Album")
                        Spacer()
                        if album.localIdentifier == selectedAlbum?.localIdentifier {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            .navigationTitle("Select Album")
            .onAppear(perform: fetchAlbums)
        }
    }
    
    private func fetchAlbums() {
        let options = PHFetchOptions()
        let userAlbums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: options)
        let sharedAlbums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumCloudShared, options: options)
        
        var allAlbums: [PHAssetCollection] = []
        userAlbums.enumerateObjects { (collection, _, _) in
            allAlbums.append(collection)
        }
        sharedAlbums.enumerateObjects { (collection, _, _) in
            allAlbums.append(collection)
        }
        
        self.albums = allAlbums
    }
}
