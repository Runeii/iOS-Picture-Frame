import UIKit
import Photos

class FolderSelectionManager: NSObject {
    private var completion: (() -> Void)?
    private weak var presentingViewController: UIViewController?

    // MARK: - Public Methods
    
    func ensureFolderSelected(from viewController: UIViewController, completion: @escaping () -> Void) {
        self.completion = completion
        self.presentingViewController = viewController
        
        print("Presenting view controller: \(presentingViewController)")
        let selectedFolderIdentifier = FolderSelectionManager.loadSelectedFolder()
        print("Selected Folder Identifier: \(selectedFolderIdentifier ?? "None")")

        if selectedFolderIdentifier == nil {
            DispatchQueue.main.async {
                self.promptUserToSelectFolder()
            }
        } else {
            completion()
        }
    }
    
    // MARK: - Private Methods
    
    private func promptUserToSelectFolder() {
        print("Prompting user to select an album...")
        // Fetch only user-created albums
        let fetchOptions = PHFetchOptions()
        let userAlbums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: fetchOptions)
            
        if userAlbums.count == 0 {
            let message = "No albums found. Please create an album and restart the app."
            let alertController = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
            alertController.addAction(UIAlertAction(title: "OK", style: .cancel, handler: nil))
            presentingViewController?.present(alertController, animated: true, completion: nil)
            return
        }

        let alertController = UIAlertController(
            title: "Select Album",
            message: "Please select an album for the digital picture frame.",
            preferredStyle: .alert
        )
        
        userAlbums.enumerateObjects { album, _, _ in
            alertController.addAction(UIAlertAction(title: album.localizedTitle, style: .default) { _ in
                FolderSelectionManager.saveSelectedFolder(identifier: album.localIdentifier)
                DispatchQueue.main.async {
                    self.showSuccessMessage()
                }
            })
        }
        
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        
        print("Prompted user to select an album...")
        presentingViewController?.present(alertController, animated: true, completion: nil)
    }
    
    private func showSuccessMessage() {
        let alertController = UIAlertController(
            title: "Album Selected",
            message: "The selected album has been saved for the digital picture frame.",
            preferredStyle: .alert
        )
        
        alertController.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            self.completion?()
        })
        
        presentingViewController?.present(alertController, animated: true, completion: nil)
    }
    
    // MARK: - Folder Persistence
    
    static let folderKey = "SelectedSharedFolderIdentifier"

    static func saveSelectedFolder(identifier: String) {
        UserDefaults.standard.set(identifier, forKey: folderKey)
    }

    static func clearSelectedFolder() {
        UserDefaults.standard.removeObject(forKey: folderKey)
    }

    static func loadSelectedFolder() -> String? {
        return UserDefaults.standard.string(forKey: folderKey)
    }
}



extension FolderSelectionManager: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        picker.dismiss(animated: true, completion: nil)
        
        if let assetURL = info[.referenceURL] as? URL {
            FolderSelectionManager.saveSelectedFolder(identifier: assetURL.absoluteString)
            DispatchQueue.main.async {
                self.showSuccessMessage()
            }
        }
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true, completion: nil)
    }
}
