import Foundation

public struct FourOperatorVoiceData: Equatable, Sendable {
    /// A neutral editing model shared by supported Yamaha 4-op modules.
    /// Values here are chosen for a common editor workflow and are not always
    /// exact raw-byte semantics for every device.
    public var sourceModelName: String
    public var name: String
    public var algorithm: Int
    public var feedback: Int
    public var transpose: Int
    public var lfoSpeed: Int
    public var lfoWaveform: Int
    public var lfoSyncEnabled: Bool
    public var pitchModulationDepth: Int
    public var amplitudeModulationDepth: Int
    public var pitchModulationSensitivity: Int
    public var amplitudeModulationSensitivity: Int
    public var operators: [FourOperatorVoiceOperatorData]

    public init(
        sourceModelName: String,
        name: String,
        algorithm: Int,
        feedback: Int,
        transpose: Int,
        lfoSpeed: Int,
        lfoWaveform: Int,
        lfoSyncEnabled: Bool,
        pitchModulationDepth: Int,
        amplitudeModulationDepth: Int,
        pitchModulationSensitivity: Int,
        amplitudeModulationSensitivity: Int,
        operators: [FourOperatorVoiceOperatorData]
    ) {
        self.sourceModelName = sourceModelName
        self.name = name
        self.algorithm = algorithm
        self.feedback = feedback
        self.transpose = transpose
        self.lfoSpeed = lfoSpeed
        self.lfoWaveform = lfoWaveform
        self.lfoSyncEnabled = lfoSyncEnabled
        self.pitchModulationDepth = pitchModulationDepth
        self.amplitudeModulationDepth = amplitudeModulationDepth
        self.pitchModulationSensitivity = pitchModulationSensitivity
        self.amplitudeModulationSensitivity = amplitudeModulationSensitivity
        self.operators = operators.sorted { $0.operatorNumber < $1.operatorNumber }
    }

    public static func carrierOperatorNumbers(forAlgorithm algorithm: Int) -> Set<Int> {
        switch algorithm {
        case 0, 1, 2, 3:
            [1]
        case 4:
            [1, 3]
        case 5, 6:
            [1, 2, 3]
        case 7:
            [1, 2, 3, 4]
        default:
            []
        }
    }
}

public struct FourOperatorVoiceOperatorData: Equatable, Sendable {
    public var operatorNumber: Int
    public var isCarrier: Bool
    public var totalLevel: Int
    /// Device-specific coarse oscillator tuning control.
    /// On FB-01 this maps to the integer frequency multiplier.
    /// On DX100/27 this maps to Yamaha's frequency-ratio control value.
    public var oscillatorFrequencyControl: Int
    public var detune: Int
    public var keyboardLevelScalingDepth: Int
    public var keyboardRateScalingDepth: Int
    /// Keyboard velocity sensitivity that affects operator level.
    public var keyVelocityLevelSensitivity: Int
    public var velocityToAttack: Int
    /// Whether this operator responds to amplitude modulation.
    public var amplitudeModulationResponseEnabled: Bool
    public var attack: Int
    public var decay1: Int
    public var decay2: Int
    public var sustain: Int
    public var release: Int

    public init(
        operatorNumber: Int,
        isCarrier: Bool,
        totalLevel: Int,
        oscillatorFrequencyControl: Int,
        detune: Int,
        keyboardLevelScalingDepth: Int,
        keyboardRateScalingDepth: Int,
        keyVelocityLevelSensitivity: Int,
        velocityToAttack: Int,
        amplitudeModulationResponseEnabled: Bool,
        attack: Int,
        decay1: Int,
        decay2: Int,
        sustain: Int,
        release: Int
    ) {
        self.operatorNumber = operatorNumber
        self.isCarrier = isCarrier
        self.totalLevel = totalLevel
        self.oscillatorFrequencyControl = oscillatorFrequencyControl
        self.detune = detune
        self.keyboardLevelScalingDepth = keyboardLevelScalingDepth
        self.keyboardRateScalingDepth = keyboardRateScalingDepth
        self.keyVelocityLevelSensitivity = keyVelocityLevelSensitivity
        self.velocityToAttack = velocityToAttack
        self.amplitudeModulationResponseEnabled = amplitudeModulationResponseEnabled
        self.attack = attack
        self.decay1 = decay1
        self.decay2 = decay2
        self.sustain = sustain
        self.release = release
    }
}

public extension FB01VoiceData {
    var fourOperatorVoice: FourOperatorVoiceData {
        FourOperatorVoiceData(
            sourceModelName: "FB-01",
            name: name,
            algorithm: algorithm,
            feedback: feedbackLevel,
            transpose: transpose,
            lfoSpeed: lfoSpeed,
            lfoWaveform: lfoWaveform,
            lfoSyncEnabled: lfoSyncEnabled,
            pitchModulationDepth: pitchModulationDepth,
            amplitudeModulationDepth: amplitudeModulationDepth,
            pitchModulationSensitivity: pitchModulationSensitivity,
            amplitudeModulationSensitivity: amplitudeModulationSensitivity,
            operators: operators.map { op in
                FourOperatorVoiceOperatorData(
                    operatorNumber: Self.operatorNumber(forDataIndex: op.index),
                    isCarrier: op.carrier,
                    totalLevel: op.totalLevel,
                    oscillatorFrequencyControl: op.multiple,
                    detune: op.detune1,
                    keyboardLevelScalingDepth: op.keyboardLevelScalingDepth,
                    keyboardRateScalingDepth: op.keyboardRateScalingDepth,
                    keyVelocityLevelSensitivity: op.velocitySensitivityForTotalLevel,
                    velocityToAttack: op.velocitySensitivityForAttackRate,
                    amplitudeModulationResponseEnabled: false,
                    attack: op.attackRate,
                    decay1: op.decay1Rate,
                    decay2: op.decay2Rate,
                    sustain: op.sustainLevel,
                    release: op.releaseRate
                )
            }
        )
    }
}

public extension FB01VoiceOperatorData {
    var fourOperatorOperator: FourOperatorVoiceOperatorData {
        FourOperatorVoiceOperatorData(
            operatorNumber: FB01VoiceData.operatorNumber(forDataIndex: index),
            isCarrier: carrier,
            totalLevel: totalLevel,
            oscillatorFrequencyControl: multiple,
            detune: detune1,
            keyboardLevelScalingDepth: keyboardLevelScalingDepth,
            keyboardRateScalingDepth: keyboardRateScalingDepth,
            keyVelocityLevelSensitivity: velocitySensitivityForTotalLevel,
            velocityToAttack: velocitySensitivityForAttackRate,
            amplitudeModulationResponseEnabled: false,
            attack: attackRate,
            decay1: decay1Rate,
            decay2: decay2Rate,
            sustain: sustainLevel,
            release: releaseRate
        )
    }
}
