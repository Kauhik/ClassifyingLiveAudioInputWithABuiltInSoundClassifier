//
//  SystemAudioClassifier.swift
//  Poltek Visit App
//
//  Created by Kaushik Manian on 5/7/25.
//  Modified to fix the audio interruption error handling
//

import Foundation
import AVFoundation
import SoundAnalysis
import Combine

final class SystemAudioClassifier: NSObject {
    enum SystemAudioClassificationError: Error {
        case audioStreamInterrupted
        case noMicrophoneAccess
    }

    private let analysisQueue = DispatchQueue(label: "com.example.apple-samplecode.classifying-sounds.AnalysisQueue")
    private var audioEngine: AVAudioEngine?
    private var analyzer: SNAudioStreamAnalyzer?
    private var retainedObservers: [SNResultsObserving]?
    private var subject: PassthroughSubject<SNClassificationResult, Error>?

    private override init() {}
    static let singleton = SystemAudioClassifier()

    private func ensureMicrophoneAccess() throws {
        var hasMicrophoneAccess = false
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            let sem = DispatchSemaphore(value: 0)
            AVCaptureDevice.requestAccess(for: .audio) { success in
                hasMicrophoneAccess = success
                sem.signal()
            }
            _ = sem.wait(timeout: .distantFuture)
        case .authorized:
            hasMicrophoneAccess = true
        default:
            break
        }
        if !hasMicrophoneAccess {
            throw SystemAudioClassificationError.noMicrophoneAccess
        }
    }

    private func startAudioSession() throws {
        stopAudioSession()
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .default)
            try audioSession.setActive(true)
        } catch {
            stopAudioSession()
            throw error
        }
    }

    private func stopAudioSession() {
        autoreleasepool {
            let session = AVAudioSession.sharedInstance()
            try? session.setActive(false)
        }
    }

    private func startListeningForAudioSessionInterruptions() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleAudioSessionInterruption),
                                               name: AVAudioSession.interruptionNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleAudioSessionInterruption),
                                               name: AVAudioSession.mediaServicesWereLostNotification,
                                               object: nil)
    }

    private func stopListeningForAudioSessionInterruptions() {
        NotificationCenter.default.removeObserver(self,
                                                  name: AVAudioSession.interruptionNotification,
                                                  object: nil)
        NotificationCenter.default.removeObserver(self,
                                                  name: AVAudioSession.mediaServicesWereLostNotification,
                                                  object: nil)
    }

    @objc private func handleAudioSessionInterruption(_ notification: Notification) {
        // Fully qualify the enum case so Swift knows which Error you mean
        subject?.send(completion: .failure(SystemAudioClassificationError.audioStreamInterrupted))
        stopSoundClassification()
    }

    private func startAnalyzing(_ requestsAndObservers: [(SNRequest, SNResultsObserving)]) throws {
        stopAnalyzing()
        do {
            try startAudioSession()
            try ensureMicrophoneAccess()

            let newEngine = AVAudioEngine()
            audioEngine = newEngine
            let bus = AVAudioNodeBus(0)
            let bufferSize = AVAudioFrameCount(4096)
            let format = newEngine.inputNode.outputFormat(forBus: bus)

            let newAnalyzer = SNAudioStreamAnalyzer(format: format)
            analyzer = newAnalyzer

            try requestsAndObservers.forEach { try newAnalyzer.add($0.0, withObserver: $0.1) }
            retainedObservers = requestsAndObservers.map { $0.1 }

            newEngine.inputNode.installTap(onBus: bus, bufferSize: bufferSize, format: format) { buffer, when in
                self.analysisQueue.async {
                    newAnalyzer.analyze(buffer, atAudioFramePosition: when.sampleTime)
                }
            }
            try newEngine.start()
        } catch {
            stopAnalyzing()
            throw error
        }
    }

    private func stopAnalyzing() {
        autoreleasepool {
            if let engine = audioEngine {
                engine.stop()
                engine.inputNode.removeTap(onBus: 0)
            }
            analyzer?.removeAllRequests()
            analyzer = nil
            retainedObservers = nil
            audioEngine = nil
        }
        stopAudioSession()
    }

    func startSoundClassification(subject: PassthroughSubject<SNClassificationResult, Error>,
                                  inferenceWindowSize: Double,
                                  overlapFactor: Double) {
        stopSoundClassification()
        do {
            let observer = ClassificationResultsSubject(subject: subject)
            let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
            request.windowDuration = CMTimeMakeWithSeconds(inferenceWindowSize, preferredTimescale: 48000)
            request.overlapFactor = overlapFactor
            self.subject = subject
            startListeningForAudioSessionInterruptions()
            try startAnalyzing([(request, observer)])
        } catch {
            subject.send(completion: .failure(error))
            self.subject = nil
            stopSoundClassification()
        }
    }

    func stopSoundClassification() {
        stopAnalyzing()
        stopListeningForAudioSessionInterruptions()
    }

    static func getAllPossibleLabels() throws -> Set<String> {
        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        return Set(request.knownClassifications)
    }
}
