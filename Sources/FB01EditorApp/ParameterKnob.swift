import SwiftUI

private struct ForestHoverTextEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var forestHoverTextEnabled: Bool {
        get { self[ForestHoverTextEnabledKey.self] }
        set { self[ForestHoverTextEnabledKey.self] = newValue }
    }
}

private struct ForestHoverHelpModifier: ViewModifier {
    @Environment(\.forestHoverTextEnabled) private var hoverTextEnabled
    var text: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if hoverTextEnabled, let text, !text.isEmpty {
            content.help(text)
        } else {
            content
        }
    }
}

extension View {
    func forestHoverHelp(_ text: String?) -> some View {
        modifier(ForestHoverHelpModifier(text: text))
    }
}

enum ControlHoverText {
    static func knob(label: String) -> String? {
        switch normalized(label) {
        case "":
            return nil
        case "User Code":
            return "Stores a small voice ID value. It usually does not change the sound."
        case "Transpose":
            return "Moves the whole voice up or down in pitch."
        case "Feedback", "OP4 Feedback":
            return "Feeds Operator 4 back into itself. Adds edge, buzz, or metallic bite."
        case "LFO Speed":
            return "Controls how fast vibrato or tremolo movement cycles."
        case "Amplitude MOD Depth":
            return "Sets how deeply the LFO can move loudness for tremolo-like motion."
        case "Pitch MOD Depth", "PMD":
            return "Sets pitch modulation depth, usually heard as vibrato amount."
        case "Amplitude MOD Sensitivity":
            return "Sets how strongly the voice responds to amplitude modulation sources."
        case "Pitch MOD Sensitivity":
            return "Sets how strongly the voice responds to pitch modulation sources like the mod wheel."
        case "OSC FRQ Multiplier":
            return "Changes the operator frequency ratio. Higher values add brighter or more complex harmonics."
        case "Detune", "Detune 1":
            return "Fine-shifts pitch for beating, chorus, or rougher harmonic color."
        case "Detune 2":
            return "Adds another small pitch offset for thickness or shimmer."
        case "Total Level":
            return "Sets this operator's strength. Carriers get louder; modulators change brightness and complexity."
        case "TL Adjust":
            return "Offsets total level for this operator. Useful for fine balancing."
        case "Vel to TL":
            return "Makes playing harder change this operator's level, adding touch-sensitive brightness or volume."
        case "Keyboard Level Depth":
            return "Changes how this operator's level varies across the keyboard."
        case "Keyboard Rate Scaling Depth":
            return "Changes envelope speed across the keyboard, often making higher notes respond faster."
        case "Attack":
            return "Controls how quickly the sound reaches its initial level after a note starts."
        case "Vel to Attack":
            return "Makes harder playing change attack speed for more expressive starts."
        case "Decay 1":
            return "Controls the first drop after the attack, shaping punch or pluck."
        case "Decay 2":
            return "Controls the later decay toward sustain, shaping how the tone settles."
        case "Sustain":
            return "Sets the held level after the decay stages."
        case "Release":
            return "Controls how quickly the sound fades after you release a key."
        case "Level":
            return "Sets output level; higher values make this part louder."
        case "Stereo Pan":
            return "Moves this instrument left or right in the stereo field."
        case "MIDI Channel", "Channel":
            return "Chooses the MIDI channel used for this part or live keyboard."
        case "Voice Bank":
            return "Selects the voice bank used by this instrument."
        case "Voice Number":
            return "Selects the voice slot used by this instrument."
        case "Active Notes":
            return "Allocates polyphony to this instrument. More notes here leave fewer for other instruments."
        case "Low Key":
            return "Sets the lowest key this instrument will respond to."
        case "High Key":
            return "Sets the highest key this instrument will respond to."
        case "Octave":
            return "Moves the live keyboard or instrument up or down by octaves."
        case "Portamento":
            return "Adds glide between notes. Higher values make pitch slides slower."
        case "Bend Range":
            return "Sets how far pitch bend can move the pitch."
        case "Velocity":
            return "Sets how hard live keyboard notes are sent."
        case "Volume":
            return "Sets the output level used by the live keyboard controls."
        case "Brightness":
            return "Macro: shifts the voice toward a brighter, more forward tone."
        case "Warmth":
            return "Macro: softens hard edges and nudges the voice toward a rounder tone."
        case "Bite":
            return "Macro: emphasizes attack and harmonic edge for a more aggressive front."
        case "Body":
            return "Macro: adds weight and sustain so the voice feels fuller."
        case "Motion":
            return "Macro: adds movement through modulation and evolving tone."
        case "Punch":
            return "Macro: makes the start of notes hit harder."
        case "Air":
            return "Macro: opens the tone with lighter, more shimmering upper detail."
        case "Character":
            return "Macro: pushes the selected voice character toward a stronger identity."
        default:
            return "\(normalized(label)): drag up to increase, drag down to decrease."
        }
    }

