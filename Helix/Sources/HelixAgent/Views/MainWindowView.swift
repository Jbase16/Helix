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
                    Text(appState.thread.title)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

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
                        ForEach(appState.thread.messages) { msg in
                            ChatBubbleView(message: msg)
                                .id(msg.id)
                        }
                    }
                    .padding()
                }
                .background(Color(NSColor.textBackgroundColor))
                .onChange(of: appState.thread.messages.count) {
                    if let last = appState.thread.messages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // --------------------------------------------------------
            // Input Area
            // --------------------------------------------------------
            HStack(alignment: .bottom, spacing: 8) {

                TextEditor(text: $input)
                    .font(.body)
                    .frame(minHeight: 40, maxHeight: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.3))
                    )

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
                    .disabled(appState.thread.messages.isEmpty)
                }
            }
            .padding()
        }
        .frame(minWidth: 700, minHeight: 480)
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
