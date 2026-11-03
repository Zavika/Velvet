import SwiftUI

extension Color {
    static let ink = Color(red: 15 / 255, green: 11 / 255, blue: 18 / 255)
    static let panel = Color(red: 27 / 255, green: 20 / 255, blue: 33 / 255)
    static let panel2 = Color(red: 37 / 255, green: 28 / 255, blue: 44 / 255)
    static let rose = Color(red: 1, green: 143 / 255, blue: 182 / 255)
    static let onRose = Color(red: 26 / 255, green: 11 / 255, blue: 18 / 255)
    static let muted = Color(red: 168 / 255, green: 150 / 255, blue: 159 / 255)
    static let textMain = Color(red: 247 / 255, green: 238 / 255, blue: 243 / 255)
    static let warn = Color(red: 1, green: 154 / 255, blue: 154 / 255)
}

extension Font {
    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy, design: .rounded) }
}

extension View {
    func pill(primary: Bool) -> some View {
        self
            .font(.system(size: 15, weight: .bold))
            .padding(.horizontal, 22)
            .padding(.vertical, 13)
            .background(primary ? AnyShapeStyle(Color.rose) : AnyShapeStyle(.ultraThinMaterial), in: Capsule())
            .foregroundStyle(primary ? Color.onRose : Color.textMain)
    }
}