    static func toggle(label: String) -> String {
        switch normalized(label) {
        case "Left", "Left Output":
            return "Sends this voice to the left output channel."
        case "Right", "Right Output":
            return "Sends this voice to the right output channel."
        case "Load LFO Data":
            return "Uses the voice's stored LFO settings when the voice is loaded."
        case "LFO Sync":
            return "Restarts LFO motion with each note for more consistent modulation."
        case "Enabled", "Operator Enabled":
            return "Turns this operator on or off. Disabled operators do not shape the sound."
        case "Enable":
            return "Lets Forest listen to the selected external MIDI source."
        case "Memory Protect":
            return "Shows whether device memory protection is on; protection blocks writes."
        case "Memory Writable":
            return "Allows device writes for this configured FB-01 device."
        case "LFO Enabled":
            return "Lets this instrument use LFO modulation."
        case "Layer Instruments":
            return "Layers active instruments so they can sound together."
        default:
            return "\(normalized(label)): toggles this setting on or off."
        }
    }

    private static func normalized(_ label: String) -> String {
        label
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}

struct ParameterKnob: View {
    var label: String
    @Binding var value: Int
    var range: ClosedRange<Int>
    var width: CGFloat = 82
    var knobSize: CGFloat = 48
    var displayTextProvider: ((Int) -> String)?
    var helpText: String?
    var isModified: Bool = false

    @State private var dragStartValue: Int?

    var body: some View {
        VStack(spacing: 5) {
            SevenSegmentDisplay(text: formattedDisplayText)
                .frame(width: width, height: 24)

            KnobFace(normalizedValue: normalizedValue)
                .frame(width: knobSize, height: knobSize)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            if dragStartValue == nil {
                                dragStartValue = value
                            }
                            let startValue = dragStartValue ?? value
                            let span = max(range.upperBound - range.lowerBound, 1)
                            let pointsPerFullTravel: CGFloat = 150
                            let delta = dragDelta(
                                translation: gesture.translation.height,
                                startValue: startValue,
                                span: span,
                                pointsPerFullTravel: pointsPerFullTravel
                            )
                            setValue(startValue + delta)
                        }
                        .onEnded { _ in
                            dragStartValue = nil
                        }
                )
                .accessibilityLabel(label)
                .accessibilityValue("\(value)")

            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isModified ? Color.orange : Color.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .frame(width: width, height: 28, alignment: .top)
        }
        .frame(width: width)
        .forestHoverHelp(helpText ?? ControlHoverText.knob(label: label))
    }

    private var normalizedValue: Double {
        let span = max(range.upperBound - range.lowerBound, 1)
        return Double(value - range.lowerBound) / Double(span)
    }

    private var hasCenterZeroDetent: Bool {
        range.lowerBound < 0 && range.upperBound > 0
    }

    private var formattedDisplayText: String {
        if let displayTextProvider {
            return displayTextProvider(value)
        }

        let maximumDigits = max("\(range.lowerBound)".count, "\(range.upperBound)".count)
        if value < 0 {
            return String(format: "%0\(maximumDigits)d", value)
        }
        return String(format: "%0\(maximumDigits)d", value)
    }

    private func dragDelta(
        translation: CGFloat,
        startValue: Int,
        span: Int,
        pointsPerFullTravel: CGFloat
    ) -> Int {
        var adjustedTranslation = translation
        if hasCenterZeroDetent, startValue == 0 {
            let detentPoints: CGFloat = 18
            if abs(adjustedTranslation) < detentPoints {
                return 0
            }
            adjustedTranslation += adjustedTranslation > 0 ? -detentPoints : detentPoints
        }

        return Int((-adjustedTranslation / pointsPerFullTravel * CGFloat(span)).rounded())
    }

    private func setValue(_ proposedValue: Int) {
        let clampedValue = min(max(proposedValue, range.lowerBound), range.upperBound)
        if hasCenterZeroDetent, abs(Double(clampedValue)) < 1.25 {
            value = 0
        } else {
            value = clampedValue
        }
    }
}

struct ReadOnlyLEDValue: View {
    var label: String
    var value: String
    var width: CGFloat = 82

    var body: some View {
        VStack(spacing: 5) {
            SevenSegmentDisplay(text: value)
                .frame(width: width, height: 24)
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .frame(width: width, height: 28, alignment: .top)
        }
        .frame(width: width)
    }
}

