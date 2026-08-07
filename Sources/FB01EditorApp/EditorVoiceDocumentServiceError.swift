import FB01Editor
import Foundation

enum EditorVoiceDocumentServiceError: Error, CustomStringConvertible {
    case unsupportedRecentVoiceFetchForDevice(EditorDeviceSelection)

    var description: String {
        switch self {
        case .unsupportedRecentVoiceFetchForDevice(let device):
            return "\(device.displayName) does not yet support that stored-voice fetch path."
        }
    }
}
