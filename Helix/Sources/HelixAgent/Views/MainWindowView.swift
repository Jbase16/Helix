//
//  MainWindowView.swift
//  HelixAgent
//
//  Primary Helix UI:
//   • Scrollable chat-like view for conversation
//   • Bottom text input box for prompts
//   • Send / Clear controls
//   • Stop button while streaming
//

import SwiftUI

struct MainWindowView: View {

    @EnvironmentObject var appState: HelixAppState
    @State private var input: String = ""
    @State private var showPermissions: Bool = false

    var body: some View {
        VStack(spacing: 0) {

            // --------------------------------------------------------
            // Header / Toolbar
            // --------------------------------------------------------
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Helix Agent")
                        .font(.title2)
                        .bold()
                    // Current thread title or fallback
                    if let current = appState.currentThread {
                        Text(current.title)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Thread picker and controls
                if !appState.threads.isEmpty {
                    Picker("Thread", selection: Binding(
                        get: { appState.selectedThreadID ?? appState.threads.first!.id },
                        set: { newID in appState.selectThread(id: newID) }
                    )) {
                        ForEach(appState.threads) { thread in
                            Text(thread.title).tag(thread.id)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 150)
                    .pickerStyle(MenuPickerStyle())
                    Button(action: { appState.createThread() }) {
                        Image(systemName: "plus.circle")
                    }
                    .help("New Chat")
                    Button(action: {
                        if let id = appState.selectedThreadID {
                            appState.deleteThread(id: id)
                        }
                    }) {
                        Image(systemName: "minus.circle")
                    }
                    .disabled(appState.threads.count <= 1)
                    .help("Delete Chat")
                    
                    Divider()
                    
                    Button(action: { showPermissions = true }) {
                        Image(systemName: "lock.shield")
                    }
                    .help("Manage Permissions")
                }

                // Generation indicator and stop button
                if appState.isProcessing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Button("Stop") {
                            appState.cancelGeneration()
                        }
                        .keyboardShortcut(.escape, modifiers: [])
                    }
                }
            }
            .padding()
            Divider()

            // --------------------------------------------------------
            // Chat Transcript
            // --------------------------------------------------------
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if let current = appState.currentThread {
                            ForEach(current.messages) { msg in
                                ChatBubbleView(message: msg)
                                    .id(msg.id)
                            }
                        }
                    }
                    .padding()
                }
                .background(Color(NSColor.textBackgroundColor))
                .onChange(of: appState.currentThread?.messages.count ?? 0) { oldValue, newValue in
                    if let last = appState.currentThread?.messages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // --------------------------------------------------------
            // Permission Request Banner
            // --------------------------------------------------------
            if let action = appState.pendingAction {
                VStack(alignment: .leading, spacing: 8) {
                    Text("⚠️ Permission Requested")
                        .font(.headline)
                        .foregroundColor(.orange)
                    
                    Text("Helix wants to execute:")
                        .font(.subheadline)
                    
                    Text("\(action.toolName)(\(action.arguments.description))")
                        .font(.system(.caption, design: .monospaced))
                        .padding(8)
                        .background(Color.black.opacity(0.1))
                        .cornerRadius(6)
                    
                    HStack {
                        Button("Reject") {
                            appState.rejectPendingAction()
                        }
                        .keyboardShortcut(.escape, modifiers: [])
                        
                        Spacer()
                        
                        Button("Approve") {
                            appState.approvePendingAction()
                        }
                        .keyboardShortcut(.return, modifiers: [.command, .shift])
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
                .background(Color(NSColor.windowBackgroundColor))
                .overlay(
                    Rectangle()
                        .stroke(Color.orange, lineWidth: 1)
                )
                .padding()
                .transition(.move(edge: .bottom))
            }

            // --------------------------------------------------------
            // Input Area
            // --------------------------------------------------------
            HStack(alignment: .bottom, spacing: 8) {

                ZStack(alignment: .topLeading) {
                    if input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Ask Helix…")
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 8)
                    }
                    TextEditor(text: $input)
                        .font(.body)
                        .frame(minHeight: 40, maxHeight: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3))
                        )
                }

                VStack(spacing: 8) {
                    Button {
                        send()
                    } label: {
                        Text(appState.isProcessing ? "Sending…" : "Send")
                            .frame(minWidth: 70)
                    }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || appState.isProcessing)

                    Button("Clear") {
                        appState.clear()
                    }
                    .disabled(appState.currentThread?.messages.isEmpty ?? true)
                }
            }
            .padding()
        }
        .frame(minWidth: 700, minHeight: 480)
        // Present errors as alerts
        .alert(item: Binding<HelixError?>(
            get: { appState.currentError },
            set: { _ in appState.currentError = nil }
        )) { error in
            Alert(title: Text("Error"), message: Text(error.localizedDescription), dismissButton: .default(Text("OK")))
        }
        .sheet(isPresented: $showPermissions) {
            PermissionsView(permissionManager: appState.permissionManager)
        }
    }

    // MARK: - Helpers

    private func send() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        appState.send(trimmed)
        input = ""
    }
}

// ------------------------------------------------------------
// MARK: - PREVIEW
// ------------------------------------------------------------

struct MainWindowView_Previews: PreviewProvider {
    static var previews: some View {
        MainActor.assumeIsolated {
            MainWindowView()
                .environmentObject(HelixAppState())
                .frame(width: 900, height: 600)
        }
    }
}

