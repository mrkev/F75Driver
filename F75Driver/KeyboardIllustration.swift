//
//  KeyboardIllustration.swift
//  F75Driver
//
//  A drawing of the AULA F75, seen from above. Drawn from shapes so it stays
//  sharp at any size and can be recoloured; no product photo is shipped.
//  Positions are in key units (1u = one key pitch), measured from a
//  top-down photo of the keyboard.
//

import SwiftUI

struct KeyboardColorway {
    var plate: Color
    var alpha: Color
    var modifier: Color
    var accent: Color
    var alphaLegend: Color
    var modifierLegend: Color
    var accentLegend: Color
    var knobRing: Color

    /// Black case, navy alphas, black modifiers, yellow accents.
    static let midnight = KeyboardColorway(
        plate: Color(red: 0.06, green: 0.06, blue: 0.07),
        alpha: Color(red: 0.23, green: 0.24, blue: 0.36),
        modifier: Color(red: 0.12, green: 0.12, blue: 0.14),
        accent: Color(red: 0.93, green: 0.70, blue: 0.20),
        alphaLegend: Color(red: 0.95, green: 0.74, blue: 0.40),
        modifierLegend: Color(red: 0.93, green: 0.93, blue: 0.93),
        accentLegend: Color(red: 0.10, green: 0.10, blue: 0.10),
        knobRing: Color(red: 0.78, green: 0.79, blue: 0.82)
    )
}

struct KeyboardIllustration: View {
    var colorway: KeyboardColorway = .midnight

    var body: some View {
        Canvas { context, size in
            let unit = size.width / F75Layout.width
            draw(in: &context, unit: unit)
        }
        .aspectRatio(F75Layout.width / F75Layout.height, contentMode: .fit)
        .accessibilityLabel("AULA F75 keyboard")
    }

    private func draw(in context: inout GraphicsContext, unit u: CGFloat) {
        let m = F75Layout.margin

        // The mode switch on the top edge, then the case.
        let tab = CGRect(x: (m + 4.6) * u, y: 0, width: 0.7 * u, height: 0.2 * u)
        context.fill(Path(roundedRect: tab, cornerRadius: 0.06 * u), with: .color(colorway.plate))
        let plate = CGRect(x: 0, y: 0.12 * u, width: F75Layout.width * u, height: (F75Layout.height - 0.12) * u)
        let platePath = Path(roundedRect: plate, cornerRadius: 0.38 * u, style: .continuous)
        context.fill(platePath, with: .color(colorway.plate))
        context.stroke(Path(roundedRect: plate.insetBy(dx: 0.03 * u, dy: 0.03 * u), cornerRadius: 0.36 * u, style: .continuous),
                       with: .color(.white.opacity(0.10)), lineWidth: max(0.5, 0.025 * u))

        // Offset everything else by the case margin.
        var keys = context
        keys.translateBy(x: m * u, y: (m + 0.12) * u)

        // The light bar between Esc and F1.
        let bar = CGRect(x: 1.42 * u, y: 0.12 * u, width: 0.1 * u, height: 0.76 * u)
        keys.fill(Path(roundedRect: bar, cornerRadius: 0.05 * u), with: .color(.white.opacity(0.12)))

        for key in F75Layout.keys {
            drawKey(key, in: &keys, unit: u)
        }

        // The knob above the right-hand column.
        let knob = CGRect(x: 15.25 * u, y: -0.05 * u, width: 1.1 * u, height: 1.1 * u)
        keys.fill(Path(ellipseIn: knob), with: .linearGradient(
            Gradient(colors: [colorway.knobRing, colorway.knobRing.opacity(0.55)]),
            startPoint: CGPoint(x: knob.minX, y: knob.minY), endPoint: CGPoint(x: knob.maxX, y: knob.maxY)))
        keys.fill(Path(ellipseIn: knob.insetBy(dx: 0.12 * u, dy: 0.12 * u)), with: .color(colorway.plate))
        keys.fill(Path(ellipseIn: knob.insetBy(dx: 0.16 * u, dy: 0.16 * u)), with: .radialGradient(
            Gradient(colors: [Color(white: 0.16), Color(white: 0.05)]),
            center: CGPoint(x: knob.midX - 0.15 * u, y: knob.midY - 0.15 * u), startRadius: 0, endRadius: 0.5 * u))
    }

