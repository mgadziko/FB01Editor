import FB01Editor
import SwiftUI

struct FMRoutingPatchBayView: View {
    @Binding var name: String
    @Binding var algorithm: Int
    @Binding var feedback: Int
    @Binding var userCode: Int
    @Binding var lfoSpeed: Int
    @Binding var lfoWaveform: Int
    @Binding var loadLFODataEnabled: Bool
    @Binding var lfoSyncEnabled: Bool
    @Binding var amplitudeModulationDepth: Int
    @Binding var pitchModulationDepth: Int
    @Binding var amplitudeModulationSensitivity: Int
    @Binding var pitchModulationSensitivity: Int
    @Binding var transpose: Int
    @Binding var leftOutputEnabled: Bool
    @Binding var rightOutputEnabled: Bool
    @Binding var voiceCharacterType: VoiceCharacterType
    var macroValue: (PerformanceMacro) -> Binding<Int>
    var operators: [FB01VoiceOperatorData]
    var operatorEnabled: [Binding<Bool>]
    @Binding var selectedOperatorIndex: Int
    var updateOperator: (FB01VoiceOperatorData) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle("FM Routing Patch Bay")

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    globalVoicePanel
                    modulationPanel
                }

                VStack(alignment: .leading, spacing: 14) {
                    globalVoicePanel
                    modulationPanel
                }
            }

            macroPanel
                .frame(maxWidth: .infinity, alignment: .center)

            algorithmChooser
                .frame(maxWidth: .infinity, alignment: .center)

            routedOperatorPatchBay
        }
    }

    private var globalVoicePanel: some View {
        OperatorControlGroup(title: "Voice and Output") {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                        GridRow {
                            Text("Name")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            TextField("Name", text: $name)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 180)
                        }
                    }

                    HStack(alignment: .top, spacing: 14) {
                        ParameterKnob(label: "User Code", value: $userCode, range: 0...255)
                        ParameterKnob(label: "Transpose", value: $transpose, range: -128...127)
                    }
                }
                .frame(width: 238, alignment: .topLeading)

                HStack(alignment: .top, spacing: 12) {
                    RockerSwitch(label: "Left Output", isOn: $leftOutputEnabled, width: 70, height: 62)
                    RockerSwitch(label: "Right Output", isOn: $rightOutputEnabled, width: 74, height: 62)
                }
                .padding(.top, 49)
            }
        }
        .frame(minWidth: 430, maxWidth: 520, alignment: .topLeading)
    }

    private var algorithmChooser: some View {
        OperatorControlGroup(title: "Algorithm") {
            CompactAlgorithmSelectorView(selection: $algorithm)
        }
        .frame(width: 780, alignment: .center)
    }

    private var modulationPanel: some View {
        OperatorControlGroup(title: "Global LFO and Modulation") {
            HStack(alignment: .top, spacing: 12) {
                ParameterKnob(label: "LFO Speed", value: $lfoSpeed, range: 0...255)
                ParameterKnob(label: "Amplitude MOD\nDepth", value: $amplitudeModulationDepth, range: 0...127)
                ParameterKnob(label: "Pitch MOD\nDepth", value: $pitchModulationDepth, range: 0...127)
                ParameterKnob(label: "Amplitude MOD\nSensitivity", value: $amplitudeModulationSensitivity, range: 0...3)
                ParameterKnob(label: "Pitch MOD\nSensitivity", value: $pitchModulationSensitivity, range: 0...7)
            }

            HStack(alignment: .top, spacing: 14) {
                WaveformPicker(selection: $lfoWaveform)
                    .frame(width: 342)

                RockerSwitch(label: "Load LFO Data", isOn: $loadLFODataEnabled, width: 76, height: 58)
                RockerSwitch(label: "LFO Sync", isOn: $lfoSyncEnabled, width: 62, height: 58)
            }
        }
        .frame(minWidth: 520, maxWidth: 680, alignment: .topLeading)
    }

    private var macroPanel: some View {
        OperatorControlGroup(title: "Performance Macros") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("Voice Character Type")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Picker("Voice Character Type", selection: $voiceCharacterType) {
                        ForEach(VoiceCharacterType.allCases) { characterType in
                            Text(characterType.title).tag(characterType)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 180)

                    Text("These musical macros change the current editable voice in memory only. They are not stored FB-01 fields.")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                LazyVGrid(columns: Array(repeating: GridItem(.fixed(92), spacing: 12), count: 4), alignment: .leading, spacing: 12) {
                    ForEach(PerformanceMacro.allCases) { macro in
                        VStack(spacing: 3) {
                            ParameterKnob(
                                label: macro.title,
                                value: macroValue(macro),
                                range: PerformanceMacro.range,
                                width: 88,
                                knobSize: 46
                            )
                        }
                        .help(macro.help(for: voiceCharacterType))
                    }
                }

                Text(PerformanceMacro.summary(for: voiceCharacterType))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: 780, alignment: .leading)
    }

    private var routedOperatorPatchBay: some View {
        let layout = FMPatchBayLayout(algorithm: algorithm)
        return ScrollView(.horizontal) {
            FMPatchBayCanvas(
                layout: layout,
                operatorsByNumber: operatorsByNumber,
                operatorEnabledBinding: operatorEnabledBinding,
                feedback: $feedback,
                selectedOperatorIndex: $selectedOperatorIndex,
                updateOperator: updateOperator
            )
            .frame(width: layout.size.width, height: layout.size.height)
        }
        .frame(height: layout.size.height)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var operatorsByNumber: [Int: FB01VoiceOperatorData] {
        Dictionary(uniqueKeysWithValues: operators.map { operatorData in
            (FB01VoiceData.operatorNumber(forDataIndex: operatorData.index), operatorData)
        })
    }

    private func operatorEnabledBinding(for index: Int) -> Binding<Bool> {
        guard operatorEnabled.indices.contains(index) else {
            return .constant(true)
        }
        return operatorEnabled[index]
    }
}

