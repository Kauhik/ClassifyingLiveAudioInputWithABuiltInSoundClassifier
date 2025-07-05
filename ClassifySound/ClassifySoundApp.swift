import SwiftUI
import Combine
import SoundAnalysis

struct AppConfiguration {
    var inferenceWindowSize: Double
    var overlapFactor: Double
    var monitoredSounds: Set<SoundIdentifier>

    init(inferenceWindowSize: Double = 1.5, overlapFactor: Double = 0.9) {
        self.inferenceWindowSize = inferenceWindowSize
        self.overlapFactor = overlapFactor
        do {
            let labels = try SystemAudioClassifier.getAllPossibleLabels()
            self.monitoredSounds = Set(labels.map { SoundIdentifier(labelName: $0) })
        } catch {
            print("Error retrieving sound analysis labels: \(error)")
            self.monitoredSounds = []
        }
    }

    static func listAllValidSoundIdentifiers() throws -> Set<SoundIdentifier> {
        let labels = try SystemAudioClassifier.getAllPossibleLabels()
        return Set(labels.map { SoundIdentifier(labelName: $0) })
    }
}

class AppState: ObservableObject {
    private var detectionCancellable: AnyCancellable? = nil
    private var appConfig = AppConfiguration()

    @Published var detectionStates: [(SoundIdentifier, DetectionState)] = []
    @Published var soundDetectionIsRunning: Bool = false

    func restartDetection(config: AppConfiguration) {
        SystemAudioClassifier.singleton.stopSoundClassification()

        let classificationSubject = PassthroughSubject<SNClassificationResult, Error>()

        detectionCancellable = classificationSubject
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { _ in self.soundDetectionIsRunning = false },
                  receiveValue: { result in
                      self.detectionStates = AppState.advanceDetectionStates(self.detectionStates, givenClassificationResult: result)
                  })

        self.detectionStates = config.monitoredSounds
            .sorted(by: { $0.displayName < $1.displayName })
            .map { ($0, DetectionState(presenceThreshold: 0.5,
                                       absenceThreshold: 0.3,
                                       presenceMeasurementsToStartDetection: 2,
                                       absenceMeasurementsToEndDetection: 30)) }

        soundDetectionIsRunning = true
        appConfig = config

        SystemAudioClassifier.singleton.startSoundClassification(
            subject: classificationSubject,
            inferenceWindowSize: config.inferenceWindowSize,
            overlapFactor: config.overlapFactor)
    }

    static func advanceDetectionStates(_ oldStates: [(SoundIdentifier, DetectionState)],
                                       givenClassificationResult result: SNClassificationResult) -> [(SoundIdentifier, DetectionState)] {
        return oldStates.map { (identifier, state) in
            let confidence = result.classification(forIdentifier: identifier.labelName)?.confidence ?? 0
            let updated = DetectionState(advancedFrom: state, currentConfidence: confidence)
            return (identifier, updated)
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
