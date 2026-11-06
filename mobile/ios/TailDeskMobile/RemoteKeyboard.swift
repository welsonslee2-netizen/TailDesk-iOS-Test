import SwiftUI
import UIKit

struct RemoteKeyboard: UIViewRepresentable {
    @ObservedObject var client: RemoteClient
    let focusToken: Int

    func makeCoordinator() -> Coordinator { Coordinator(client: client) }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField(frame: .zero)
        field.delegate = context.coordinator
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.autocapitalizationType = .none
        field.returnKeyType = .default
        field.textColor = .clear
        field.tintColor = .clear
        field.accessibilityLabel = "远程键盘输入"
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.client = client
        if context.coordinator.focusToken != focusToken {
            context.coordinator.focusToken = focusToken
            DispatchQueue.main.async { field.becomeFirstResponder() }
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var client: RemoteClient
        var focusToken = 0
        init(client: RemoteClient) { self.client = client }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            if string.isEmpty { client.key(8) } else { client.text(string) }
            return false
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            client.key(13); return false
        }
    }
}

