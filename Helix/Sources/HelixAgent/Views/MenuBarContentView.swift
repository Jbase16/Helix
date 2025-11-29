import SwiftUI

struct MenuBarContentView: View {

    @EnvironmentObject var appState: HelixAppState
    @State private var input: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            ScrollView {
                ForEach(appState.thread.messages) { msg in
                    ChatBubbleView(message: msg)
                }
            }
            .frame(maxHeight: 300)

            HStack {
                TextField("Ask Helix…", text: $input)
                    .textFieldStyle(.roundedBorder)

                Button("Send") {
                    if !input.isEmpty {
                        appState.send(input)
                        input = ""
                    }
                }
                .disabled(appState.isProcessing)
            }
        }
        .padding()
        .frame(width: 340)
    }
}
