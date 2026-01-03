import SwiftUI

struct CacheProgressView: View {
    let progress: Float
    let isInitialLoad: Bool
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 20) {
                Text(isInitialLoad ? "Downloading Photos..." : "Updating Cache...")
                    .font(.title)
                    .foregroundColor(.white)
                
                ProgressView(value: progress)
                    .progressViewStyle(LinearProgressViewStyle(tint: .white))
                    .frame(width: 300)
                
                Text("\(Int(progress * 100))% Complete")
                    .foregroundColor(.white)
                    .font(.body)
                
                Text(isInitialLoad ? "Preparing for offline use" : "Adding new photos")
                    .foregroundColor(.gray)
                    .font(.caption)
            }
        }
    }
}