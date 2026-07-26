import SwiftUI

struct ParameterKnob: View {
    var label: String
    @Binding var value: Int
    var range: ClosedRange<Int>
    var width: CGFloat = 82
    var knobSize: CGFloat = 48

    @State private var dragStartValue: Int?

    var body: some View {
        VStack(spacing: 5) {
            SevenSegmentDisplay(text: displayText)
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
                            let delta = Int((-gesture.translation.height / pointsPerFullTravel * CGFloat(span)).rounded())
                            setValue(startValue + delta)
                        }
                        .onEnded { _ in
                            dragStartValue = nil
                        }
                )
                .accessibilityLabel(label)
                .accessibilityValue("\(value)")
                .help("\(label): drag up to increase, drag down to decrease.")

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

    private var normalizedValue: Double {
        let span = max(range.upperBound - range.lowerBound, 1)
        return Double(value - range.lowerBound) / Double(span)
    }

    private var displayText: String {
        let maximumDigits = max("\(range.lowerBound)".count, "\(range.upperBound)".count)
        if value < 0 {
            return String(format: "%0\(maximumDigits)d", value)
        }
        return String(format: "%0\(maximumDigits)d", value)
    }

    private func setValue(_ proposedValue: Int) {
        value = min(max(proposedValue, range.lowerBound), range.upperBound)
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
