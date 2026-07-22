import SwiftUI
import UIKit

enum FitTheme {
    static let background = Color(red: 0.035, green: 0.047, blue: 0.075)
    static let surface = Color(red: 0.075, green: 0.094, blue: 0.14)
    static let elevated = Color(red: 0.105, green: 0.128, blue: 0.185)
    static let accent = Color(red: 0.49, green: 0.94, blue: 0.62)
    static let accentBlue = Color(red: 0.35, green: 0.70, blue: 1.0)
    static let warning = Color(red: 1.0, green: 0.70, blue: 0.28)
    static let danger = Color(red: 1.0, green: 0.35, blue: 0.39)
    static let secondaryText = Color.white.opacity(0.62)
}

struct FitBackground: View {
    var body: some View {
        ZStack {
            FitTheme.background
            RadialGradient(
                colors: [FitTheme.accentBlue.opacity(0.16), .clear],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 520
            )
        }
        .ignoresSafeArea()
    }
}

struct FitCardModifier: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(FitTheme.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.white.opacity(0.07), lineWidth: 1)
                    }
            )
    }
}

extension View {
    func fitCard(padding: CGFloat = 16) -> some View {
        modifier(FitCardModifier(padding: padding))
    }
}

struct SectionHeading: View {
    let eyebrow: String
    let title: String
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(eyebrow.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(1.4)
                .foregroundStyle(FitTheme.accent)
            Text(title)
                .font(.title2.bold())
            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(FitTheme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ChoiceCard: View {
    let symbol: String
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isSelected ? FitTheme.background : FitTheme.accent)
                    .frame(width: 42, height: 42)
                    .background(isSelected ? FitTheme.accent : FitTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(isSelected ? Color.white.opacity(0.78) : FitTheme.secondaryText)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? FitTheme.accent : Color.white.opacity(0.2))
            }
            .padding(14)
            .background(isSelected ? FitTheme.accent.opacity(0.13) : FitTheme.surface)
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(isSelected ? FitTheme.accent.opacity(0.65) : Color.white.opacity(0.06), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }
}

struct MetricChip: View {
    let value: String
    let label: String
    var tint: Color = FitTheme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(tint)
            Text(label)
                .font(.caption2)
                .foregroundStyle(FitTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(FitTheme.elevated, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct PrimaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(FitTheme.background)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(FitTheme.accent.opacity(configuration.isPressed ? 0.76 : 1), in: RoundedRectangle(cornerRadius: 16))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(isSelected ? FitTheme.background : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isSelected ? FitTheme.accent : FitTheme.elevated, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct AdvisoryBadge: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.caption2.bold())
            .foregroundStyle(FitTheme.warning)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(FitTheme.warning.opacity(0.12), in: Capsule())
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: ProposedViewSize(width: bounds.width, height: bounds.height), subviews: subviews)
        for (index, point) in result.points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var points: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return (CGSize(width: min(maxWidth, max(0, x - spacing)), height: y + lineHeight), points)
    }
}

struct NumericInputControl: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    var unit: String = ""
    var prominent = false
    @State private var text = ""
    @State private var isEditing = false

    var body: some View {
        HStack(spacing: prominent ? 14 : 10) {
            Text(title).font(.subheadline).foregroundStyle(FitTheme.secondaryText)
            Spacer()
            Button { value = max(range.lowerBound, value - step) } label: {
                Image(systemName: "minus").frame(width: prominent ? 46 : 34, height: prominent ? 46 : 34).background(FitTheme.elevated, in: Circle())
            }
            .buttonStyle(.plain)
            .buttonRepeatBehavior(.enabled)
            SelectableNumericTextField(text: $text, isEditing: $isEditing) { commitText() }
                .frame(width: prominent ? 122 : 82, height: prominent ? 52 : 40)
                .background(FitTheme.elevated, in: RoundedRectangle(cornerRadius: prominent ? 14 : 10))
            if !unit.isEmpty { Text(unit).font(.caption).foregroundStyle(FitTheme.secondaryText) }
            Button { value = min(range.upperBound, value + step) } label: {
                Image(systemName: "plus").frame(width: prominent ? 46 : 34, height: prominent ? 46 : 34).background(FitTheme.accent, in: Circle()).foregroundStyle(FitTheme.background)
            }
            .buttonStyle(.plain)
            .buttonRepeatBehavior(.enabled)
        }
        .onAppear { syncText() }
        .onChange(of: value) { _, _ in if !isEditing { syncText() } }
        .onChange(of: isEditing) { _, editing in if !editing { commitText() } }
    }

    private func commitText() {
        value = NumericInputPolicy.commit(text, previous: value, range: range)
        syncText()
    }

    private func syncText() {
        text = value.formatted(.number.precision(.fractionLength(step < 1 ? 1...2 : 0...2)))
    }
}

private struct SelectableNumericTextField: UIViewRepresentable {
    @Binding var text: String
    @Binding var isEditing: Bool
    let onCommit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.keyboardType = .decimalPad
        field.textAlignment = .center
        field.font = .monospacedDigitSystemFont(ofSize: 18, weight: .semibold)
        field.textColor = .label
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        toolbar.items = [UIBarButtonItem(systemItem: .flexibleSpace), UIBarButtonItem(title: "完成", style: .done, target: context.coordinator, action: #selector(Coordinator.done))]
        field.inputAccessoryView = toolbar
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        if field.text != text { field.text = text }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: SelectableNumericTextField
        init(parent: SelectableNumericTextField) { self.parent = parent }

        @objc func changed(_ field: UITextField) { parent.text = field.text ?? "" }
        @objc func done() { parent.onCommit(); parent.isEditing = false; UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
        func textFieldDidBeginEditing(_ textField: UITextField) {
            parent.isEditing = true
            DispatchQueue.main.async { textField.selectAll(nil) }
        }
        func textFieldDidEndEditing(_ textField: UITextField) {
            parent.text = textField.text ?? ""
            parent.isEditing = false
        }
    }
}

struct IntegerInputControl: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    var unit: String = ""

    var body: some View {
        HStack(spacing: 10) {
            Text(title).font(.subheadline).foregroundStyle(FitTheme.secondaryText)
            Spacer()
            Button { value = max(range.lowerBound, value - step) } label: {
                Image(systemName: "minus").frame(width: 34, height: 34).background(FitTheme.elevated, in: Circle())
            }
            .buttonStyle(.plain)
            TextField("0", value: $value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.headline.monospacedDigit())
                .padding(.vertical, 8)
                .frame(width: 68)
                .background(FitTheme.elevated, in: RoundedRectangle(cornerRadius: 10))
                .onChange(of: value) { _, newValue in value = min(range.upperBound, max(range.lowerBound, newValue)) }
            if !unit.isEmpty { Text(unit).font(.caption).foregroundStyle(FitTheme.secondaryText) }
            Button { value = min(range.upperBound, value + step) } label: {
                Image(systemName: "plus").frame(width: 34, height: 34).background(FitTheme.accent, in: Circle()).foregroundStyle(FitTheme.background)
            }
            .buttonStyle(.plain)
        }
    }
}