enum VoiceCharacterType: String, CaseIterable, Identifiable {
    case piano
    case brass
    case bass
    case bell
    case organ
    case strings
    case wind
    case percussion
    case synthetic
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .piano: return "Piano"
        case .brass: return "Brass"
        case .bass: return "Bass"
        case .bell: return "Bell"
        case .organ: return "Organ"
        case .strings: return "Strings"
        case .wind: return "Wind"
        case .percussion: return "Percussion"
        case .synthetic: return "Synthetic"
        case .other: return "Other"
        }
    }
}

enum PerformanceMacro: String, CaseIterable, Identifiable {
    case brightness
    case warmth
    case bite
    case body
    case motion
    case punch
    case air
    case character

    static let range = 0...127
    static let neutralValue = 64
    static let neutralValues = Dictionary(uniqueKeysWithValues: PerformanceMacro.allCases.map { ($0, neutralValue) })

    var id: String { rawValue }

    var title: String {
        switch self {
        case .brightness: return "Brightness"
        case .warmth: return "Warmth"
        case .bite: return "Bite"
        case .body: return "Body"
        case .motion: return "Motion"
        case .punch: return "Punch"
        case .air: return "Air"
        case .character: return "Character"
        }
    }

    func help(for characterType: VoiceCharacterType) -> String {
        "\(title): \(touchedParametersDescription(for: characterType)). This changes the current editable voice only."
    }

    func touchedParametersDescription(for characterType: VoiceCharacterType) -> String {
        switch self {
        case .brightness:
            return "modulator level, feedback, and pitch modulation depth"
        case .warmth:
            return "modulator level, feedback, and release"
        case .bite:
            return "attack, velocity-to-attack, and modulator level"
        case .body:
            return "carrier level and sustain"
        case .motion:
            return "LFO speed plus amplitude and pitch modulation depth"
        case .punch:
            return "attack, decay, sustain, and velocity response"
        case .air:
            return "release, pitch modulation depth, and upper modulation level"
        case .character:
            return "\(characterType.title.lowercased())-aware operator balance, envelope, and feedback"
        }
    }

    static func summary(for characterType: VoiceCharacterType) -> String {
        "Neutral is 64. Moving a macro above or below neutral applies musical deltas to FB-01 parameters. Character currently uses the \(characterType.title) recipe."
    }

    func apply(previousValue: Int, newValue: Int, characterType: VoiceCharacterType, to voice: FB01VoiceData) throws -> FB01VoiceData {
        let delta = newValue - previousValue
        guard delta != 0 else { return voice }

        switch self {
        case .brightness:
            return try voice
                .adjustingOperators(carriers: false, delta: delta) { operatorData, delta in
                    try operatorData.settingTotalLevel(adjust(operatorData.totalLevel, by: -scaled(delta, 0.30), in: 0...127))
                }
                .settingFeedbackLevel(adjust(voice.feedbackLevel, by: scaled(delta, 0.05), in: 0...7))
                .settingPitchModulationDepth(adjust(voice.pitchModulationDepth, by: scaled(delta, 0.12), in: 0...127))
        case .warmth:
            return try voice
                .adjustingOperators(carriers: false, delta: delta) { operatorData, delta in
                    try operatorData
                        .settingTotalLevel(adjust(operatorData.totalLevel, by: scaled(delta, 0.25), in: 0...127))
                        .settingReleaseRate(adjust(operatorData.releaseRate, by: scaled(delta, 0.03), in: 0...15))
                }
                .settingFeedbackLevel(adjust(voice.feedbackLevel, by: -scaled(delta, 0.05), in: 0...7))
        case .bite:
            return try voice.adjustingOperators(carriers: nil, delta: delta) { operatorData, delta in
                var updated = try operatorData
                    .settingAttackRate(adjust(operatorData.attackRate, by: scaled(delta, 0.16), in: 0...31))
                    .settingVelocitySensitivityForAttackRate(adjust(operatorData.velocitySensitivityForAttackRate, by: scaled(delta, 0.05), in: 0...7))
                if !operatorData.carrier {
                    updated = try updated.settingTotalLevel(adjust(operatorData.totalLevel, by: -scaled(delta, 0.16), in: 0...127))
                }
                return updated
            }
        case .body:
            return try voice.adjustingOperators(carriers: true, delta: delta) { operatorData, delta in
                try operatorData
                    .settingTotalLevel(adjust(operatorData.totalLevel, by: -scaled(delta, 0.25), in: 0...127))
                    .settingSustainLevel(adjust(operatorData.sustainLevel, by: scaled(delta, 0.05), in: 0...15))
            }
        case .motion:
            return try voice
                .settingLFOSpeed(adjust(voice.lfoSpeed, by: scaled(delta, 0.65), in: 0...255))
                .settingAmplitudeModulationDepth(adjust(voice.amplitudeModulationDepth, by: scaled(delta, 0.20), in: 0...127))
                .settingPitchModulationDepth(adjust(voice.pitchModulationDepth, by: scaled(delta, 0.20), in: 0...127))
        case .punch:
            return try voice.adjustingOperators(carriers: nil, delta: delta) { operatorData, delta in
                try operatorData
                    .settingAttackRate(adjust(operatorData.attackRate, by: scaled(delta, 0.18), in: 0...31))
                    .settingDecay1Rate(adjust(operatorData.decay1Rate, by: scaled(delta, 0.08), in: 0...15))
                    .settingSustainLevel(adjust(operatorData.sustainLevel, by: -scaled(delta, 0.05), in: 0...15))
                    .settingVelocitySensitivityForTotalLevel(adjust(operatorData.velocitySensitivityForTotalLevel, by: scaled(delta, 0.04), in: 0...7))
            }
        case .air:
            return try voice
                .adjustingOperators(carriers: false, delta: delta) { operatorData, delta in
                    try operatorData
                        .settingTotalLevel(adjust(operatorData.totalLevel, by: -scaled(delta, 0.10), in: 0...127))
                        .settingReleaseRate(adjust(operatorData.releaseRate, by: scaled(delta, 0.06), in: 0...15))
                }
                .settingPitchModulationDepth(adjust(voice.pitchModulationDepth, by: scaled(delta, 0.10), in: 0...127))
        case .character:
            return try applyCharacter(delta: delta, characterType: characterType, to: voice)
        }
    }

