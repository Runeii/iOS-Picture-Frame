import SwiftUI

struct DebugLogView: View {
    let debugLog: [String]
    let appStartTime: Date

    @State private var elapsedTime: TimeInterval = 0.0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack(alignment: .bottom) {
            // Black background covering the entire screen
            Color.black
                .edgesIgnoringSafeArea(.all)
            
            VStack(alignment: .leading, spacing: 4) {
                // Display each log entry
                ForEach(debugLog.indices, id: \.self) { index in
                    Text(debugLog[index])
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()

            // Elapsed time indicator in the top-right corner
            VStack {
                HStack {
                    Spacer()
                    Text(formattedElapsedTime())
                        .foregroundColor(.white)
                        .padding()
                }
                Spacer()
            }
        }
        .onReceive(timer) { _ in
            elapsedTime = Date().timeIntervalSince(appStartTime)
        }
    }

    // Helper function to format the elapsed time
    func formattedElapsedTime() -> String {
        let totalSeconds = Int(elapsedTime)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = (totalSeconds % 60)
        return String(format: "Uptime: %02d:%02d:%02d", hours, minutes, seconds)
    }
}
