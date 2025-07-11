import Foundation
import AVFoundation
import SoundAnalysis
import Combine
import CoreML
import Accelerate

/// Manages both the built-in and custom Create ML sound classification pipelines.
final class SystemAudioClassifier: NSObject {
    enum ClassificationError: Error {
        case audioStreamInterrupted
        case noMicrophoneAccess
    }

    static let shared = SystemAudioClassifier()
    private override init() {}

    private let analysisQueue = DispatchQueue(label: "com.example.audio.AnalysisQueue")
    private var audioEngine: AVAudioEngine?
    private var analyzer: SNAudioStreamAnalyzer?
    private var observers: [SNResultsObserving]?
    private var subject: PassthroughSubject<SNClassificationResult, Error>?

    // MARK: – Audio session setup/teardown

    private func ensureMicAccess() throws {
        var granted = false
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            let sem = DispatchSemaphore(value: 0)
            AVCaptureDevice.requestAccess(for: .audio) {
                granted = $0
                sem.signal()
            }
            _ = sem.wait(timeout: .distantFuture)
        case .authorized:
            granted = true
        default:
            break
        }
        if !granted { throw ClassificationError.noMicrophoneAccess }
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default)
        try session.setActive(true)
    }

    private func teardownAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    private func startInterruptionObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.mediaServicesWereLostNotification,
            object: nil)
    }

    private func stopInterruptionObservers() {
        NotificationCenter.default.removeObserver(
            self,
            name: AVAudioSession.interruptionNotification,
            object: nil)
        NotificationCenter.default.removeObserver(
            self,
            name: AVAudioSession.mediaServicesWereLostNotification,
            object: nil)
    }

    @objc private func handleInterruption(_ notification: Notification) {
        subject?.send(completion: .failure(ClassificationError.audioStreamInterrupted))
        stopClassification()
    }

    // MARK: – Tap + RMS gating + analysis

    private func startAnalyzing(requests: [(SNRequest, SNResultsObserving)]) throws {
        stopAnalyzing()
        try configureAudioSession()
        try ensureMicAccess()

        let engine = AVAudioEngine()
        let format = engine.inputNode.outputFormat(forBus: 0)
        let newAnalyzer = SNAudioStreamAnalyzer(format: format)

        audioEngine = engine
        analyzer = newAnalyzer
        observers = requests.map { $0.1 }

        for (req, obs) in requests {
            try newAnalyzer.add(req, withObserver: obs)
        }

        engine.inputNode.installTap(onBus: 0,
                                    bufferSize: 4096,
                                    format: format) { buffer, when in
            self.analysisQueue.async {
                guard let data = buffer.floatChannelData?[0] else { return }
                let count = Int(buffer.frameLength)

                var meanSquare: Float = 0
                vDSP_measqv(data, 1, &meanSquare, vDSP_Length(count))
                let rms = sqrt(meanSquare)

                // gate out low-level noise
                if rms > 0.01 {
                    newAnalyzer.analyze(buffer, atAudioFramePosition: when.sampleTime)
                }
            }
        }

        try engine.start()
    }

    private func stopAnalyzing() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        analyzer?.removeAllRequests()
        teardownAudioSession()
        audioEngine = nil
        analyzer = nil
        observers = nil
    }

    // MARK: – System classifier

    func startSystemClassification(
        subject: PassthroughSubject<SNClassificationResult, Error>,
        windowDuration: Double,
        overlap: Double
    ) {
        stopClassification()
        do {
            let obs = ClassificationResultsSubject(subject: subject)
            let req = try SNClassifySoundRequest(classifierIdentifier: .version1)
            // use 1.5 s window, 50 % overlap
            req.windowDuration = CMTimeMakeWithSeconds(1.5, preferredTimescale: 48000)
            req.overlapFactor   = 0.5

            self.subject = subject
            startInterruptionObservers()
            try startAnalyzing(requests: [(req, obs)])
        } catch {
            subject.send(completion: .failure(error))
            stopClassification()
        }
    }

    // MARK: – Custom Create ML model

    func startCustomClassification(
        subject: PassthroughSubject<SNClassificationResult, Error>,
        windowDuration: Double,
        overlap: Double
    ) {
        stopClassification()
        do {
            let obs   = ClassificationResultsSubject(subject: subject)
            let model = try PoltekAudio(configuration: MLModelConfiguration()).model
            let req   = try SNClassifySoundRequest(mlModel: model)
            // match training window
            req.windowDuration = CMTimeMakeWithSeconds(1.5, preferredTimescale: 48000)
            req.overlapFactor   = 0.5

            self.subject = subject
            startInterruptionObservers()
            try startAnalyzing(requests: [(req, obs)])
        } catch {
            subject.send(completion: .failure(error))
            stopClassification()
        }
    }

    func stopClassification() {
        stopAnalyzing()
        stopInterruptionObservers()
    }

    // MARK: – Label helpers

    static func systemLabels() throws -> [String] {
        let req = try SNClassifySoundRequest(classifierIdentifier: .version1)
        return req.knownClassifications
    }

    static func customLabels() throws -> [String] {
        let model = try PoltekAudio(configuration: MLModelConfiguration()).model
        let req   = try SNClassifySoundRequest(mlModel: model)
        return req.knownClassifications
    }
}