    private func applyCharacter(delta: Int, characterType: VoiceCharacterType, to voice: FB01VoiceData) throws -> FB01VoiceData {
        switch characterType {
        case .piano:
            return try voice.adjustingOperators(carriers: false, delta: delta) { operatorData, delta in
                try operatorData
                    .settingDecay1Rate(adjust(operatorData.decay1Rate, by: scaled(delta, 0.10), in: 0...15))
                    .settingSustainLevel(adjust(operatorData.sustainLevel, by: -scaled(delta, 0.05), in: 0...15))
            }
        case .brass:
            return try voice
                .adjustingOperators(carriers: false, delta: delta) { operatorData, delta in
                    try operatorData.settingTotalLevel(adjust(operatorData.totalLevel, by: -scaled(delta, 0.20), in: 0...127))
                }
                .settingFeedbackLevel(adjust(voice.feedbackLevel, by: scaled(delta, 0.06), in: 0...7))
        case .bass:
            return try voice.adjustingOperators(carriers: true, delta: delta) { operatorData, delta in
                try operatorData
                    .settingTotalLevel(adjust(operatorData.totalLevel, by: -scaled(delta, 0.18), in: 0...127))
                    .settingReleaseRate(adjust(operatorData.releaseRate, by: -scaled(delta, 0.04), in: 0...15))
            }
        case .bell:
            return try voice
                .adjustingOperators(carriers: false, delta: delta) { operatorData, delta in
                    try operatorData
                        .settingMultiple(adjust(operatorData.multiple, by: scaled(delta, 0.03), in: 0...15))
                        .settingSustainLevel(adjust(operatorData.sustainLevel, by: -scaled(delta, 0.08), in: 0...15))
                        .settingReleaseRate(adjust(operatorData.releaseRate, by: scaled(delta, 0.06), in: 0...15))
                }
                .settingFeedbackLevel(adjust(voice.feedbackLevel, by: scaled(delta, 0.06), in: 0...7))
        case .organ:
            return try voice.adjustingOperators(carriers: nil, delta: delta) { operatorData, delta in
                try operatorData
                    .settingSustainLevel(adjust(operatorData.sustainLevel, by: scaled(delta, 0.08), in: 0...15))
                    .settingReleaseRate(adjust(operatorData.releaseRate, by: scaled(delta, 0.03), in: 0...15))
            }
        case .strings:
            return try voice
                .adjustingOperators(carriers: true, delta: delta) { operatorData, delta in
                    try operatorData
                        .settingAttackRate(adjust(operatorData.attackRate, by: -scaled(delta, 0.10), in: 0...31))
                        .settingReleaseRate(adjust(operatorData.releaseRate, by: scaled(delta, 0.07), in: 0...15))
                }
                .settingAmplitudeModulationDepth(adjust(voice.amplitudeModulationDepth, by: scaled(delta, 0.08), in: 0...127))
        case .wind:
            return try voice
                .adjustingOperators(carriers: nil, delta: delta) { operatorData, delta in
                    try operatorData.settingVelocitySensitivityForTotalLevel(adjust(operatorData.velocitySensitivityForTotalLevel, by: scaled(delta, 0.05), in: 0...7))
                }
                .settingPitchModulationDepth(adjust(voice.pitchModulationDepth, by: scaled(delta, 0.10), in: 0...127))
        case .percussion:
            return try voice.adjustingOperators(carriers: nil, delta: delta) { operatorData, delta in
                try operatorData
                    .settingAttackRate(adjust(operatorData.attackRate, by: scaled(delta, 0.18), in: 0...31))
                    .settingDecay2Rate(adjust(operatorData.decay2Rate, by: scaled(delta, 0.12), in: 0...31))
                    .settingSustainLevel(adjust(operatorData.sustainLevel, by: -scaled(delta, 0.10), in: 0...15))
            }
        case .synthetic:
            return try voice
                .adjustingOperators(carriers: false, delta: delta) { operatorData, delta in
                    try operatorData
                        .settingTotalLevel(adjust(operatorData.totalLevel, by: -scaled(delta, 0.22), in: 0...127))
                        .settingDetune1(adjust(operatorData.detune1, by: scaled(delta, 0.03), in: 0...7))
                }
                .settingFeedbackLevel(adjust(voice.feedbackLevel, by: scaled(delta, 0.07), in: 0...7))
        case .other:
            return try voice
                .adjustingOperators(carriers: false, delta: delta) { operatorData, delta in
                    try operatorData.settingTotalLevel(adjust(operatorData.totalLevel, by: -scaled(delta, 0.16), in: 0...127))
                }
                .settingFeedbackLevel(adjust(voice.feedbackLevel, by: scaled(delta, 0.04), in: 0...7))
        }
    }

    private func scaled(_ delta: Int, _ factor: Double) -> Int {
        let value = Int((Double(delta) * factor).rounded())
        if value == 0, delta != 0, factor > 0 {
            return delta > 0 ? 1 : -1
        }
        return value
    }

    private func adjust(_ value: Int, by delta: Int, in range: ClosedRange<Int>) -> Int {
        min(max(value + delta, range.lowerBound), range.upperBound)
    }
}

enum MIDIControlChangeLabel {
    static let range = 0...127
    static let allControllers = Array(range)

    static func title(for controller: Int) -> String {
        "\(controller) \(name(for: controller))"
    }

