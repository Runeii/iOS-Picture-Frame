import Foundation

class LightMonitor {
    let powerSavingManager = PowerSavingManager()
    var isPowerSavingEnabled = false
    
    let homeAssistantURL = ProcessInfo.processInfo.environment["HOMEASSISTANT_URL"]
    let apiToken = ProcessInfo.processInfo.environment["HOMEASSISTANT_TOKEN"]
    
    let lightEntityID = "light.dining_table_light"
    let sunEntityID = "sun.sun"
    
    var sunUp: Bool = true
    var lastSunCheckDate: Date?
    
    var onDebug: ((String) -> Void)? = nil
    var lightStatusTimer: DispatchSourceTimer?
    var sunCheckTimer: DispatchSourceTimer?
    
    func startLightMonitor(
        onPowerModeChanged: @escaping (Bool) -> Void,
        onDebug: @escaping (String) -> Void
    ) {
        self.onDebug = onDebug
        
        // Start periodic sun check
        startPeriodicSunCheck()
        
        // Start light status monitor
        startLightStatusMonitor(onPowerModeChanged: onPowerModeChanged)
    }
    
    func startPeriodicSunCheck() {
        let hourInterval = TimeInterval(3600) // 1 hour in seconds
        
        sunCheckTimer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
        sunCheckTimer?.schedule(deadline: .now(), repeating: hourInterval)
        
        sunCheckTimer?.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.onDebug?("Sun check timer fired.")
            
            let now = Date()
            if let lastCheck = self.lastSunCheckDate {
                if Calendar.current.isDate(now, inSameDayAs: lastCheck) {
                    return // No need to check if it's the same day
                }
            }
            
            self.checkEntityState(entityID: self.sunEntityID) { state in
                self.sunUp = (state == "above_horizon")
                self.lastSunCheckDate = now
                self.onDebug?("Sun state updated: \(self.sunUp ? "Up" : "Down")")
            }
        }
        
        sunCheckTimer?.resume()
    }
    
    func startLightStatusMonitor(
        onPowerModeChanged: @escaping (Bool) -> Void
    ) {
        let checkInterval = TimeInterval(5 * 60) // 5 minutes in seconds
        
        lightStatusTimer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
        lightStatusTimer?.schedule(deadline: .now(), repeating: checkInterval)
        
        lightStatusTimer?.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.checkLightStatus { isOn in
                self.onDebug?("Light status updated: \(isOn ?? false ? "On" : "Off")")
                self.onDebug?("Sun is currently \(self.sunUp ? "Up" : "Down")")

                if let isOn = isOn {
                    if self.sunUp || isOn {
                        // Sun is up or light is on, disable power-saving mode
                        if self.isPowerSavingEnabled {
                            self.isPowerSavingEnabled = false
                            self.powerSavingManager.setPowerSavingMode(enabled: false)
                            onPowerModeChanged(false)
                        }
                    } else {
                        // It's night, and light is off, enable power-saving mode
                        if !self.isPowerSavingEnabled {
                            self.isPowerSavingEnabled = true
                            self.powerSavingManager.setPowerSavingMode(enabled: true)
                            onPowerModeChanged(true)
                        }
                    }
                } else {
                    self.onDebug?("Failed to retrieve light status.")
                }
            }
        }
        
        lightStatusTimer?.resume()
    }
    
    // Function to get the state of an entity
    private func checkEntityState(entityID: String, completion: @escaping (String?) -> Void) {
        guard let homeAssistantURL = homeAssistantURL,
              let apiToken = apiToken else {
            self.onDebug?("Environment variables not set.")
            completion(nil)
            return
        }
        
        let urlString = "\(homeAssistantURL)/api/states/\(entityID)"
        guard let url = URL(string: urlString) else {
            self.onDebug?("Invalid URL: \(urlString)")
            completion(nil)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                self.onDebug?("Error during API call: \(error.localizedDescription)")
                completion(nil)
                return
            }
            
            guard let data = data else {
                self.onDebug?("No data received from API.")
                completion(nil)
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let state = json["state"] as? String {
                    completion(state)
                } else {
                    self.onDebug?("Invalid response format from API.")
                    completion(nil)
                }
            } catch {
                self.onDebug?("Failed to parse JSON response: \(error.localizedDescription)")
                completion(nil)
            }
        }
        
        task.resume()
    }
    
    private func checkLightStatus(completion: @escaping (Bool?) -> Void) {
        checkEntityState(entityID: lightEntityID) { state in
            self.onDebug?("Light state: \(self.lightEntityID) is \(state ?? "unknown")")
            if let state = state {
                completion(state == "on")
            } else {
                completion(nil)
            }
        }
    }
}
