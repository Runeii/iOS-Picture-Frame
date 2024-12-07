//
//  AppDelegate.swift
//  DigitalPictureFrame
//
//  Created by Andrew Hill on 12/11/2024.
//


import UIKit
import Photos

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    var rootViewController: DigitalPictureFrameViewController?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        window = UIWindow(frame: UIScreen.main.bounds)
        rootViewController = DigitalPictureFrameViewController()
        window?.rootViewController = rootViewController
        window?.makeKeyAndVisible()

        return true
    }
}