    private static func name(for controller: Int) -> String {
        switch controller {
        case 0: return "Bank Select"
        case 1: return "Mod Wheel"
        case 2: return "Breath Controller"
        case 3: return "Undefined"
        case 4: return "Foot Controller"
        case 5: return "Portamento Time"
        case 6: return "Data Entry MSB"
        case 7: return "Channel Volume"
        case 8: return "Balance"
        case 9: return "Undefined"
        case 10: return "Pan"
        case 11: return "Expression"
        case 12: return "Effect Control 1"
        case 13: return "Effect Control 2"
        case 14...15: return "Undefined"
        case 16...19: return "General Purpose"
        case 20...31: return "Undefined"
        case 32: return "Bank Select LSB"
        case 33: return "Mod Wheel LSB"
        case 34: return "Breath Controller LSB"
        case 35: return "Undefined LSB"
        case 36: return "Foot Controller LSB"
        case 37: return "Portamento Time LSB"
        case 38: return "Data Entry LSB"
        case 39: return "Channel Volume LSB"
        case 40: return "Balance LSB"
        case 41: return "Undefined LSB"
        case 42: return "Pan LSB"
        case 43: return "Expression LSB"
        case 44: return "Effect Control 1 LSB"
        case 45: return "Effect Control 2 LSB"
        case 46...63: return "Undefined LSB"
        case 64: return "Sustain Pedal"
        case 65: return "Portamento"
        case 66: return "Sostenuto"
        case 67: return "Soft Pedal"
        case 68: return "Legato Footswitch"
        case 69: return "Hold 2"
        case 70: return "Sound Variation"
        case 71: return "Timbre Resonance"
        case 72: return "Release Time"
        case 73: return "Attack Time"
        case 74: return "Brightness"
        case 75: return "Decay Time"
        case 76: return "Vibrato Rate"
        case 77: return "Vibrato Depth"
        case 78: return "Vibrato Delay"
        case 79: return "Sound Controller 10"
        case 80...83: return "General Purpose"
        case 84: return "Portamento Control"
        case 85...87: return "Undefined"
        case 88: return "High Resolution Velocity"
        case 89...90: return "Undefined"
        case 91: return "Effects 1 Depth"
        case 92: return "Effects 2 Depth"
        case 93: return "Effects 3 Depth"
        case 94: return "Effects 4 Depth"
        case 95: return "Effects 5 Depth"
        case 96: return "Data Increment"
        case 97: return "Data Decrement"
        case 98: return "NRPN LSB"
        case 99: return "NRPN MSB"
        case 100: return "RPN LSB"
        case 101: return "RPN MSB"
        case 102...119: return "Undefined"
        case 120: return "All Sound Off"
        case 121: return "Reset Controllers"
        case 122: return "Local Control"
        case 123: return "All Notes Off"
        case 124: return "Omni Off"
        case 125: return "Omni On"
        case 126: return "Mono On"
        case 127: return "Poly On"
        default: return "Invalid"
        }
    }
}

private extension FB01VoiceData {
    func adjustingOperators(
        carriers carrierFilter: Bool?,
        delta: Int,
        update: (FB01VoiceOperatorData, Int) throws -> FB01VoiceOperatorData
    ) throws -> FB01VoiceData {
        var editedVoice = self
        for operatorData in operators where carrierFilter == nil || operatorData.carrier == carrierFilter {
            let updatedOperator = try update(operatorData, delta)
            editedVoice = try editedVoice.replacingOperator(updatedOperator)
        }
        return editedVoice
    }
}

private struct FMPatchBayLayout {
    struct Route: Identifiable {
        enum Kind {
            case modulation
            case carrier
            case feedback
        }

        var id: String
        var points: [CGPoint]
        var kind: Kind
        var arrowAtEnd = true
    }

    let algorithm: Int
    let positions: [Int: CGPoint]
    let routes: [Route]
    let sumPoints: [CGPoint]
    let outputPoint: CGPoint
    let feedbackControlCenter: CGPoint

    static let moduleSize = CGSize(width: 390, height: 1240)
    static let margin: CGFloat = 170
    static let horizontalGap: CGFloat = 96
    static let verticalGap: CGFloat = 120

    var size: CGSize {
        let maxX = positions.values.map { $0.x }.max() ?? 0
        let maxY = positions.values.map { $0.y }.max() ?? 0
        let routeMaxX = routes.flatMap(\.points).map(\.x).max() ?? 0
        let routeMaxY = routes.flatMap(\.points).map(\.y).max() ?? 0
        let controlMaxX = feedbackControlCenter.x + 58
        let controlMaxY = feedbackControlCenter.y + 58
        return CGSize(
            width: max(max(maxX + Self.moduleSize.width, routeMaxX, controlMaxX) + Self.margin, 820),
            height: max(max(maxY + Self.moduleSize.height, routeMaxY, controlMaxY) + 96, outputPoint.y + 72)
        )
    }

    init(algorithm: Int) {
        self.algorithm = min(max(algorithm, 1), 8)
        let layout = Self.makeLayout(for: self.algorithm)
        positions = layout.positions
        routes = layout.routes
        sumPoints = layout.sumPoints
        outputPoint = layout.outputPoint
        feedbackControlCenter = layout.feedbackControlCenter
    }

