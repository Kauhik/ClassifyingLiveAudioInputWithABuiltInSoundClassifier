//
//  DetectSoundsView.swift
//  ClassifySound
//
//  Created by Kaushik Manian on 5/7/25.
//  Updated to fix isRunning & restartDetection signature.
//

import SwiftUI

/// Shows the grid of meters and the paused/Start button.
struct DetectSoundsView: View {
    @ObservedObject var state: AppState
    @Binding var config: AppConfiguration
    let configureAction: () -> Void

    // MARK: – Helpers for the little confidence bars

    private static func generateConfidenceColors(count: Int) -> [Color] {
        let greenCount  = count / 3
        let yellowCount = (count * 2 / 3) - greenCount
        let redCount    = count - greenCount - yellowCount
        return Array(repeating: .green,  count: greenCount)
             + Array(repeating: .yellow, count: yellowCount)
             + Array(repeating: .red,    count: redCount)
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
            LazyVGrid(columns: [ GridItem(.adaptive(minimum: 100)) ], spacing: 8) {
                ForEach(detections, id: \.0.labelName) { id, state in
                    // only show confidence if detected
                    let conf = state.isDetected ? state.currentConfidence : 0
                    meterCard(confidence: conf, label: id.displayName)
                }
            }
            .padding()
        }
    }

    // MARK: – View Body

    var body: some View {
        VStack {
            ZStack {
                // Live grid
                VStack {
                    Text("Detecting Sounds")
                      .font(.title2)
                      .padding(.top, 8)

                    DetectSoundsView.generateDetectionsGrid(state.detectionStates)
                }
                // Blur/disable when stopped
                .blur(radius: state.isRunning ? 0 : 10)
                .disabled(!state.isRunning)

                // Paused overlay
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

            // “Edit Configuration” always visible
            Button("Edit Configuration", action: configureAction)
              .padding(.bottom, 12)
        }
    }
}
