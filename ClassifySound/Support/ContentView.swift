import SwiftUI

struct ContentView: View {
    @State private var showSetup = true
    @State private var config = AppConfiguration()
    @StateObject private var appState = AppState()

    var body: some View {
        ZStack {
            if showSetup {
                SetupMonitoredSoundsView(
                    querySoundOptions: {
                        let labels = try SystemAudioClassifier.systemLabels()
                        let ids = labels.map { SoundIdentifier(labelName: $0) }
                        return Set(ids)
                    },
                    selectedSounds: $config.monitoredSounds,
                    doneAction: {
                        showSetup = false
                        appState.restartDetection(with: config)
                    },
                    customAction: {
                        showSetup = false
                        appState.restartCustomDetection()
                    }
                )
            } else {
                DetectSoundsView(
                    state: appState,
                    config: $config,
                    configureAction: { showSetup = true }
                )
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