    private static func makeLayout(for algorithm: Int) -> (
        positions: [Int: CGPoint],
        routes: [Route],
        sumPoints: [CGPoint],
        outputPoint: CGPoint,
        feedbackControlCenter: CGPoint
    ) {
        let w = moduleSize.width
        let h = moduleSize.height
        let m = margin
        let hg = horizontalGap
        let vg = verticalGap
        let stepX = w + hg
        let stepY = h + vg

        func point(_ column: Int, _ row: Int) -> CGPoint {
            CGPoint(x: m + CGFloat(column) * stepX, y: m + CGFloat(row) * stepY)
        }

        func rect(_ number: Int, in positions: [Int: CGPoint]) -> CGRect {
            CGRect(origin: positions[number] ?? .zero, size: moduleSize)
        }

        func top(_ number: Int, in positions: [Int: CGPoint]) -> CGPoint {
            let r = rect(number, in: positions)
            return CGPoint(x: r.midX, y: r.minY - 18)
        }

        func bottom(_ number: Int, in positions: [Int: CGPoint]) -> CGPoint {
            let r = rect(number, in: positions)
            return CGPoint(x: r.midX, y: r.maxY + 18)
        }

        func right(_ number: Int, in positions: [Int: CGPoint]) -> CGPoint {
            let r = rect(number, in: positions)
            return CGPoint(x: r.maxX + 22, y: r.midY)
        }

        func left(_ number: Int, in positions: [Int: CGPoint]) -> CGPoint {
            let r = rect(number, in: positions)
            return CGPoint(x: r.minX - 22, y: r.midY)
        }

        func route(_ id: String, _ points: [CGPoint], kind: Route.Kind = .modulation, arrowAtEnd: Bool = true) -> Route {
            Route(id: id, points: points, kind: kind, arrowAtEnd: arrowAtEnd)
        }

        func feedbackRoute(_ positions: [Int: CGPoint]) -> Route {
            let r = rect(4, in: positions)
            let sideX = r.maxX + 82
            let topY = r.minY + 90
            let bottomY = r.minY + 390
            return route(
                "feedback-4",
                [
                    CGPoint(x: r.maxX + 16, y: topY),
                    CGPoint(x: sideX, y: topY),
                    CGPoint(x: sideX, y: bottomY),
                    CGPoint(x: r.maxX + 16, y: bottomY),
                ],
                kind: .feedback
            )
        }

        func feedbackControl(_ positions: [Int: CGPoint]) -> CGPoint {
            let r = rect(4, in: positions)
            return CGPoint(x: r.maxX + 82, y: r.minY + 240)
        }

        func outputRoutes(_ carriers: [Int], positions: [Int: CGPoint], output: CGPoint) -> [Route] {
            let busY = output.y - 42
            let points = carriers.map { bottom($0, in: positions) }
            guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max() else {
                return []
            }
            var routes = points.map { source in
                route("op\(Int(source.x))-to-output-bus", [source, CGPoint(x: source.x, y: busY)], kind: .carrier, arrowAtEnd: false)
            }
            routes.append(route("output-bus", [CGPoint(x: minX, y: busY), CGPoint(x: maxX, y: busY)], kind: .carrier, arrowAtEnd: false))
            routes.append(route("output-arrow", [CGPoint(x: (minX + maxX) / 2, y: busY), output], kind: .carrier))
            return routes
        }

        var positions: [Int: CGPoint]
        var routes: [Route] = []
        var sumPoints: [CGPoint] = []
        var outputPoint: CGPoint

        switch algorithm {
        case 1:
            positions = [4: point(0, 0), 3: point(0, 1), 2: point(0, 2), 1: point(0, 3)]
            outputPoint = CGPoint(x: rect(1, in: positions).midX, y: rect(1, in: positions).maxY + 88)
            routes = [
                route("4-3", [bottom(4, in: positions), top(3, in: positions)]),
                route("3-2", [bottom(3, in: positions), top(2, in: positions)]),
                route("2-1", [bottom(2, in: positions), top(1, in: positions)]),
                feedbackRoute(positions),
            ] + outputRoutes([1], positions: positions, output: outputPoint)
        case 2:
            positions = [3: point(0, 0), 4: point(1, 0), 2: CGPoint(x: point(0, 1).x + stepX / 2, y: point(0, 1).y), 1: CGPoint(x: point(0, 2).x + stepX / 2, y: point(0, 2).y)]
            let sum = CGPoint(x: rect(2, in: positions).midX, y: rect(2, in: positions).minY - 58)
            sumPoints = [sum]
            outputPoint = CGPoint(x: rect(1, in: positions).midX, y: rect(1, in: positions).maxY + 88)
            routes = [
                route("3-sum", [bottom(3, in: positions), CGPoint(x: bottom(3, in: positions).x, y: sum.y), sum]),
                route("4-sum", [bottom(4, in: positions), CGPoint(x: bottom(4, in: positions).x, y: sum.y), sum]),
                route("sum-2", [sum, top(2, in: positions)]),
                route("2-1", [bottom(2, in: positions), top(1, in: positions)]),
                feedbackRoute(positions),
            ] + outputRoutes([1], positions: positions, output: outputPoint)
        case 3:
            positions = [3: point(0, 0), 2: point(0, 1), 4: point(1, 1), 1: CGPoint(x: point(0, 2).x + stepX / 2, y: point(0, 2).y)]
            let sum = CGPoint(x: rect(1, in: positions).midX, y: rect(1, in: positions).minY - 58)
            sumPoints = [sum]
            outputPoint = CGPoint(x: rect(1, in: positions).midX, y: rect(1, in: positions).maxY + 88)
            routes = [
                route("3-2", [bottom(3, in: positions), top(2, in: positions)]),
                route("2-sum", [bottom(2, in: positions), CGPoint(x: bottom(2, in: positions).x, y: sum.y), sum]),
                route("4-sum", [bottom(4, in: positions), CGPoint(x: bottom(4, in: positions).x, y: sum.y), sum]),
                route("sum-1", [sum, top(1, in: positions)]),
                feedbackRoute(positions),
            ] + outputRoutes([1], positions: positions, output: outputPoint)
        case 4:
            positions = [4: point(1, 0), 2: point(0, 1), 3: point(1, 1), 1: CGPoint(x: point(0, 2).x + stepX / 2, y: point(0, 2).y)]
            let sum = CGPoint(x: rect(1, in: positions).midX, y: rect(1, in: positions).minY - 58)
            sumPoints = [sum]
            outputPoint = CGPoint(x: rect(1, in: positions).midX, y: rect(1, in: positions).maxY + 88)
            routes = [
                route("4-3", [bottom(4, in: positions), top(3, in: positions)]),
                route("2-sum", [bottom(2, in: positions), CGPoint(x: bottom(2, in: positions).x, y: sum.y), sum]),
                route("3-sum", [bottom(3, in: positions), CGPoint(x: bottom(3, in: positions).x, y: sum.y), sum]),
                route("sum-1", [sum, top(1, in: positions)]),
                feedbackRoute(positions),
            ] + outputRoutes([1], positions: positions, output: outputPoint)
        case 5:
            positions = [2: point(0, 0), 4: point(1, 0), 1: point(0, 1), 3: point(1, 1)]
            outputPoint = CGPoint(x: (rect(1, in: positions).midX + rect(3, in: positions).midX) / 2, y: max(rect(1, in: positions).maxY, rect(3, in: positions).maxY) + 88)
            routes = [
                route("2-1", [bottom(2, in: positions), top(1, in: positions)]),
                route("4-3", [bottom(4, in: positions), top(3, in: positions)]),
                feedbackRoute(positions),
            ] + outputRoutes([1, 3], positions: positions, output: outputPoint)
        case 6:
            positions = [4: CGPoint(x: point(1, 0).x, y: point(1, 0).y), 1: point(0, 1), 2: point(1, 1), 3: point(2, 1)]
            let split = CGPoint(x: rect(4, in: positions).midX, y: rect(1, in: positions).minY - 58)
            let busLeft = CGPoint(x: rect(1, in: positions).midX, y: split.y)
            let busRight = CGPoint(x: rect(3, in: positions).midX, y: split.y)
            sumPoints = [split]
            outputPoint = CGPoint(x: rect(2, in: positions).midX, y: rect(2, in: positions).maxY + 88)
            routes = [
                route("4-split", [bottom(4, in: positions), split]),
                route("split-bus", [busLeft, busRight], arrowAtEnd: false),
                route("split-1", [CGPoint(x: rect(1, in: positions).midX, y: split.y), top(1, in: positions)]),
                route("split-2", [CGPoint(x: rect(2, in: positions).midX, y: split.y), top(2, in: positions)]),
                route("split-3", [CGPoint(x: rect(3, in: positions).midX, y: split.y), top(3, in: positions)]),
                feedbackRoute(positions),
            ] + outputRoutes([1, 2, 3], positions: positions, output: outputPoint)
        case 7:
            positions = [4: point(2, 0), 1: point(0, 1), 2: point(1, 1), 3: point(2, 1)]
            outputPoint = CGPoint(x: rect(2, in: positions).midX, y: rect(2, in: positions).maxY + 88)
            routes = [
                route("4-3", [bottom(4, in: positions), top(3, in: positions)]),
                feedbackRoute(positions),
            ] + outputRoutes([1, 2, 3], positions: positions, output: outputPoint)
        default:
            positions = [1: point(0, 0), 2: point(1, 0), 3: point(2, 0), 4: point(3, 0)]
            outputPoint = CGPoint(x: (rect(1, in: positions).midX + rect(4, in: positions).midX) / 2, y: rect(1, in: positions).maxY + 88)
            routes = [
                feedbackRoute(positions),
            ] + outputRoutes([1, 2, 3, 4], positions: positions, output: outputPoint)
        }

        return (positions, routes, sumPoints, outputPoint, feedbackControl(positions))
    }
}