struct RockerSwitch: View {
    var label: String
    @Binding var isOn: Bool
    var width: CGFloat = 58
    var height: CGFloat = 68
    var helpText: String?
    var isModified: Bool = false

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            VStack(spacing: 5) {
                RockerSwitchFace(isOn: isOn)
                    .frame(width: width * 0.72, height: height)

                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isModified ? Color.orange : Color.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .frame(width: width, height: 28, alignment: .top)
            }
            .frame(width: width, height: height + 33, alignment: .top)
            .fixedSize()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "On" : "Off")
        .forestHoverHelp(helpText ?? ControlHoverText.toggle(label: label))
    }
}

private struct RockerSwitchFace: View {
    var isOn: Bool

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let bezel = RoundedRectangle(cornerRadius: min(size.width, size.height) * 0.16)
            let upperRect = CGRect(x: 4, y: 4, width: size.width - 8, height: size.height * 0.52 - 4)
            let lowerRect = CGRect(x: 4, y: size.height * 0.48, width: size.width - 8, height: size.height * 0.52 - 4)

            ZStack {
                bezel
                    .fill(Color(red: 0.05, green: 0.06, blue: 0.06))
                    .overlay(bezel.stroke(Color.white.opacity(0.16), lineWidth: 1))
                    .shadow(color: .black.opacity(0.65), radius: 3, x: 0, y: 2)

                RoundedRectangle(cornerRadius: 5)
                    .fill(isOn ? Color(red: 0.03, green: 0.56, blue: 0.24) : Color(red: 0.07, green: 0.13, blue: 0.09))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(isOn ? Color.green.opacity(0.75) : Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .shadow(color: isOn ? Color.green.opacity(0.70) : .clear, radius: 7)
                    .frame(width: upperRect.width, height: upperRect.height)
                    .position(x: upperRect.midX, y: upperRect.midY)

                RoundedRectangle(cornerRadius: 5)
                    .fill(isOn ? Color(red: 0.02, green: 0.08, blue: 0.04) : Color(red: 0.04, green: 0.05, blue: 0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.white.opacity(isOn ? 0.05 : 0.15), lineWidth: 1)
                    )
                    .frame(width: lowerRect.width, height: lowerRect.height)
                    .position(x: lowerRect.midX, y: lowerRect.midY)

                if isOn {
                    Circle()
                        .stroke(Color.white.opacity(0.76), lineWidth: 2)
                        .frame(width: size.width * 0.22, height: size.width * 0.22)
                        .position(x: upperRect.midX, y: upperRect.midY + upperRect.height * 0.05)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.32))
                        .frame(width: upperRect.width * 0.62, height: 4)
                        .position(x: upperRect.midX, y: upperRect.minY + 9)
                }

                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white.opacity(isOn ? 0.12 : 0.22))
                    .frame(width: lowerRect.width * 0.48, height: 3)
                    .position(x: lowerRect.midX, y: lowerRect.midY - lowerRect.height * 0.10)
            }
        }
    }
}

private struct KnobFace: View {
    var normalizedValue: Double

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let rect = CGRect(
                x: (proxy.size.width - size) / 2,
                y: (proxy.size.height - size) / 2,
                width: size,
                height: size
            )
            let angle = Angle.degrees(-135 + min(max(normalizedValue, 0), 1) * 270)

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.33, green: 0.37, blue: 0.39),
                                Color(red: 0.14, green: 0.16, blue: 0.18),
                            ],
                            center: .topLeading,
                            startRadius: 2,
                            endRadius: size * 0.62
                        )
                    )
                    .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1.2))
                    .shadow(color: .black.opacity(0.55), radius: 3, x: 0, y: 2)

                Circle()
                    .trim(from: 0.125, to: 0.875)
                    .stroke(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(90))
                    .frame(width: size * 0.92, height: size * 0.92)

                Rectangle()
                    .fill(Color.white.opacity(0.76))
                    .frame(width: 2.5, height: size * 0.35)
                    .offset(y: -size * 0.18)
                    .rotationEffect(angle)

                Circle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: size * 0.58, height: size * 0.58)
            }
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
        }
    }
}

private struct SevenSegmentDisplay: View {
    var text: String

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(displayCharacters.enumerated()), id: \.offset) { _, character in
                SevenSegmentCharacter(character: character)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(red: 0.03, green: 0.05, blue: 0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.green.opacity(0.22), lineWidth: 1)
                )
        )
    }

    private var displayCharacters: [Character] {
        Array(text)
    }
}

private struct SevenSegmentCharacter: View {
    var character: Character

