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

    // Activate power-saving mode
    private func activatePowerSavingMode() {
        guard !powerSavingEnabled else { return } // If already enabled, do nothing
        
        DispatchQueue.main.async {
            // Save current brightness and idle timer settings
            self.originalBrightness = UIScreen.main.brightness

            // 1. Reduce screen brightness to minimum
            UIScreen.main.brightness = 0.0
            
            // 2. Allow the device to sleep when idle (disable screen-on behavior)
            UIApplication.shared.isIdleTimerDisabled = false
            
            // 3. Optionally: Disable resource-heavy operations, animations, or background tasks here
            print("Power-saving mode enabled")

            // Mark power-saving as enabled
            self.powerSavingEnabled = true
        }
    }

    // Deactivate power-saving mode and restore original settings
    private func deactivatePowerSavingMode() {
        guard powerSavingEnabled else { return } // If not enabled, do nothing

        DispatchQueue.main.async {
            // 1. Restore original screen brightness
            UIScreen.main.brightness = self.originalBrightness
            
            // 2. Restore original idle timer state
            UIApplication.shared.isIdleTimerDisabled = true
            
            // 3. Optionally: Re-enable animations, background tasks, etc.
            print("Power-saving mode disabled")

            // Mark power-saving as disabled
            self.powerSavingEnabled = false
        }
    }
}