private struct FMPatchBayCanvas: View {
    var layout: FMPatchBayLayout
    var operatorsByNumber: [Int: FB01VoiceOperatorData]
    var operatorEnabledBinding: (Int) -> Binding<Bool>
    @Binding var feedback: Int
    @Binding var selectedOperatorIndex: Int
    var updateOperator: (FB01VoiceOperatorData) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.045))
                .allowsHitTesting(false)

            FMPatchBayRouteCanvas(layout: layout)
                .allowsHitTesting(false)

            Text("Output")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .position(x: layout.outputPoint.x, y: layout.outputPoint.y + 22)
                .allowsHitTesting(false)

            ParameterKnob(label: "OP4 Feedback", value: $feedback, range: 0...7)
                .position(layout.feedbackControlCenter)

            ForEach(1...4, id: \.self) { number in
                if let operatorData = operatorsByNumber[number],
                   let origin = layout.positions[number] {
                    FMPatchOperatorModule(
                        operatorData: operatorData,
                        operatorEnabled: operatorEnabledBinding(operatorData.index),
                        isSelected: operatorData.index == selectedOperatorIndex,
                        select: { selectedOperatorIndex = operatorData.index },
                        updateOperator: updateOperator
                    )
                    .frame(
                        width: FMPatchBayLayout.moduleSize.width,
                        height: FMPatchBayLayout.moduleSize.height,
                        alignment: .topLeading
                    )
                    .position(
                        x: origin.x + FMPatchBayLayout.moduleSize.width / 2,
                        y: origin.y + FMPatchBayLayout.moduleSize.height / 2
                    )
                }
            }
        }
    }
}

private struct FMPatchBayRouteCanvas: View {
    var layout: FMPatchBayLayout

    var body: some View {
        Canvas { context, _ in
            for route in layout.routes {
                guard route.points.count >= 2 else {
                    continue
                }
                let color = color(for: route.kind)
                var path = Path()
                path.move(to: route.points[0])
                for point in route.points.dropFirst() {
                    path.addLine(to: point)
                }
                context.stroke(
                    path,
                    with: .color(color),
                    style: StrokeStyle(lineWidth: route.kind == .feedback ? 2.2 : 2.6, lineCap: .round, lineJoin: .round)
                )

                if route.arrowAtEnd,
                   let end = route.points.last,
                   let previous = route.points.dropLast().last {
                    drawArrowHead(context: context, from: previous, to: end, color: color)
                }
            }

            for point in layout.sumPoints {
                let rect = CGRect(x: point.x - 12, y: point.y - 12, width: 24, height: 24)
                context.fill(Path(ellipseIn: rect), with: .color(Color(nsColor: .controlBackgroundColor)))
                context.stroke(Path(ellipseIn: rect), with: .color(.blue.opacity(0.78)), lineWidth: 1.6)
                context.draw(
                    context.resolve(Text("+").font(.caption.weight(.bold)).foregroundStyle(.primary)),
                    at: point
                )
            }

            let outputRect = CGRect(x: layout.outputPoint.x - 9, y: layout.outputPoint.y - 9, width: 18, height: 18)
            context.fill(Path(ellipseIn: outputRect), with: .color(Color.green.opacity(0.24)))
            context.stroke(Path(ellipseIn: outputRect), with: .color(Color.green.opacity(0.86)), lineWidth: 1.4)
        }
    }

    private func color(for kind: FMPatchBayLayout.Route.Kind) -> Color {
        switch kind {
        case .modulation:
            return .blue.opacity(0.86)
        case .carrier:
            return .green.opacity(0.86)
        case .feedback:
            return .orange.opacity(0.92)
        }
    }

    private func drawArrowHead(context: GraphicsContext, from start: CGPoint, to end: CGPoint, color: Color) {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let length: CGFloat = 10
        let spread: CGFloat = 0.58
        let left = CGPoint(
            x: end.x - length * cos(angle - spread),
            y: end.y - length * sin(angle - spread)
        )
        let right = CGPoint(
            x: end.x - length * cos(angle + spread),
            y: end.y - length * sin(angle + spread)
        )
        var head = Path()
        head.move(to: left)
        head.addLine(to: end)
        head.addLine(to: right)
        context.stroke(head, with: .color(color), style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
    }
}

struct FMPatchOperatorModule: View {
    var operatorData: FB01VoiceOperatorData
    @Binding var operatorEnabled: Bool
    var isSelected: Bool
    var select: () -> Void
    var updateOperator: (FB01VoiceOperatorData) -> Void

