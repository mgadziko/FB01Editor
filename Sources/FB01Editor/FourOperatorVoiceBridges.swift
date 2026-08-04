import Foundation

public extension FourOperatorVoiceData {
    func fb01EditableVoice() throws -> FB01VoiceData {
        var voice = try FB01DocumentService.shared.templateVoice()
        voice = try voice.settingName(String(name.prefix(FB01VoiceData.nameLength)))
        voice = try voice.settingAlgorithmAndOperatorRoles(clamped(algorithm, range: 0...7))
        voice = try voice.settingFeedbackLevel(clamped(feedback, range: 0...7))
        voice = try voice.settingTranspose(clamped(transpose, range: -128...127))
        voice = try voice.settingLFOSpeed(clamped(lfoSpeed, range: 0...255))
        voice = try voice.settingAmplitudeModulationDepth(clamped(amplitudeModulationDepth, range: 0...127))
        voice = try voice.settingPitchModulationDepth(clamped(pitchModulationDepth, range: 0...127))
        voice = try voice.settingPitchModulationSensitivity(clamped(pitchModulationSensitivity, range: 0...7))
        voice = try voice.settingAmplitudeModulationSensitivity(clamped(amplitudeModulationSensitivity, range: 0...3))
        voice = try voice.settingLFOWaveform(clamped(lfoWaveform, range: 0...3))
        voice = try voice.settingLFOSyncEnabled(lfoSyncEnabled)
        voice = try voice.settingLoadLFODataEnabled(false)
        voice = try voice.settingLeftOutputEnabled(true)
        voice = try voice.settingRightOutputEnabled(true)

        let carriers = Self.carrierOperatorNumbers(forAlgorithm: clamped(algorithm, range: 0...7))
        for op in operators.sorted(by: { $0.operatorNumber > $1.operatorNumber }) {
            let operatorIndex = FB01VoiceData.dataIndex(forOperatorNumber: op.operatorNumber)
            var editable = voice.operators[operatorIndex]
            editable = try editable.settingCarrier(carriers.contains(op.operatorNumber))
            editable = try editable.settingTotalLevel(clamped(op.totalLevel, range: 0...127))
            editable = try editable.settingMultiple(clamped(op.frequencyValue, range: 0...15))
            editable = try editable.settingDetune1(fb01Detune1Value(from: op.detune))
            editable = try editable.settingDetune2(0)
            editable = try editable.settingVelocitySensitivityForTotalLevel(clamped(op.velocityToTotalLevel, range: 0...7))
            editable = try editable.settingTotalLevelAdjust(0)
            editable = try editable.settingKeyboardLevelScalingDepth(clamped(op.keyboardLevelScalingDepth, range: 0...15))
            editable = try editable.settingKeyboardLevelScalingTypeBit0(false)
            editable = try editable.settingKeyboardLevelScalingTypeBit1(false)
            editable = try editable.settingKeyboardRateScalingDepth(clamped(op.keyboardRateScalingDepth, range: 0...7))
            editable = try editable.settingAttackRate(clamped(op.attack, range: 0...31))
            editable = try editable.settingVelocitySensitivityForAttackRate(clamped(op.velocityToAttack, range: 0...7))
            editable = try editable.settingDecay1Rate(clamped(op.decay1, range: 0...15))
            editable = try editable.settingDecay2Rate(clamped(op.decay2, range: 0...31))
            editable = try editable.settingSustainLevel(clamped(op.sustain, range: 0...15))
            editable = try editable.settingReleaseRate(clamped(op.release, range: 0...15))
            voice = try voice.replacingOperator(editable)
            voice = try voice.settingOperatorEnabled(index: editable.index, enabled: true)
        }

        return voice
    }

    func dx100Voice() throws -> DX100VoiceData {
        var bytes = try DX100DocumentService.shared.templateVoice().bytes
        let nameBytes = Array(name.prefix(DX100VoiceData.nameLength).utf8)
        for index in 0..<DX100VoiceData.nameLength {
            bytes[77 + index] = index < nameBytes.count ? min(nameBytes[index], 0x7E) : 0x20
        }

        bytes[52] = UInt8(clamped(algorithm, range: 0...7))
        bytes[53] = UInt8(clamped(feedback, range: 0...7))
        bytes[54] = UInt8(clamped(lfoSpeed, range: 0...99))
        bytes[55] = 0
        bytes[56] = UInt8(clamped(pitchModulationDepth, range: 0...99))
        bytes[57] = UInt8(clamped(amplitudeModulationDepth, range: 0...99))
        bytes[58] = lfoSyncEnabled ? 1 : 0
        bytes[59] = UInt8(clamped(lfoWaveform, range: 0...3))
        bytes[60] = UInt8(clamped(pitchModulationSensitivity, range: 0...7))
        bytes[61] = UInt8(clamped(amplitudeModulationSensitivity, range: 0...3))
        bytes[62] = UInt8(clamped(transpose + 24, range: 0...48))
        bytes[63] = 0
        bytes[64] = 2
        bytes[65] = 0
        bytes[66] = 0
        bytes[67] = 0
        bytes[68] = 0
        bytes[69] = 0
        bytes[70] = 0
        bytes[71] = 0
        bytes[72] = 0
        bytes[73] = 0
        bytes[74] = 0
        bytes[75] = 0
        bytes[76] = 0

        for op in operators {
            guard let dataOrderIndex = DX100VoiceData.operatorNumbersInDataOrder.firstIndex(of: op.operatorNumber) else {
                throw DX100SysExError.operatorNumberOutOfRange(op.operatorNumber)
            }
            let start = dataOrderIndex * DX100VoiceData.operatorBlockByteCount
            bytes[start + 0] = UInt8(clamped(op.attack, range: 0...31))
            bytes[start + 1] = UInt8(clamped(op.decay1, range: 0...31))
            bytes[start + 2] = UInt8(clamped(op.decay2, range: 0...31))
            bytes[start + 3] = UInt8(clamped(op.release, range: 0...15))
            bytes[start + 4] = UInt8(clamped(op.sustain, range: 0...15))
            bytes[start + 5] = UInt8(clamped(op.keyboardLevelScalingDepth, range: 0...99))
            bytes[start + 6] = UInt8(clamped(op.keyboardRateScalingDepth, range: 0...3))
            bytes[start + 7] = UInt8(clamped(op.velocityToAttack, range: 0...7))
            bytes[start + 8] = op.amplitudeModulationEnabled ? 1 : 0
            bytes[start + 9] = UInt8(clamped(op.velocityToTotalLevel, range: 0...7))
            bytes[start + 10] = UInt8(clamped(op.totalLevel, range: 0...99))
            bytes[start + 11] = UInt8(clamped(op.frequencyValue, range: 0...63))
            bytes[start + 12] = UInt8(clamped(dx100DetuneValue(from: op.detune), range: 0...6))
        }

        return try DX100VoiceData(bytes: bytes)
    }

    private func clamped(_ value: Int, range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private func fb01Detune1Value(from neutralDetune: Int) -> Int {
        if (-3...3).contains(neutralDetune) {
            return clamped(neutralDetune + 3, range: 0...7)
        }
        return clamped(neutralDetune, range: 0...7)
    }

    private func dx100DetuneValue(from neutralDetune: Int) -> Int {
        if (0...7).contains(neutralDetune) {
            return clamped(neutralDetune, range: 0...6)
        }
        return clamped(neutralDetune + 3, range: 0...6)
    }
}

public extension DX100VoiceData {
    func fb01EditableVoice() throws -> FB01VoiceData {
        try fourOperatorVoice.fb01EditableVoice()
    }
}
