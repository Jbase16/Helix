import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// A SwiftUI view that provides a user interface for editing the Helix
/// configuration.  Users can add or remove project directories, change the
/// model and temp directories, manage custom path bindings, and reset to
/// defaults.  Changes are persisted via HelixConfigStore.
struct HelixSettingsView: View {
    @ObservedObject private var configStore = HelixConfigStore.shared
    @State private var newProjectDir: String = ""
    @State private var newCustomKey: String = ""
    @State private var newCustomValue: String = ""
    @State private var showSaveSuccess: Bool = false
    @State private var showResetConfirm: Bool = false

    var body: some View {
        Form {
            Section(header: Text("Project Directories").font(.headline)) {
                ForEach(configStore.config.projectDirectories, id: \.self) { dir in
                    HStack {
                        Text(dir)
                        Spacer()
                        Button(role: .destructive) {
                            removeProjectDirectory(dir)
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
                HStack {
                    TextField("Add new directory…", text: $newProjectDir)
                    #if canImport(AppKit)
                    Button {
                        pickDirectory { path in
                            newProjectDir = path
                        }
                    } label: {
                        Image(systemName: "folder")
                    }
                    #endif
                    Button("Add") {
                        addProjectDirectory()
                    }
                }
            }

            Section(header: Text("Model Directory").font(.headline)) {
                HStack {
                    TextField("Model directory", text: $configStore.config.modelDirectory)
                        .textFieldStyle(.roundedBorder)
                    #if canImport(AppKit)
                    Button {
                        pickDirectory { path in
                            configStore.config.modelDirectory = path
                        }
                    } label: {
                        Image(systemName: "folder")
                    }
                    #endif
                }
            }

            Section(header: Text("Temp Directory").font(.headline)) {
                HStack {
                    TextField("Temp directory", text: $configStore.config.tempDirectory)
                        .textFieldStyle(.roundedBorder)
                    #if canImport(AppKit)
                    Button {
                        pickDirectory { path in
                            configStore.config.tempDirectory = path
                        }
                    } label: {
                        Image(systemName: "folder")
                    }
                    #endif
                }
            }

            Section(header: Text("Custom Paths").font(.headline)) {
                ForEach(configStore.config.customPaths.keys.sorted(), id: \.self) { key in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(key).bold()
                            Text(configStore.config.customPaths[key] ?? "")
                                .font(.caption)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            removeCustomPath(key)
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
                HStack {
                    TextField("Key", text: $newCustomKey)
                    TextField("Value", text: $newCustomValue)
                    Button("Add") {
                        addCustomPath()
                    }
                }
            }

            Section {
                Button("Save Changes") {
                    saveConfig()
                }
                if showSaveSuccess {
                    Text("Saved successfully.")
                        .foregroundColor(.green)
                        .font(.caption)
                }
            }

            Section {
                Button("Reset to Defaults", role: .destructive) {
                    showResetConfirm = true
                }
            }
        }
        .alert("Reset all settings?", isPresented: $showResetConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                resetToDefaults()
            }
        } message: {
            Text("This will restore HelixConfig to its default values and overwrite your current settings.")
        }
        .padding()
        .frame(width: 600, height: 500)
    }

    // MARK: - Directory Picker (macOS only)
    #if canImport(AppKit)
    private func pickDirectory(completion: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                completion(url.path)
            }
        }
    }
    #endif

    // MARK: - Helper Methods
    private func addProjectDirectory() {
        let trimmed = newProjectDir.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        configStore.config.projectDirectories.append(trimmed)
        newProjectDir = ""
    }

    private func removeProjectDirectory(_ dir: String) {
        configStore.config.projectDirectories.removeAll { $0 == dir }
    }

    private func addCustomPath() {
        let keyTrimmed = newCustomKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let valueTrimmed = newCustomValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyTrimmed.isEmpty, !valueTrimmed.isEmpty else { return }
        configStore.config.customPaths[keyTrimmed] = valueTrimmed
        newCustomKey = ""
        newCustomValue = ""
    }

    private func removeCustomPath(_ key: String) {
        configStore.config.customPaths.removeValue(forKey: key)
    }

    private func saveConfig() {
        // The debouncer in HelixConfigStore handles saving automatically,
        // but we can trigger a save success indicator here.
        showSaveSuccess = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showSaveSuccess = false
        }
    }

    private func resetToDefaults() {
        configStore.config = HelixConfig.default
        showSaveSuccess = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showSaveSuccess = false
        }
    }
}