    private func drawKey(_ key: F75Layout.Key, in context: inout GraphicsContext, unit u: CGFloat) {
        let (cap, legendColor): (Color, Color) = switch key.style {
        case .alpha: (colorway.alpha, colorway.alphaLegend)
        case .function: (colorway.alpha, colorway.modifierLegend)
        case .modifier: (colorway.modifier, colorway.modifierLegend)
        case .accent: (colorway.accent, colorway.accentLegend)
        }
        let gap = 0.05 * u
        let outer = CGRect(x: key.x * u + gap, y: key.y * u + gap, width: key.width * u - 2 * gap, height: u - 2 * gap)
        // Skirt, then a slightly lighter top face set towards the top edge.
        context.fill(Path(roundedRect: outer, cornerRadius: 0.1 * u, style: .continuous),
                     with: .color(cap.mix(with: .black, by: 0.25)))
        let face = CGRect(x: outer.minX + 0.07 * u, y: outer.minY + 0.05 * u,
                          width: outer.width - 0.14 * u, height: outer.height - 0.16 * u)
        context.fill(Path(roundedRect: face, cornerRadius: 0.08 * u, style: .continuous),
                     with: .linearGradient(Gradient(colors: [cap.mix(with: .white, by: 0.06), cap]),
                                           startPoint: CGPoint(x: face.midX, y: face.minY),
                                           endPoint: CGPoint(x: face.midX, y: face.maxY)))

        let inset = CGPoint(x: face.minX + 0.1 * u, y: face.minY + 0.08 * u)
        switch key.legend {
        case .none:
            break
        case .letter(let text):
            context.draw(legend(text, size: 0.24 * u, color: legendColor), at: inset, anchor: .topLeading)
        case .pair(let shifted, let base):
            context.draw(legend(shifted, size: 0.19 * u, color: legendColor), at: inset, anchor: .topLeading)
            context.draw(legend(base, size: 0.19 * u, color: legendColor),
                         at: CGPoint(x: inset.x, y: face.maxY - 0.07 * u), anchor: .bottomLeading)
        case .label(let text):
            context.draw(legend(text, size: 0.15 * u, color: legendColor),
                         at: CGPoint(x: inset.x, y: face.midY), anchor: .leading)
        case .symbol(let text):
            context.draw(legend(text, size: 0.24 * u, color: legendColor),
                         at: CGPoint(x: face.midX, y: face.midY), anchor: .center)
        }
    }

    private func legend(_ text: String, size: CGFloat, color: Color) -> Text {
        Text(text).font(.system(size: size, weight: .semibold)).foregroundStyle(color)
    }
}

/// Where each key sits, in key units from the top-left key.
private enum F75Layout {
    /// Function keys share the alpha colour but carry modifier legends.
    enum Style { case alpha, function, modifier, accent }
    enum Legend {
        case none
        case letter(String)
        case pair(String, String)
        case label(String)
        case symbol(String)
    }

    struct Key {
        var x: CGFloat
        var y: CGFloat
        var width: CGFloat = 1
        var style: Style
        var legend: Legend
    }

    static let margin: CGFloat = 0.45
    /// 16.25u of keys plus the case on both sides.
    static let width: CGFloat = 16.25 + 2 * margin
    /// Six rows, the function row set 0.35u apart, plus the case and the switch on top.
    static let height: CGFloat = 6.35 + 2 * margin + 0.12

