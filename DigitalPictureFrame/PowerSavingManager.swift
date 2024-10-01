import UIKit

class PowerSavingManager {
    // Track the original state before entering power-saving mode
    private var originalBrightness: CGFloat = UIScreen.main.brightness
    private var originalIdleTimerState: Bool = UIApplication.shared.isIdleTimerDisabled
    private var powerSavingEnabled: Bool = false
    
    // Method to toggle power-saving mode
    func setPowerSavingMode(enabled: Bool) {
        if enabled {
            activatePowerSavingMode()
        } else {
            deactivatePowerSavingMode()
        }
    }

    private func activatePowerSavingMode() {
        guard !powerSavingEnabled else { return }
        
        DispatchQueue.main.async {
            self.originalBrightness = UIScreen.main.brightness
            UIScreen.main.brightness = 0.0
            self.powerSavingEnabled = true
        }
    }

    private func deactivatePowerSavingMode() {
        guard powerSavingEnabled else { return }

        DispatchQueue.main.async {
            UIScreen.main.brightness = self.originalBrightness
            UIApplication.shared.isIdleTimerDisabled = true
            self.powerSavingEnabled = false
        }
    }
}
