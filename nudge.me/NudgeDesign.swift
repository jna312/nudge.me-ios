import SwiftUI

enum NudgeDesign {
    static let background = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.06, green: 0.075, blue: 0.11, alpha: 1)
        : UIColor(red: 0.965, green: 0.965, blue: 0.985, alpha: 1) })
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let accent = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.66, green: 0.71, blue: 1, alpha: 1)
        : UIColor(red: 0.29, green: 0.34, blue: 0.80, alpha: 1) })
    static let softAccent = accent.opacity(0.10)

    static func dayLabel(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return String(localized: "Today") }
        if Calendar.current.isDateInTomorrow(date) { return String(localized: "Tomorrow") }
        return date.formatted(.dateTime.weekday(.wide))
    }

    static func exactDate(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year())
    }
}

struct NudgeCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NudgeDesign.surface, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct NudgePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color(uiColor: .systemBackground))
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(NudgeDesign.accent, in: RoundedRectangle(cornerRadius: 16))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