    static let keys: [Key] = {
        var keys: [Key] = []
        let rightColumn: CGFloat = 15.25

        // Function row: Esc, then F1–F4, F5–F8 and F9–F12 in groups.
        keys.append(Key(x: 0, y: 0, style: .accent, legend: .label("Esc")))
        for i in 0..<12 {
            let group = i / 4
            let x = 2 + CGFloat(i) + CGFloat(group) * 0.25
            keys.append(Key(x: x, y: 0, style: group == 1 ? .modifier : .function, legend: .label("F\(i + 1)")))
        }

        func row(_ y: CGFloat, from start: CGFloat, _ legends: [Legend]) -> CGFloat {
            var x = start
            for legend in legends {
                keys.append(Key(x: x, y: y, style: .alpha, legend: legend))
                x += 1
            }
            return x
        }
        func letters(_ text: String) -> [Legend] { text.map { .letter(String($0)) } }
        func pairs(_ list: [(String, String)]) -> [Legend] { list.map { .pair($0.0, $0.1) } }

        // Number row.
        var y: CGFloat = 1.35
        var x = row(y, from: 0, pairs([("~", "`"), ("!", "1"), ("@", "2"), ("#", "3"), ("$", "4"), ("%", "5"),
                                      ("^", "6"), ("&", "7"), ("*", "8"), ("(", "9"), (")", "0"), ("_", "-"), ("+", "=")]))
        keys.append(Key(x: x, y: y, width: 2, style: .modifier, legend: .label("← Backspace")))
        keys.append(Key(x: rightColumn, y: y, style: .modifier, legend: .label("Delete")))

        // Top letter row.
        y += 1
        keys.append(Key(x: 0, y: y, width: 1.5, style: .modifier, legend: .label("Tab")))
        x = row(y, from: 1.5, letters("QWERTYUIOP") + pairs([("{", "["), ("}", "]")]))
        keys.append(Key(x: x, y: y, width: 1.5, style: .alpha, legend: .pair("|", "\\")))
        keys.append(Key(x: rightColumn, y: y, style: .modifier, legend: .label("PgUp")))

        // Home row.
        y += 1
        keys.append(Key(x: 0, y: y, width: 1.75, style: .modifier, legend: .label("Caps Lock")))
        x = row(y, from: 1.75, letters("ASDFGHJKL") + pairs([(":", ";"), ("\"", "'")]))
        keys.append(Key(x: x, y: y, width: 2.25, style: .accent, legend: .label("↵ Enter")))
        keys.append(Key(x: rightColumn, y: y, style: .modifier, legend: .label("PgDn")))

        // Bottom letter row.
        y += 1
        keys.append(Key(x: 0, y: y, width: 2.25, style: .modifier, legend: .label("⇧ Shift")))
        x = row(y, from: 2.25, letters("ZXCVBNM") + pairs([("<", ","), (">", "."), ("?", "/")]))
        keys.append(Key(x: x, y: y, width: 1.75, style: .modifier, legend: .label("⇧ Shift")))
        keys.append(Key(x: 14.25, y: y, style: .accent, legend: .symbol("↑")))
        keys.append(Key(x: rightColumn, y: y, style: .modifier, legend: .label("End")))

        // Space row.
        y += 1
        x = 0
        for label in ["Ctrl", "Win", "Alt"] {
            keys.append(Key(x: x, y: y, width: 1.25, style: .modifier, legend: .label(label)))
            x += 1.25
        }
        keys.append(Key(x: x, y: y, width: 6.25, style: .accent, legend: .none))
        x += 6.25
        for label in ["Fn", "Ctrl"] {
            keys.append(Key(x: x, y: y, width: 1.25, style: .modifier, legend: .label(label)))
            x += 1.25
        }
        for (i, arrow) in ["←", "↓", "→"].enumerated() {
            keys.append(Key(x: 13.25 + CGFloat(i), y: y, style: .accent, legend: .symbol(arrow)))
        }
        return keys
    }()
}

#Preview {
    KeyboardIllustration()
        .padding()
        .frame(width: 600)
}
