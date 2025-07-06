import SwiftUI

/// Lets the user pick system labels or jump directly to the custom model.
struct SetupMonitoredSoundsView: View {
    let querySoundOptions: () throws -> Set<SoundIdentifier>
    @Binding var selectedSounds: Set<SoundIdentifier>
    let doneAction: () -> Void
    let customAction: () -> Void

    @State private var soundOptions: Set<SoundIdentifier>
    @State private var queryError: String?
    @State private var searchText = ""

    init(
        querySoundOptions: @escaping () throws -> Set<SoundIdentifier>,
        selectedSounds: Binding<Set<SoundIdentifier>>,
        doneAction: @escaping () -> Void,
        customAction: @escaping () -> Void
    ) {
        self.querySoundOptions = querySoundOptions
        self._selectedSounds = selectedSounds
        self.doneAction = doneAction
        self.customAction = customAction

        do {
            let opts = try querySoundOptions()
            _soundOptions = State(initialValue: opts)
            _queryError = State(initialValue: nil)
        } catch {
            _soundOptions = State(initialValue: [])
            _queryError = State(initialValue: "\(error)")
        }
    }

    private var filteredOptions: [SoundIdentifier] {
        let all = soundOptions.sorted { $0.displayName < $1.displayName }
        guard !searchText.isEmpty else { return all }
        return all.filter {
            $0.displayName.lowercased().contains(searchText.lowercased())
        }
    }

    private var header: some View {
        VStack(alignment: .leading) {
            HStack {
                Spacer()
                Button("Done", action: doneAction).padding(.horizontal)
            }
            Text("Select Labels to Detect")
                .font(.title)
                .padding(.horizontal)
            HStack {
                Button("Select All") {
                    selectedSounds = soundOptions
                }
                .padding(.horizontal)
                Button("Clear All") {
                    selectedSounds.removeAll()
                }
                .padding(.horizontal)
                Button("Custom") {
                    customAction()
                }
                .padding(.horizontal)
            }
            .padding(.bottom)
            HStack {
                Image(systemName: "magnifyingglass")
                TextField("Search", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "x.circle.fill")
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header
                List(filteredOptions, id: \.labelName) { option in
                    Button {
                        if selectedSounds.contains(option) {
                            selectedSounds.remove(option)
                        } else {
                            selectedSounds.insert(option)
                        }
                    } label: {
                        HStack {
                            Image(systemName:
                                selectedSounds.contains(option)
                                  ? "checkmark.circle.fill"
                                  : "circle"
                            )
                            Text(option.displayName)
                        }
                    }
                }
                .disabled(queryError != nil)
            }

            if let err = queryError {
                VStack {
                    Text("Error loading sounds:")
                    Text(err)
                    Button("Retry") {
                        do {
                            soundOptions = try querySoundOptions()
                            queryError = nil
                        } catch {
                            queryError = "\(error)"
                        }
                    }
                }
                .padding()
                .background(Color(.systemBackground).opacity(0.95))
            }
        }
    }
}
