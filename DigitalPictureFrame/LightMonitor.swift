import Foundation

class LightMonitor {
    let powerSavingManager = PowerSavingManager()
    var isPowerSavingEnabled = false
    
    let homeAssistantURL = "https://home.andrewthomashill.co.uk"
    let apiToken = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJiY2E2ZTE3NGVkNjc0NTIxOGEzODg3MDJjYzliNjE3MyIsImlhdCI6MTcyNTk0MTgwOSwiZXhwIjoyMDQxMzAxODA5fQ.a_hnCL6X3CkNFjOcfICo-wkS88tXgNbYbzTKH5L1Mlo"
    let entityID = "light.dining_table_light"

    func startLightMonitor(_ onPowerModeChanged: @escaping (Bool) -> Void) {
           checkLightStatus { isOn in
               if let isOn = isOn {
                   if isOn {
                       // Light is on, disable power-saving mode
                       if self.isPowerSavingEnabled {
                           self.isPowerSavingEnabled = false
                           self.powerSavingManager.setPowerSavingMode(enabled: false)
                           onPowerModeChanged(false) // Notify that low power mode is disabled
                       }
                   } else {
                       // Light is off, enable power-saving mode
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
               DispatchQueue.global().asyncAfter(deadline: .now() + 30) {
                   self.startLightMonitor(onPowerModeChanged) // Recursively call to monitor again
               }
           }
       }

    // Function to get the light status
    private func checkLightStatus(completion: @escaping (Bool?) -> Void) {
        // Construct the URL
        guard let url = URL(string: "\(homeAssistantURL)/api/states/\(entityID)") else {
            print("Invalid URL")
            completion(nil)
            return
        }
        
        // Create the URLRequest and set the token in the headers
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Create the data task
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
                // Parse the JSON response
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let state = json["state"] as? String {
                    // The light is on if state is "on"
                    let isOn = (state == "on")
                    completion(isOn)
                    return
                }
            } catch let jsonError {
                print("Error parsing JSON: \(jsonError)")
            }
            
            // If we reach here, something went wrong
            completion(nil)
        }
        
        // Start the request
        task.resume()
    }
}