    private var operatorNumber: Int {
        FB01VoiceData.operatorNumber(forDataIndex: operatorData.index)
    }

    private var controlColumns: [GridItem] {
        [
            GridItem(.adaptive(minimum: 82), spacing: 12),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Operator \(operatorNumber)")
                    .font(.headline)
                Text(operatorData.carrier ? "Carrier to Output" : "Modulator")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(operatorData.carrier ? Color.green : Color.blue)
                Spacer()
                Image(systemName: operatorEnabled ? "power.circle.fill" : "power.circle")
                    .foregroundStyle(operatorEnabled ? Color.green : .secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: select)

            operatorSection(
                title: "Oscillator",
                subtitle: "Pitch and frequency source."
            ) {
                LazyVGrid(columns: controlColumns, alignment: .leading, spacing: 10) {
                    ParameterKnob(label: "OSC FRQ Multiplier", value: operatorBinding({ $0.multiple }, update: { try $0.settingMultiple($1) }), range: 0...15)
                    ParameterKnob(label: "Detune 1", value: operatorBinding({ $0.detune1 }, update: { try $0.settingDetune1($1) }), range: 0...7)
                    ParameterKnob(label: "Detune 2", value: operatorBinding({ $0.detune2 }, update: { try $0.settingDetune2($1) }), range: 0...3)
                }
            }

            operatorSection(
                title: amplifierTitle,
                subtitle: operatorData.carrier ? "Audible output loudness." : "Modulation strength and timbre intensity."
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        ParameterKnob(label: "Total Level", value: operatorBinding({ $0.totalLevel }, update: { try $0.settingTotalLevel($1) }), range: 0...127)
                        ParameterKnob(label: "TL Adjust", value: operatorBinding({ $0.totalLevelAdjust }, update: { try $0.settingTotalLevelAdjust($1) }), range: 0...15)
                        ParameterKnob(label: "Vel to TL", value: operatorBinding({ $0.velocitySensitivityForTotalLevel }, update: { try $0.settingVelocitySensitivityForTotalLevel($1) }), range: 0...7)
                    }

                    HStack(alignment: .top, spacing: 16) {
                        ParameterKnob(label: "Keyboard Level\nDepth", value: operatorBinding({ $0.keyboardLevelScalingDepth }, update: { try $0.settingKeyboardLevelScalingDepth($1) }), range: 0...15)
                        keyLevelScalingTypeControl
                    }
                }
            }

            timbreMacroSection

            operatorSection(
                title: "Envelope",
                subtitle: "Time shape of the operator amplifier."
            ) {
                OperatorEnvelopeView(
                    operatorData: operatorData,
                    updateOperator: { updatedOperator in
                        guard operatorEnabled else {
                            return
                        }
                        updateOperator(updatedOperator)
                    }
                )
                .frame(height: 82)
                .allowsHitTesting(operatorEnabled)

                LazyVGrid(columns: controlColumns, alignment: .leading, spacing: 10) {
                    ParameterKnob(label: "Attack", value: operatorBinding({ $0.attackRate }, update: { try $0.settingAttackRate($1) }), range: 0...31)
                    ParameterKnob(label: "Vel to Attack", value: operatorBinding({ $0.velocitySensitivityForAttackRate }, update: { try $0.settingVelocitySensitivityForAttackRate($1) }), range: 0...7)
                    ParameterKnob(label: "Decay 1", value: operatorBinding({ $0.decay1Rate }, update: { try $0.settingDecay1Rate($1) }), range: 0...15)
                    ParameterKnob(label: "Decay 2", value: operatorBinding({ $0.decay2Rate }, update: { try $0.settingDecay2Rate($1) }), range: 0...31)
                    ParameterKnob(label: "Sustain", value: operatorBinding({ $0.sustainLevel }, update: { try $0.settingSustainLevel($1) }), range: 0...15)
                    ParameterKnob(label: "Release", value: operatorBinding({ $0.releaseRate }, update: { try $0.settingReleaseRate($1) }), range: 0...15)
                }
            }

            HStack(alignment: .top, spacing: 20) {
                Spacer()
                RockerSwitch(label: "Enabled", isOn: editableOperatorEnabled, width: 82, height: 58)
                ParameterKnob(label: "Keyboard Rate\nScaling Depth", value: operatorBinding({ $0.keyboardRateScalingDepth }, update: { try $0.settingKeyboardRateScalingDepth($1) }), range: 0...7)
                Spacer()
            }
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .padding(12)
        .frame(
            width: FMPatchBayLayout.moduleSize.width,
            height: FMPatchBayLayout.moduleSize.height,
            alignment: .topLeading
        )
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(moduleFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(moduleStroke, lineWidth: operatorEnabled ? 2.2 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
    }

    private var amplifierTitle: String {
        operatorData.carrier ? "Amplifier - Volume Level" : "Amplifier - Modulation Level"
    }

    private var keyLevelScalingTypeControl: some View {
        VStack(alignment: .center, spacing: 6) {
            Spacer()
                .frame(height: 29)

            GreenNumberSegmentedPicker(selection: keyLevelScalingTypeBinding, values: Array(0...3))
                .frame(width: 148)

            Text("Keyboard Level\nScaling Type")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 190, alignment: .top)
    }

    private var timbreMacroSection: some View {
        operatorSection(
            title: "Timbre Macro",
            subtitle: "Quick amplifier and envelope recipes."
        ) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(FMOperatorTimbreMacro.rows.indices, id: \.self) { rowIndex in
                    HStack(spacing: 6) {
                        ForEach(FMOperatorTimbreMacro.rows[rowIndex]) { macro in
                            timbreMacroButton(macro)
                        }
                    }
                }
            }
        }
    }

