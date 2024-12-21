import UIKit
import Photos

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    let folderSelectionManager = FolderSelectionManager()

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        self.window = UIWindow(frame: UIScreen.main.bounds)
        registerSettingsDefaults()

        let resetKey = "reset_selected_folder"
        if UserDefaults.standard.bool(forKey: resetKey) {
            // Reset the selected folder
            UserDefaults.standard.removeObject(forKey: "SelectedSharedFolderIdentifier")
            
            // Reset the toggle to off (so it doesn't reset repeatedly)
            UserDefaults.standard.set(false, forKey: resetKey)
            
            print("Selected folder identifier reset.")
        }
        
        // Set a placeholder root view controller
        let placeholderViewController = UIViewController()
        placeholderViewController.view.backgroundColor = .black // Neutral background
        self.window?.rootViewController = placeholderViewController
        self.window?.makeKeyAndVisible()
        
        requestPhotoLibraryPermission()
        return true
    }

    private func requestPhotoLibraryPermission() {
        PHPhotoLibrary.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                switch status {
                case .authorized:
                    self.showFolderPicker()
                default:
                    self.showPermissionDeniedAlert()
                }
            }
        }
    }

    private func showFolderPicker() {
        guard let window = self.window else { return }
        
        // Create a temporary root view controller for the folder picker
        let folderPickerViewController = UIViewController()
        folderPickerViewController.view.backgroundColor = .black
        window.rootViewController = folderPickerViewController
        
        // Present folder selection
        folderSelectionManager.ensureFolderSelected(from: folderPickerViewController) { [weak self] in
            self?.showSlideshow()
        }
    }

    private func showSlideshow() {
        guard let window = self.window else { return }
        
        // Replace root view controller with the slideshow
        let slideshowViewController = DigitalPictureFrameViewController()
        UIView.transition(with: window, duration: 0.5, options: .transitionCrossDissolve, animations: {
                window.rootViewController = slideshowViewController
            }) { _ in
                // Perform long-running task on a background thread after the transition completes
                DispatchQueue.global(qos: .userInitiated).async {
                    slideshowViewController.fetchPhotosFromAlbum()
                }
            }
    }

    private func showPermissionDeniedAlert() {
        guard let window = self.window else { return }
        
        let permissionDeniedViewController = UIViewController()
        permissionDeniedViewController.view.backgroundColor = .white
        window.rootViewController = permissionDeniedViewController
        
        let alertController = UIAlertController(
            title: "Access Denied",
            message: "Permission to access the photo library was denied. Please enable it in settings to use this app.",
            preferredStyle: .alert
        )
        alertController.addAction(UIAlertAction(title: "OK", style: .default))
        
        permissionDeniedViewController.present(alertController, animated: true)
    }
    
    func registerSettingsDefaults() {
        if let settingsURL = Bundle.main.url(forResource: "Settings", withExtension: "bundle"),
           let settingsDict = NSDictionary(contentsOf: settingsURL.appendingPathComponent("Root.plist")),
           let preferences = settingsDict["PreferenceSpecifiers"] as? [[String: Any]] {

            var defaults: [String: Any] = [:]

            for preference in preferences {
                if let key = preference["Key"] as? String, let defaultValue = preference["DefaultValue"] {
                    defaults[key] = defaultValue
                }
            }

            UserDefaults.standard.register(defaults: defaults)
        }
    }
}
