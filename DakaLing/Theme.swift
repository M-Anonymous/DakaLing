import SwiftUI

enum Theme {
    static let paper = Color(red: 1.0, green: 0.953, blue: 0.925)
    static let ink = Color(red: 0.353, green: 0.227, blue: 0.196)
    static let cinnabar = Color(red: 1.0, green: 0.478, blue: 0.541)
    static let pine = Color(red: 0.435, green: 0.749, blue: 0.545)
    static let card = Color(red: 1.0, green: 0.984, blue: 0.973)
    static let line = Color(red: 0.953, green: 0.835, blue: 0.784)
    static let muted = Color(red: 0.651, green: 0.486, blue: 0.447)
}

struct PunchButtonStyle: ButtonStyle {
    var filled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(filled ? Theme.card : Theme.ink)
            .background(filled ? Theme.cinnabar : Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                if !filled {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Theme.line, lineWidth: 1)
                }
            }
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}