    private func operatorSection<Content: View>(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.blue)
            if let subtitle {
                Text(subtitle)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    private func timbreMacroButton(_ macro: FMOperatorTimbreMacro) -> some View {
        Button {
            applyTimbreMacro(macro)
        } label: {
            Text(macro.title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(operatorEnabled ? Color.primary : Color.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(width: 84, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(operatorEnabled ? Color.green.opacity(0.14) : Color.secondary.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(operatorEnabled ? Color.green.opacity(0.45) : Color.secondary.opacity(0.16), lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!operatorEnabled)
        .help(macro.help)
    }

    private var editableOperatorEnabled: Binding<Bool> {
        Binding(
            get: { operatorEnabled },
            set: { enabled in
                operatorEnabled = enabled
            }
        )
    }

    private var moduleFill: Color {
        operatorData.carrier
            ? Color(red: 0.06, green: 0.20, blue: 0.09).opacity(0.75)
            : Color(red: 0.06, green: 0.11, blue: 0.22).opacity(0.75)
    }

    private var moduleStroke: Color {
        if operatorEnabled {
            return Color.green.opacity(0.90)
        }
        return operatorData.carrier ? Color.green.opacity(0.24) : Color.blue.opacity(0.24)
    }

    private func applyTimbreMacro(_ macro: FMOperatorTimbreMacro) {
        guard operatorEnabled, let updated = try? macro.applying(to: operatorData) else {
            return
        }
        updateOperator(updated)
    }

    private func operatorBinding(
        _ value: @escaping (FB01VoiceOperatorData) -> Int,
        update: @escaping (FB01VoiceOperatorData, Int) throws -> FB01VoiceOperatorData
    ) -> Binding<Int> {
        Binding(
            get: { value(operatorData) },
            set: { newValue in
                guard operatorEnabled else {
                    return
                }
                if let updated = try? update(operatorData, newValue) {
                    updateOperator(updated)
                }
            }
        )
    }

    private var keyLevelScalingTypeBinding: Binding<Int> {
        Binding(
            get: {
                (operatorData.keyboardLevelScalingTypeBit1 ? 2 : 0) +
                    (operatorData.keyboardLevelScalingTypeBit0 ? 1 : 0)
            },
            set: { newValue in
                guard operatorEnabled else {
                    return
                }
                do {
                    let updated = try operatorData
                        .settingKeyboardLevelScalingTypeBit0(newValue & 0x01 == 0x01)
                        .settingKeyboardLevelScalingTypeBit1(newValue & 0x02 == 0x02)
                    updateOperator(updated)
                } catch {
                    return
                }
            }
        )
    }
}

enum FMOperatorTimbreMacro: String, CaseIterable, Identifiable {
    case pure
    case soft
    case hollow
    case bright
    case buzz
    case metallic
    case bell
    case percussive

    var id: String { rawValue }

    static let rows: [[FMOperatorTimbreMacro]] = [
        [.pure, .soft, .hollow, .bright],
        [.buzz, .metallic, .bell, .percussive],
    ]

    var title: String {
        switch self {
        case .pure:
            return "Pure"
        case .soft:
            return "Soft"
        case .hollow:
            return "Hollow"
        case .bright:
            return "Bright"
        case .buzz:
            return "Buzz"
        case .metallic:
            return "Metallic"
        case .bell:
            return "Bell"
        case .percussive:
            return "Percussive"
        }
    }

    var help: String {
        switch self {
        case .pure:
            return "Simple sine-like operator settings."
        case .soft:
            return "Gentle rounded settings for pads, muted tones, or warm carriers."
        case .hollow:
            return "Odd-harmonic leaning settings for a rounder hollow tone."
        case .bright:
            return "Brighter harmonic settings with a quick, stable envelope."
        case .buzz:
            return "Aggressive harmonic settings for buzzy or reed-like color."
        case .metallic:
            return "Detuned higher-ratio settings for metallic color."
        case .bell:
            return "High-ratio, decaying settings for bell-like color."
        case .percussive:
            return "Fast transient settings for plucks, mallets, and attack energy."
        }
    }

    func applying(to operatorData: FB01VoiceOperatorData) throws -> FB01VoiceOperatorData {
        let settings = self.settings
        return try operatorData
            .settingTotalLevel(settings.totalLevel)
            .settingMultiple(settings.multiple)
            .settingDetune1(settings.detune1)
            .settingDetune2(settings.detune2)
            .settingAttackRate(settings.attack)
            .settingDecay1Rate(settings.decay1)
            .settingDecay2Rate(settings.decay2)
            .settingSustainLevel(settings.sustain)
            .settingReleaseRate(settings.release)
    }

    private var settings: Settings {
        switch self {
        case .pure:
            return Settings(totalLevel: 0, multiple: 1, detune1: 0, detune2: 0, attack: 31, decay1: 0, decay2: 0, sustain: 15, release: 8)
        case .soft:
            return Settings(totalLevel: 18, multiple: 1, detune1: 0, detune2: 0, attack: 18, decay1: 2, decay2: 4, sustain: 13, release: 10)
        case .hollow:
            return Settings(totalLevel: 12, multiple: 2, detune1: 0, detune2: 0, attack: 31, decay1: 2, decay2: 6, sustain: 12, release: 8)
        case .bright:
            return Settings(totalLevel: 8, multiple: 3, detune1: 0, detune2: 0, attack: 31, decay1: 4, decay2: 8, sustain: 10, release: 7)
        case .buzz:
            return Settings(totalLevel: 6, multiple: 5, detune1: 1, detune2: 0, attack: 31, decay1: 5, decay2: 10, sustain: 9, release: 6)
        case .metallic:
            return Settings(totalLevel: 10, multiple: 7, detune1: 2, detune2: 1, attack: 31, decay1: 6, decay2: 12, sustain: 6, release: 8)
        case .bell:
            return Settings(totalLevel: 14, multiple: 9, detune1: 3, detune2: 2, attack: 31, decay1: 8, decay2: 15, sustain: 0, release: 11)
        case .percussive:
            return Settings(totalLevel: 7, multiple: 4, detune1: 1, detune2: 0, attack: 31, decay1: 9, decay2: 15, sustain: 0, release: 5)
        }
    }

    private struct Settings {
        var totalLevel: Int
        var multiple: Int
        var detune1: Int
        var detune2: Int
        var attack: Int
        var decay1: Int
        var decay2: Int
        var sustain: Int
        var release: Int
    }
}
