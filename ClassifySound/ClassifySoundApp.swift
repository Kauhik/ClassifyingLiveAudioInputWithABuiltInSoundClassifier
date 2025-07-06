import SwiftUI
import Combine
import SoundAnalysis
import CoreML

/// Holds your app’s configuration.
struct AppConfiguration {
    var windowDuration: Double
    var overlap: Double
    var monitoredSounds: Set<SoundIdentifier>

    init(windowDuration: Double = 1.5, overlap: Double = 0.9) {
        self.windowDuration = windowDuration
        self.overlap = overlap
        do {
            let labels = try SystemAudioClassifier.systemLabels()
            self.monitoredSounds = Set(labels.map { SoundIdentifier(labelName: $0) })
        } catch {
            print("Error loading system labels: \(error)")
            self.monitoredSounds = []
        }
    }

    static func availableSystemSounds() throws -> Set<SoundIdentifier> {
        let labels = try SystemAudioClassifier.systemLabels()
        return Set(labels.map { SoundIdentifier(labelName: $0) })
    }
}

/// Manages detection state and pipelines.
class AppState: ObservableObject {
    @Published var detectionStates: [(SoundIdentifier, DetectionState)] = []
    @Published var isRunning = false

    private var config = AppConfiguration()
    private var cancellable: AnyCancellable?

    /// Start the system classifier with the selected labels.
    func restartDetection(with config: AppConfiguration) {
        SystemAudioClassifier.shared.stopClassification()
        self.config = config

        detectionStates = config.monitoredSounds
            .sorted(by: { $0.displayName < $1.displayName })
            .map {
                ( $0,
                  DetectionState(
                    presenceThreshold: 0.5,
                    absenceThreshold: 0.3,
                    presenceMeasurementsToStartDetection: 2,
                    absenceMeasurementsToEndDetection: 30
                  )
                )
            }

        let subject = PassthroughSubject<SNClassificationResult, Error>()
        cancellable = subject
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { _ in self.isRunning = false },
                receiveValue: { result in
                    self.detectionStates = self.detectionStates.map { identifier, prev in
                        let conf = result.classification(forIdentifier: identifier.labelName)?.confidence ?? 0
                        return (identifier, DetectionState(advancedFrom: prev, currentConfidence: conf))
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

    /// Start classification using your custom PoltekAudio.mlmodel.
    func restartCustomDetection() {
        SystemAudioClassifier.shared.stopClassification()

        do {
            let labels = try SystemAudioClassifier.customLabels()
            detectionStates = Set(labels.map { SoundIdentifier(labelName: $0) })
                .sorted(by: { $0.displayName < $1.displayName })
                .map {
                    ( $0,
                      DetectionState(
                        presenceThreshold: 0.5,
                        absenceThreshold: 0.3,
                        presenceMeasurementsToStartDetection: 2,
                        absenceMeasurementsToEndDetection: 30
                      )
                    )
                }
        } catch {
            print("Failed to load custom labels: \(error)")
            detectionStates = []
        }

        let subject = PassthroughSubject<SNClassificationResult, Error>()
        cancellable = subject
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { _ in self.isRunning = false },
                receiveValue: { result in
                    self.detectionStates = self.detectionStates.map { identifier, prev in
                        let conf = result.classification(forIdentifier: identifier.labelName)?.confidence ?? 0
                        return (identifier, DetectionState(advancedFrom: prev, currentConfidence: conf))
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
}

@main
struct ClassifySoundApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
