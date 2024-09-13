import Foundation

class LightMonitor {
    let powerSavingManager = PowerSavingManager()
    var isPowerSavingEnabled = false
    
    
    let homeAssistantURL = ProcessInfo.processInfo.environment["HOMEASSISTANT_URL"]
    let apiToken = ProcessInfo.processInfo.environment["HOMEASSISTANT_TOKEN"] 
    
    let lightEntityID = "light.dining_table_light"
    let sunEntityID = "sun.sun"

    var sunUp: Bool = true // Default to sun being up
    var lastSunCheckDate: Date?

    // This function schedules periodic checks every hour to see if a new day has passed since the last sun check
    func periodicSunCheck() {
        let hourInterval = TimeInterval(3600) // Check every hour
        
        Timer.scheduledTimer(withTimeInterval: hourInterval, repeats: true) { _ in
            let now = Date()
            if let lastCheck = self.lastSunCheckDate {
                if Calendar.current.isDate(now, inSameDayAs: lastCheck) {
                    return // No need to check if it's still the same day
                }
            }
            self.checkEntityState(entityID: self.sunEntityID) { state in
                self.sunUp = (state == "above_horizon")
                self.lastSunCheckDate = now // Update last check time
            }
        }
    }
    
    func startLightMonitor(_ onPowerModeChanged: @escaping (Bool) -> Void) {
        periodicSunCheck() // Start the periodic sun check
        
        checkLightStatus { isOn in
            if let isOn = isOn {
                if self.sunUp || isOn {
                    // Sun is up or light is on, disable power-saving mode
                    if self.isPowerSavingEnabled {
                        self.isPowerSavingEnabled = false
                        self.powerSavingManager.setPowerSavingMode(enabled: false)
                        onPowerModeChanged(false) // Notify that low power mode is disabled
                    }
                } else {
                    // It's night, and light is off, enable power-saving mode
                    if !self.isPowerSavingEnabled {
                        self.isPowerSavingEnabled = true
                        self.powerSavingManager.setPowerSavingMode(enabled: true)
                        onPowerModeChanged(true) // Notify that low power mode is enabled
                    }
                }
            } else {
                print("Failed to retrieve light status.")
            }
            
            // Continue checking the light status after 5 minutes
            DispatchQueue.global().asyncAfter(deadline: .now() + 300) { // 5 minutes
                self.startLightMonitor(onPowerModeChanged) // Recursively call to monitor again
            }
        }
    }

    // Function to get the state of an entity
    private func checkEntityState(entityID: String, completion: @escaping (String?) -> Void) {
        let url = URL(string: "\(homeAssistantURL!)/api/states/\(entityID)")
        guard let url = url else {
            print("Invalid URL", url)
            completion(nil)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(apiToken!)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Error: \(error)")
                completion(nil)
                return
            }
            
            guard let data = data else {
                print("No data received")
                completion(nil)
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let state = json["state"] as? String {
                    completion(state)
                    return
                }
            } catch let jsonError {
                print("Error parsing JSON: \(jsonError)")
                completion(nil)
            }
        }
        
        // Start the request
        task.resume()
    }
    
    private func checkLightStatus(completion: @escaping (Bool?) -> Void) {
        checkEntityState(entityID: lightEntityID) { state in
            if let state = state {
                completion(state == "on")
            } else {
                completion(nil)
            }
        }
    }
}