    var body: some View {
        GeometryReader { proxy in
            let segments = activeSegments(for: character)
            let inactiveColor = Color.green.opacity(0.10)
            let activeColor = Color(red: 0.43, green: 1.0, blue: 0.12)

            ZStack {
                ForEach(SevenSegment.allCases, id: \.self) { segment in
                    segment.path(in: proxy.size)
                        .fill(segments.contains(segment) ? activeColor : inactiveColor)
                        .shadow(color: segments.contains(segment) ? activeColor.opacity(0.45) : .clear, radius: 2)
                }
            }
        }
        .aspectRatio(0.58, contentMode: .fit)
    }

    private func activeSegments(for character: Character) -> Set<SevenSegment> {
        switch character {
        case "0": return [.top, .upperLeft, .upperRight, .lowerLeft, .lowerRight, .bottom]
        case "1": return [.upperRight, .lowerRight]
        case "2": return [.top, .upperRight, .middle, .lowerLeft, .bottom]
        case "3": return [.top, .upperRight, .middle, .lowerRight, .bottom]
        case "4": return [.upperLeft, .upperRight, .middle, .lowerRight]
        case "5": return [.top, .upperLeft, .middle, .lowerRight, .bottom]
        case "6": return [.top, .upperLeft, .middle, .lowerLeft, .lowerRight, .bottom]
        case "7": return [.top, .upperRight, .lowerRight]
        case "8": return Set(SevenSegment.allCases)
        case "9": return [.top, .upperLeft, .upperRight, .middle, .lowerRight, .bottom]
        case "C", "c": return [.top, .upperLeft, .lowerLeft, .bottom]
        case "L", "l": return [.upperLeft, .lowerLeft, .bottom]
        case "R", "r": return [.top, .upperLeft, .upperRight, .middle, .lowerLeft]
        case "-": return [.middle]
        default: return []
        }
    }
}

private enum SevenSegment: CaseIterable {
    case top
    case upperLeft
    case upperRight
    case middle
    case lowerLeft
    case lowerRight
    case bottom

    func path(in size: CGSize) -> Path {
        let thickness = max(min(size.width, size.height) * 0.15, 2)
        let inset = thickness * 0.5
        let x0 = inset
        let x1 = size.width - inset
        let y0 = inset
        let y1 = size.height / 2
        let y2 = size.height - inset

        switch self {
        case .top:
            return horizontalSegment(from: CGPoint(x: x0 + thickness, y: y0), to: CGPoint(x: x1 - thickness, y: y0), thickness: thickness)
        case .middle:
            return horizontalSegment(from: CGPoint(x: x0 + thickness, y: y1), to: CGPoint(x: x1 - thickness, y: y1), thickness: thickness)
        case .bottom:
            return horizontalSegment(from: CGPoint(x: x0 + thickness, y: y2), to: CGPoint(x: x1 - thickness, y: y2), thickness: thickness)
        case .upperLeft:
            return verticalSegment(from: CGPoint(x: x0, y: y0 + thickness), to: CGPoint(x: x0, y: y1 - thickness * 0.5), thickness: thickness)
        case .upperRight:
            return verticalSegment(from: CGPoint(x: x1, y: y0 + thickness), to: CGPoint(x: x1, y: y1 - thickness * 0.5), thickness: thickness)
        case .lowerLeft:
            return verticalSegment(from: CGPoint(x: x0, y: y1 + thickness * 0.5), to: CGPoint(x: x0, y: y2 - thickness), thickness: thickness)
        case .lowerRight:
            return verticalSegment(from: CGPoint(x: x1, y: y1 + thickness * 0.5), to: CGPoint(x: x1, y: y2 - thickness), thickness: thickness)
        }
    }

    private func horizontalSegment(from start: CGPoint, to end: CGPoint, thickness: CGFloat) -> Path {
        var path = Path()
        let half = thickness / 2
        path.move(to: CGPoint(x: start.x - half, y: start.y))
        path.addLine(to: CGPoint(x: start.x, y: start.y - half))
        path.addLine(to: CGPoint(x: end.x, y: end.y - half))
        path.addLine(to: CGPoint(x: end.x + half, y: end.y))
        path.addLine(to: CGPoint(x: end.x, y: end.y + half))
        path.addLine(to: CGPoint(x: start.x, y: start.y + half))
        path.closeSubpath()
        return path
    }

    private func verticalSegment(from start: CGPoint, to end: CGPoint, thickness: CGFloat) -> Path {
        var path = Path()
        let half = thickness / 2
        path.move(to: CGPoint(x: start.x, y: start.y - half))
        path.addLine(to: CGPoint(x: start.x + half, y: start.y))
        path.addLine(to: CGPoint(x: end.x + half, y: end.y))
        path.addLine(to: CGPoint(x: end.x, y: end.y + half))
        path.addLine(to: CGPoint(x: end.x - half, y: end.y))
        path.addLine(to: CGPoint(x: start.x - half, y: start.y))
        path.closeSubpath()
        return path
    }
}
