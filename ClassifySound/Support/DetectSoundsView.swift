import SwiftUI

struct DetectSoundsView: View {
    @ObservedObject var state: AppState
    @Binding var config: AppConfiguration
    let configureAction: () -> Void

    private static func generateConfidenceColors(count: Int) -> [Color] {
        let green = count / 3
        let yellow = (count * 2 / 3) - green
        let red = count - green - yellow
        return Array(repeating: .green, count: green)
             + Array(repeating: .yellow, count: yellow)
             + Array(repeating: .red,    count: red)
    }

    private static func generateMeter(confidence: Double) -> some View {
        let bars = 20
        let colors = generateConfidenceColors(count: bars)
        let perBar = 1.0 / Double(bars)
        let lit = Int(confidence / perBar)

        return VStack(spacing: 2) {
            ForEach((0..<bars).reversed(), id: \.self) { idx in
                Rectangle()
                  .frame(width: 15, height: 2)
                  .foregroundColor(colors[idx])
                  .opacity(idx < lit ? 1.0 : 0.1)
            }
        }
        .animation(.easeInOut, value: confidence)
    }

    private static func cardify<Content: View>(_ view: Content) -> some View {
        view
          .frame(width: 100, height: 200)
          .background(Color.blue.opacity(0.2))
          .cornerRadius(12)
    }

    private static func meterCard(confidence: Double, label: String) -> some View {
        cardify(
          VStack {
            generateMeter(confidence: confidence)
            Text(label)
              .font(.caption)
              .multilineTextAlignment(.center)
              .padding(.top, 4)
          }
        )
    }

    static func generateDetectionsGrid(
      _ detections: [(SoundIdentifier, DetectionState)]
    ) -> some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))],
                      spacing: 8) {
                ForEach(detections, id: \.0.labelName) { id, state in
                    let conf = state.isDetected ? state.currentConfidence : 0
                    meterCard(confidence: conf, label: id.displayName)
                }
            }
            .padding()
        }
    }

    var body: some View {
        VStack {
            ZStack {
                VStack {
                    Text("Detecting Sounds")
                      .font(.title2)
                      .padding(.top, 8)

                    DetectSoundsView.generateDetectionsGrid(state.detectionStates)
                }
                .blur(radius: state.isRunning ? 0 : 10)
                .disabled(!state.isRunning)

                if !state.isRunning {
                    VStack(spacing: 16) {
                        Text("Sound Detection Paused")
                        Button("Start") {
                            state.restartDetection(with: config)
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground).opacity(0.8))
                    .cornerRadius(8)
                }
            }

            Spacer()

            Button("Edit Configuration", action: configureAction)
              .padding(.bottom, 12)
        }
    }
}
