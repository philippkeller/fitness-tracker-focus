import SwiftUI
import UIKit

/// A decimal weight editor that selects the existing value when editing begins.
/// Selection is scoped to this field, leaving reps and exercise notes unaffected.
struct WeightField: UIViewRepresentable {
    @Binding var value: Double

    func makeCoordinator() -> Coordinator { Coordinator(value: $value) }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.placeholder = "kg"
        field.keyboardType = .decimalPad
        field.textAlignment = .center
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        let toolbar = UIToolbar()
        toolbar.items = [
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            UIBarButtonItem(barButtonSystemItem: .done, target: field, action: #selector(UIResponder.resignFirstResponder)),
        ]
        toolbar.sizeToFit()
        field.inputAccessoryView = toolbar
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.value = $value
        // Preserve an in-progress decimal and the cursor while the model updates.
        if !field.isFirstResponder {
            field.text = context.coordinator.formattedValue
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var value: Binding<Double>
        private let formatter: NumberFormatter = {
            let formatter = NumberFormatter()
            formatter.locale = .current
            formatter.numberStyle = .decimal
            formatter.usesGroupingSeparator = false
            formatter.maximumFractionDigits = 2
            return formatter
        }()

        init(value: Binding<Double>) { self.value = value }

        var formattedValue: String {
            formatter.string(from: NSNumber(value: value.wrappedValue)) ?? ""
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            // Run after UIKit places the insertion point for the initiating tap.
            DispatchQueue.main.async { [weak textField] in
                guard let textField, textField.isFirstResponder else { return }
                textField.selectAll(nil)
            }
        }

        @objc func changed(_ textField: UITextField) {
            guard let text = textField.text, !text.isEmpty,
                  let number = formatter.number(from: text)?.doubleValue,
                  number.isFinite, number >= 0 else { return }
            value.wrappedValue = number
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            if textField.text?.isEmpty == true { value.wrappedValue = 0 }
            textField.text = formattedValue
        }
    }
}
