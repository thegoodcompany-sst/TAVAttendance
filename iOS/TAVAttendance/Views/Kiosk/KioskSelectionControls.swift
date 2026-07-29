import SwiftUI

// MARK: - Selection action button

struct SelectionActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.title2)
                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(disabled ? Color(.tertiaryLabel) : color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(disabled ? Color(.systemGray6) : color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}
