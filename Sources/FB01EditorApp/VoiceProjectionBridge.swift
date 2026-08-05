import FB01Editor
import Foundation

struct FB01OperatorProjectionOverlay: Equatable, Sendable {
    var keyboardLevelScalingTypeBit0: Bool
    var totalLevelAdjust: Int
    var keyboardLevelScalingTypeBit1: Bool
    var detune2: Int

    init(operatorData: FB01VoiceOperatorData) {
        keyboardLevelScalingTypeBit0 = operatorData.keyboardLevelScalingTypeBit0
        totalLevelAdjust = operatorData.totalLevelAdjust
        keyboardLevelScalingTypeBit1 = operatorData.keyboardLevelScalingTypeBit1
        detune2 = operatorData.detune2
    }
}

struct FB01VoiceProjectionOverlay: Equatable, Sendable {
    var userCode: Int
    var loadLFODataEnabled: Bool
    var leftOutputEnabled: Bool
    var rightOutputEnabled: Bool
    var operatorEnabled: [Bool]
    var operatorOverlays: [FB01OperatorProjectionOverlay]

    init(voice: FB01VoiceData) {
        userCode = voice.userCode
        loadLFODataEnabled = voice.loadLFODataEnabled
        leftOutputEnabled = voice.leftOutputEnabled
        rightOutputEnabled = voice.rightOutputEnabled
        operatorEnabled = voice.operatorEnabled
        operatorOverlays = voice.operators.map(FB01OperatorProjectionOverlay.init(operatorData:))
    }

    func apply(to neutralVoice: FourOperatorVoiceData) throws -> FB01VoiceData {
        var voice = try neutralVoice.fb01EditableVoice()
        voice = try voice.settingUserCode(userCode)
        voice = try voice.settingLoadLFODataEnabled(loadLFODataEnabled)
        voice = try voice.settingLeftOutputEnabled(leftOutputEnabled)
        voice = try voice.settingRightOutputEnabled(rightOutputEnabled)

        for index in 0..<min(voice.operators.count, operatorOverlays.count) {
            let overlay = operatorOverlays[index]
            var operatorData = voice.operators[index]
            operatorData = try operatorData.settingKeyboardLevelScalingTypeBit0(overlay.keyboardLevelScalingTypeBit0)
            operatorData = try operatorData.settingTotalLevelAdjust(overlay.totalLevelAdjust)
            operatorData = try operatorData.settingKeyboardLevelScalingTypeBit1(overlay.keyboardLevelScalingTypeBit1)
            operatorData = try operatorData.settingDetune2(overlay.detune2)
            voice = try voice.replacingOperator(operatorData)
        }

        for index in 0..<min(FB01VoiceData.operatorCount, operatorEnabled.count) {
            voice = try voice.settingOperatorEnabled(index: index, enabled: operatorEnabled[index])
        }

        return voice
    }
}
