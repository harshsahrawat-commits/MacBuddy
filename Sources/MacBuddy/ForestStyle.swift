import SwiftUI
import CoreText

enum ForestStyle {
    static let surface = Color(red: 15/255, green: 33/255, blue: 26/255)
    static let text = Color(red: 243/255, green: 247/255, blue: 234/255)
    static let secondary = Color(red: 183/255, green: 204/255, blue: 183/255)
    static let line = Color(red: 49/255, green: 84/255, blue: 61/255)
    static let accent = Color(red: 149/255, green: 208/255, blue: 122/255)
    static let warning = Color(red: 237/255, green: 196/255, blue: 130/255)
    static let gpu = Color(red: 159/255, green: 198/255, blue: 190/255)
    static let ram = Color(red: 210/255, green: 202/255, blue: 163/255)
    static let raised = Color(red: 29/255, green: 56/255, blue: 39/255)
    // Process-scoped registration; never installs a font into the user's system.
    static let fontRegistered: Bool = {
        guard let url = Bundle.main.url(forResource: "Manrope", withExtension: "ttf", subdirectory: "Fonts") else { return false }
        return CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }()
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        _ = fontRegistered
        return .custom("Manrope", size: size).weight(weight)
    }
}

struct ForestSection<Content: View>: View {
    let title: String
    let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title.uppercased()).font(ForestStyle.font(11, .semibold)).tracking(1.2).foregroundStyle(ForestStyle.secondary)
            content
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
            .background(ForestStyle.raised, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(ForestStyle.line, lineWidth: 1))
    }
}

struct ForestSegments<Value: Hashable>: View {
    let title: String
    let options: [(String, Value)]
    @Binding var selection: Value
    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { index in
                Button { selection = options[index].1 } label: {
                    Text(options[index].0).font(ForestStyle.font(12, .medium)).lineLimit(1)
                        .foregroundStyle(selection == options[index].1 ? ForestStyle.text : ForestStyle.secondary)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(selection == options[index].1 ? ForestStyle.line : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain).accessibilityLabel(title + ": " + options[index].0)
                    .accessibilityAddTraits(selection == options[index].1 ? .isSelected : [])
            }
        }.padding(3).overlay(RoundedRectangle(cornerRadius: 10).stroke(ForestStyle.line, lineWidth: 1))
            .accessibilityElement(children: .contain).accessibilityLabel(title)
    }
}

struct ForestWindowStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.font(ForestStyle.font(13)).foregroundStyle(ForestStyle.text).tint(ForestStyle.accent)
            .buttonStyle(ForestButtonStyle()).background(ForestStyle.surface).environment(\.colorScheme, .dark)
    }
}

struct ForestChipToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            configuration.label.font(ForestStyle.font(13, .semibold)).padding(8)
                .foregroundStyle(configuration.isOn ? ForestStyle.surface : ForestStyle.text)
                .background(configuration.isOn ? ForestStyle.accent : ForestStyle.line, in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain).accessibilityValue(configuration.isOn ? "On" : "Off")
            .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
    }
}

struct ForestButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(ForestStyle.font(12, .semibold))
            .foregroundStyle(prominent ? ForestStyle.surface : ForestStyle.text)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background((prominent ? ForestStyle.accent : ForestStyle.line).opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 9))
            .contentShape(RoundedRectangle(cornerRadius: 9))
            .opacity(isEnabled ? 1 : 0.45)
    }
}
