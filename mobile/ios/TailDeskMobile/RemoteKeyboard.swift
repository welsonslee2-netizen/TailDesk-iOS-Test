import SwiftUI
import UIKit

struct RemoteKeyboard: UIViewRepresentable {
    @ObservedObject var client: RemoteClient
    let focusToken: Int

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView(frame: .zero)
        view.delegate = context.coordinator
        view.autocorrectionType = .yes
        view.autocapitalizationType = .sentences
        view.smartDashesType = .no
        view.smartQuotesType = .no
        view.keyboardDismissMode = .interactive
        view.accessibilityLabel = "远程键盘输入"
        view.inputAccessoryView = context.coordinator.accessoryBar()
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.client = client
        context.coordinator.textView = view
        if context.coordinator.focusToken != focusToken {
            context.coordinator.focusToken = focusToken
            DispatchQueue.main.async {
                view.text = ""
                view.becomeFirstResponder()
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(client: client) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var client: RemoteClient
        var focusToken = 0
        weak var textView: UITextView?

        init(client: RemoteClient) { self.client = client }

        func textViewDidChange(_ textView: UITextView) {
            guard textView.markedTextRange == nil, !textView.text.isEmpty else { return }
            client.text(textView.text)
            textView.text = ""
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if text == "\n" {
                client.key(13)
                return false
            }
            if text.isEmpty, textView.text.isEmpty {
                client.key(8)
                return false
            }
            return true
        }

        func accessoryBar() -> UIView {
            let bar = UIToolbar()
            bar.sizeToFit()
            bar.items = [
                UIBarButtonItem(title: "Esc", style: .plain, target: self, action: #selector(escape)),
                UIBarButtonItem(title: "Tab", style: .plain, target: self, action: #selector(tab)),
                UIBarButtonItem(systemItem: .flexibleSpace),
                UIBarButtonItem(title: "收起键盘", style: .done, target: self, action: #selector(dismiss))
            ]
            return bar
        }

        @objc private func escape() { client.key(27) }
        @objc private func tab() { client.key(9) }
        @objc private func dismiss() { textView?.resignFirstResponder() }
    }
}
