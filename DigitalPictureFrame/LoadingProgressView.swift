import SwiftUI

struct LoadingProgressView: View {
    let progress: Float
    let currentStep: String
    let isInitialLoad: Bool
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 20) {
                Text(isInitialLoad ? "Loading Photos..." : "Updating Photos...")
                    .font(.title)
                    .foregroundColor(.white)
                
                ProgressView(value: progress)
                    .progressViewStyle(LinearProgressViewStyle(tint: .white))
                    .frame(width: 300)
                
                Text("\(Int(progress * 100))% Complete")
                    .foregroundColor(.white)
                    .font(.body)
                
                Text(currentStep)
                    .foregroundColor(.gray)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
        }
    }
}