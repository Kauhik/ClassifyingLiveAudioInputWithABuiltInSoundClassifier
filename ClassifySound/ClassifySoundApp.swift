import SwiftUI
import Combine
import SoundAnalysis
import CoreML

/// App-wide sound-analysis configuration.
struct AppConfiguration {
    var windowDuration: Double = 1.5
    var overlap: Double       = 0.5
    var monitoredSounds: Set<SoundIdentifier> = []

    init() {
        do {
            let labels = try SystemAudioClassifier.systemLabels()
            monitoredSounds = Set(labels.map { SoundIdentifier(labelName: $0) })
        } catch {
            monitoredSounds = []
        }
    }
}

/// Drives the detection pipelines and UI state.
class AppState: ObservableObject {
    @Published var detectionStates: [(SoundIdentifier, DetectionState)] = []
    @Published var isRunning = false

    private var config = AppConfiguration()
    private var cancellable: AnyCancellable?
    private var recentLabels: [String] = []  // for majority-vote smoothing

    /// Restart with system classifier + per-label floor + 3/5 smoothing.
    func restartDetection(with config: AppConfiguration) {
        SystemAudioClassifier.shared.stopClassification()
        self.config = config
        recentLabels.removeAll()

        // Stricter per-window thresholds
        detectionStates = config.monitoredSounds
            .sorted { $0.displayName < $1.displayName }
            .map {
                ($0, DetectionState(
                    presenceThreshold: 0.8,
                    absenceThreshold: 0.3,
                    presenceMeasurementsToStartDetection: 3,
                    absenceMeasurementsToEndDetection: 30))
            }

        let subject  = PassthroughSubject<SNClassificationResult, Error>()
        let defaultFloor: Double = 0.5

        cancellable = subject
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { _ in self.isRunning = false },
                receiveValue:     { result in
                    guard let topObs = result.classifications.first else {
                        self.applyNoDetection()
                        return
                    }

                    let label = topObs.identifier
                    let conf  = Double(topObs.confidence)
                    print("[DEBUG] top: \(label) @ \(Int(conf * 100))%")

                    // choose 30% floor for the ice-cream-wall label, otherwise 50%
                    let floor = (label == "sura es krim wall’s keliling") ? 0.3 : defaultFloor

                    if conf >= floor {
                        self.recentLabels.append(label)
                    } else {
                        self.recentLabels.append("")
                    }
                    if self.recentLabels.count > 5 {
                        self.recentLabels.removeFirst()
                    }

                    // majority-vote over last 5, need 3/5
                    let counts = Dictionary(grouping: self.recentLabels, by: { $0 })
                        .mapValues { $0.count }

                    if let (winner, count) = counts.max(by: { $0.value < $1.value }),
                       winner != "", count >= 3 {
                        self.applyDetection(of: winner)
                    } else {
                        self.applyNoDetection()
                    }
                }
            )

        isRunning = true
        SystemAudioClassifier.shared.startSystemClassification(
            subject: subject,
            windowDuration: config.windowDuration,
            overlap: config.overlap
        )
    }

    /// Restart with custom PoltekAudio.mlmodel.
    func restartCustomDetection() {
        SystemAudioClassifier.shared.stopClassification()
        recentLabels.removeAll()

        let labels: [String]
        do {
            labels = try SystemAudioClassifier.customLabels()
        } catch {
            labels = []
        }

        detectionStates = labels
            .map { SoundIdentifier(labelName: $0) }
            .sorted { $0.displayName < $1.displayName }
            .map {
                ($0, DetectionState(
                    presenceThreshold: 0.8,
                    absenceThreshold: 0.3,
                    presenceMeasurementsToStartDetection: 3,
                    absenceMeasurementsToEndDetection: 30))
            }

        let subject: PassthroughSubject<SNClassificationResult, Error> = PassthroughSubject()
        let defaultFloor: Double = 0.5

        cancellable = subject
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { _ in self.isRunning = false },
                receiveValue:     { result in
                    guard let topObs = result.classifications.first else {
                        self.applyNoDetection()
                        return
                    }

                    let label = topObs.identifier
                    let conf  = Double(topObs.confidence)
                    print("[DEBUG][Custom] top: \(label) @ \(Int(conf * 100))%")

                    let floor = (label == "sura es krim wall’s keliling") ? 0.3 : defaultFloor

                    if conf >= floor {
                        self.recentLabels.append(label)
                    } else {
                        self.recentLabels.append("")
                    }
                    if self.recentLabels.count > 5 {
                        self.recentLabels.removeFirst()
                    }

                    let counts = Dictionary(grouping: self.recentLabels, by: { $0 })
                        .mapValues { $0.count }

                    if let (winner, count) = counts.max(by: { $0.value < $1.value }),
                       winner != "", count >= 3 {
                        self.applyDetection(of: winner)
                    } else {
                        self.applyNoDetection()
                    }
                }
            )

        isRunning = true
        SystemAudioClassifier.shared.startCustomClassification(
            subject: subject,
            windowDuration: config.windowDuration,
            overlap: config.overlap
        )
    }

    // MARK: – Helpers

    private func applyDetection(of label: String) {
        detectionStates = detectionStates.map { id, prev in
            let c: Double = (id.labelName == label ? 1.0 : 0)
            return (id, DetectionState(advancedFrom: prev, currentConfidence: c))
        }
    }

    private func applyNoDetection() {
        detectionStates = detectionStates.map { id, prev in
            (id, DetectionState(advancedFrom: prev, currentConfidence: 0))
        }
    }
}

@main
struct ClassifySoundApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
