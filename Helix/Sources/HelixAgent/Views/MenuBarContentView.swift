import SwiftUI

struct MenuBarContentView: View {

    @EnvironmentObject var appState: HelixAppState
    @State private var input: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

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
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 300)
                .onChange(of: appState.currentThread?.messages.count ?? 0, initial: false) { oldValue, newValue in
                    guard newValue > oldValue,
                          let last = appState.currentThread?.messages.last
                    else { return }
                                                                                    
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            

            HStack(alignment: .bottom) {
                ZStack(alignment: .leading) {
                    if input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Ask Helix…")
                            .foregroundColor(.secondary)
                    }
                    TextField("", text: $input, onCommit: {
                        send()
                    })
                    .textFieldStyle(.roundedBorder)
                }
                Button("Send") {
                    send()
                }
                .disabled(appState.isProcessing || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 340)
        .alert(item: Binding<HelixError?>(
            get: { appState.currentError },
            set: { _ in appState.currentError = nil }
        )) { error in
            Alert(title: Text("Error"), message: Text(error.localizedDescription), dismissButton: .default(Text("OK")))
        }
    }

    private func send() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        appState.send(trimmed)
        input = ""
    }
}

