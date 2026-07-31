import AppKit
import FB01Editor
import SwiftUI

import AppKit
import Combine
import FB01Editor
import SwiftUI
import UniformTypeIdentifiers

enum VoiceSlotOperation {
    case copy
    case swap
}

struct VoiceSlotTarget: Equatable {
    var sourceID: LibrarySource.ID
    var sourceTitle: String
    var bank: Int
    var number: Int
}

struct DeviceVoiceCopySelection: Equatable {
    var sourceBank: Int
    var sourceVoiceNumber: Int
    var targetBank: Int
    var targetVoiceNumber: Int
}

struct DeviceConfigurationCopySelection: Equatable {
    var sourceSlot: Int
    var targetSlot: Int
}

final class DeviceConfigurationCopyAccessory: NSView {
    private let sourceSlotPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let targetSlotPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let nameLookup: ConfigurationFetchNameLookup

    var selection: DeviceConfigurationCopySelection {
        DeviceConfigurationCopySelection(
            sourceSlot: sourceSlotPopup.indexOfSelectedItem,
            targetSlot: targetSlotPopup.indexOfSelectedItem
        )
    }

    init(nameLookup: ConfigurationFetchNameLookup) {
        self.nameLookup = nameLookup
        super.init(frame: NSRect(x: 0, y: 0, width: 620, height: 108))

        addSectionTitle("Fetch source:", x: 0)
        addSectionTitle("Store target:", x: 322)
        addSlotPopup(sourceSlotPopup, x: 0, slots: FB01SynthModule.shared.allConfigurationSlots.closedRange)
        addSlotPopup(targetSlotPopup, x: 322, slots: FB01SynthModule.shared.writableConfigurationSlots.closedRange)
    }

    required init?(coder: NSCoder) {
        nil
    }

    private func addSectionTitle(_ title: String, x: CGFloat) {
        let label = NSTextField(labelWithString: title)
        label.font = .boldSystemFont(ofSize: 13)
        label.frame = NSRect(x: x, y: 84, width: 280, height: 18)
        addSubview(label)
    }

    private func addSlotPopup(_ popup: NSPopUpButton, x: CGFloat, slots: ClosedRange<Int>) {
        let slotLabel = NSTextField(labelWithString: "Configuration")
        slotLabel.alignment = .right
        slotLabel.frame = NSRect(x: x, y: 46, width: 90, height: 18)
        addSubview(slotLabel)

        popup.frame = NSRect(x: x + 102, y: 42, width: 178, height: 26)
        for slot in slots {
            popup.addItem(withTitle: nameLookup.menuTitle(slot: slot))
        }
        addSubview(popup)
    }
}

final class DeviceVoiceCopyAccessory: NSView {
    private let sourceBankPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let sourceVoicePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let targetBankPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let targetVoicePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let nameLookup: VoiceDocumentFetchNameLookup

    var selection: DeviceVoiceCopySelection {
        DeviceVoiceCopySelection(
            sourceBank: sourceBankPopup.indexOfSelectedItem + 1,
            sourceVoiceNumber: sourceVoicePopup.indexOfSelectedItem,
            targetBank: targetBankPopup.indexOfSelectedItem + 1,
            targetVoiceNumber: targetVoicePopup.indexOfSelectedItem
        )
    }

    init(nameLookup: VoiceDocumentFetchNameLookup) {
        self.nameLookup = nameLookup
        super.init(frame: NSRect(x: 0, y: 0, width: 620, height: 146))

        addSectionTitle("Fetch source:", x: 0)
        addSectionTitle("Store target:", x: 322)
        addPopupRows(
            bankPopup: sourceBankPopup,
            voicePopup: sourceVoicePopup,
            x: 0,
            bankRange: FB01SynthModule.shared.voiceBankRange.closedRange,
            bankTitle: { nameLookupBankTitle($0) }
        )
        addPopupRows(
            bankPopup: targetBankPopup,
            voicePopup: targetVoicePopup,
            x: 322,
            bankRange: FB01SynthModule.shared.writableVoiceBankRange.closedRange,
            bankTitle: { "Bank \($0)" }
        )

        sourceBankPopup.target = self
        sourceBankPopup.action = #selector(sourceBankChanged)
        targetBankPopup.target = self
        targetBankPopup.action = #selector(targetBankChanged)
        populateSourceVoices()
        populateTargetVoices()
    }

    required init?(coder: NSCoder) {
        nil
    }

    @objc private func sourceBankChanged() {
        populateSourceVoices()
    }

    @objc private func targetBankChanged() {
        populateTargetVoices()
    }

    private func addSectionTitle(_ title: String, x: CGFloat) {
        let label = NSTextField(labelWithString: title)
        label.font = .boldSystemFont(ofSize: 13)
        label.frame = NSRect(x: x, y: 122, width: 280, height: 18)
        addSubview(label)
    }

    private func addPopupRows(
        bankPopup: NSPopUpButton,
        voicePopup: NSPopUpButton,
        x: CGFloat,
        bankRange: ClosedRange<Int>,
        bankTitle: (Int) -> String
    ) {
        let bankLabel = NSTextField(labelWithString: "Bank")
        bankLabel.alignment = .right
        bankLabel.frame = NSRect(x: x, y: 84, width: 54, height: 18)
        addSubview(bankLabel)

        let voiceLabel = NSTextField(labelWithString: "Voice")
        voiceLabel.alignment = .right
        voiceLabel.frame = NSRect(x: x, y: 46, width: 54, height: 18)
        addSubview(voiceLabel)

        bankPopup.frame = NSRect(x: x + 66, y: 80, width: 214, height: 26)
        voicePopup.frame = NSRect(x: x + 66, y: 42, width: 214, height: 26)
        for bank in bankRange {
            bankPopup.addItem(withTitle: bankTitle(bank))
        }
        addSubview(bankPopup)
        addSubview(voicePopup)
    }

    private func populateSourceVoices() {
        let bank = sourceBankPopup.indexOfSelectedItem + 1
        populateVoices(in: sourceVoicePopup, bank: bank, includeNames: true)
    }

    private func populateTargetVoices() {
        let bank = targetBankPopup.indexOfSelectedItem + 1
        populateVoices(in: targetVoicePopup, bank: bank, includeNames: true)
    }

    private func populateVoices(in popup: NSPopUpButton, bank: Int, includeNames: Bool) {
        let selectedVoice = max(0, popup.indexOfSelectedItem)
        popup.removeAllItems()
        for voiceNumber in 1...FB01SynthModule.shared.voicesPerBank {
            let title = includeNames
                ? nameLookup.voiceMenuTitle(location: .bank(bank), voiceNumber: voiceNumber)
                : "Voice \(voiceNumber)"
            popup.addItem(withTitle: title)
        }
        popup.selectItem(at: min(selectedVoice, FB01SynthModule.shared.voicesPerBank - 1))
    }

    private func nameLookupBankTitle(_ bank: Int) -> String {
        switch bank {
        case 1:
            "Bank 1 RAM"
        case 2:
            "Bank 2 RAM"
        default:
            "Bank \(bank) ROM\(bank - 2)"
        }
    }
}

let keyboardPreparationStaleAfter: TimeInterval = 300
let keyboardPreparationSettleDelay: TimeInterval = 0.30
let voiceBankNameFetchTimeout: TimeInterval = 25

final class VoiceSlotPickerAccessory: NSView {
    private let bankPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let voicePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let targetsByBank: [Int: [VoiceSlotTarget]]
    private let titleProvider: (VoiceSlotTarget) -> String

    var selectedTarget: VoiceSlotTarget? {
        voicePopup.selectedItem?.representedObject as? VoiceSlotTarget
    }

    init(targets: [VoiceSlotTarget], preferredTarget: VoiceSlotTarget?, titleProvider: @escaping (VoiceSlotTarget) -> String) {
        self.targetsByBank = Dictionary(grouping: targets.sorted { lhs, rhs in
            if lhs.bank != rhs.bank {
                return lhs.bank < rhs.bank
            }
            return lhs.number < rhs.number
        }, by: \.bank)
        self.titleProvider = titleProvider

        super.init(frame: NSRect(x: 0, y: 0, width: 430, height: 72))

        let targetLabel = NSTextField(labelWithString: "Target slot:")
        targetLabel.frame = NSRect(x: 0, y: 50, width: 92, height: 18)
        targetLabel.alignment = .right

        let bankLabel = NSTextField(labelWithString: "Bank")
        bankLabel.frame = NSRect(x: 28, y: 28, width: 64, height: 18)
        bankLabel.alignment = .right

        let voiceLabel = NSTextField(labelWithString: "Voice")
        voiceLabel.frame = NSRect(x: 28, y: 2, width: 64, height: 18)
        voiceLabel.alignment = .right

        bankPopup.frame = NSRect(x: 104, y: 24, width: 150, height: 26)
        voicePopup.frame = NSRect(x: 104, y: 0, width: 326, height: 26)

        for bank in self.targetsByBank.keys.sorted() {
            bankPopup.addItem(withTitle: "Bank \(bank + 1)")
            bankPopup.lastItem?.representedObject = bank
        }

        bankPopup.target = self
        bankPopup.action = #selector(bankChanged)

        addSubview(targetLabel)
        addSubview(bankLabel)
        addSubview(voiceLabel)
        addSubview(bankPopup)
        addSubview(voicePopup)

        if let preferredTarget,
           let index = bankPopup.itemArray.firstIndex(where: { ($0.representedObject as? Int) == preferredTarget.bank }) {
            bankPopup.selectItem(at: index)
        } else {
            bankPopup.selectItem(at: 0)
        }
        populateVoices(preferredTarget: preferredTarget)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    @objc private func bankChanged() {
        populateVoices(preferredTarget: nil)
    }

    private func populateVoices(preferredTarget: VoiceSlotTarget?) {
        voicePopup.removeAllItems()

        guard let bank = bankPopup.selectedItem?.representedObject as? Int,
              let targets = targetsByBank[bank] else {
            return
        }

        for target in targets {
            voicePopup.addItem(withTitle: titleProvider(target))
            voicePopup.lastItem?.representedObject = target
        }

        if let preferredTarget,
           preferredTarget.bank == bank,
           let index = targets.firstIndex(of: preferredTarget) {
            voicePopup.selectItem(at: index)
        } else {
            voicePopup.selectItem(at: 0)
        }
    }
}


@MainActor
func showEditorError(title: String, message: String) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.alertStyle = .warning
    alert.addButton(withTitle: "OK")
    alert.runModal()
}

@MainActor
final class EditorProgressPanel {
    private let panel: NSPanel
    private let messageLabel: NSTextField
    private let progress: NSProgressIndicator
    private let cancelButton: NSButton
    var onCancel: (() -> Void)?

    init(title: String, message: String, showsCancelButton: Bool = false) {
        let panelHeight: CGFloat = showsCancelButton ? 220 : 190
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: panelHeight),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        panel.title = title
        panel.isReleasedWhenClosed = false
        panel.center()

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 430, height: panelHeight))
        panel.contentView = content

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .boldSystemFont(ofSize: 15)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.frame = NSRect(x: 24, y: showsCancelButton ? 172 : 142, width: 382, height: 22)
        content.addSubview(titleLabel)

        messageLabel = NSTextField(wrappingLabelWithString: message)
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.font = .systemFont(ofSize: 13)
        messageLabel.maximumNumberOfLines = 3
        messageLabel.preferredMaxLayoutWidth = 382
        messageLabel.frame = NSRect(x: 24, y: showsCancelButton ? 104 : 78, width: 382, height: 58)
        content.addSubview(messageLabel)

        progress = NSProgressIndicator(frame: NSRect(x: 24, y: showsCancelButton ? 72 : 42, width: 382, height: 14))
        progress.style = .bar
        progress.isIndeterminate = true
        content.addSubview(progress)

        cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
        cancelButton.frame = NSRect(x: 306, y: 18, width: 100, height: 30)
        cancelButton.bezelStyle = .rounded
        cancelButton.target = self
        cancelButton.action = #selector(cancel)
        cancelButton.isHidden = !showsCancelButton
        content.addSubview(cancelButton)
    }

    func show() {
        progress.startAnimation(nil)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismiss() {
        progress.stopAnimation(nil)
        panel.orderOut(nil)
    }

    func update(message: String) {
        messageLabel.stringValue = message
    }

    func update(message: String, completed: Double, total: Double) {
        messageLabel.stringValue = message
        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = max(total, 1)
        progress.doubleValue = min(max(completed, 0), progress.maxValue)
    }

    @objc private func cancel() {
        cancelButton.isEnabled = false
        update(message: "Canceling after the current MIDI operation finishes...")
        onCancel?()
    }
}

@MainActor
func labelledEditorPopup(label: String, popup: NSPopUpButton) -> NSView {
    let container = NSStackView()
    container.frame = NSRect(x: 0, y: 0, width: 520, height: 32)
    container.orientation = .horizontal
    container.alignment = .centerY
    container.spacing = 12

    let text = NSTextField(labelWithString: label)
    text.alignment = .right
    text.translatesAutoresizingMaskIntoConstraints = false

    popup.controlSize = .regular
    popup.translatesAutoresizingMaskIntoConstraints = false

    container.addArrangedSubview(text)
    container.addArrangedSubview(popup)
    NSLayoutConstraint.activate([
        container.widthAnchor.constraint(equalToConstant: 520),
        container.heightAnchor.constraint(greaterThanOrEqualToConstant: 32),
        text.widthAnchor.constraint(equalToConstant: 120),
        popup.widthAnchor.constraint(equalToConstant: 360),
    ])
    return container
}

@MainActor
func makeWarningLabel(_ string: String, width: CGFloat = 330) -> NSTextField {
    let text = NSTextField(wrappingLabelWithString: string)
    text.textColor = .secondaryLabelColor
    text.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    text.maximumNumberOfLines = 3
    text.preferredMaxLayoutWidth = width
    text.frame = NSRect(x: 0, y: 0, width: width, height: 44)
    return text
}

@MainActor
final class VoiceFetchDialogController: NSObject {
    var result: NSApplication.ModalResponse = .cancel
    weak var sourcePopup: NSPopUpButton?
    weak var instrumentPopup: NSPopUpButton?
    weak var bankPopup: NSPopUpButton?
    weak var voicePopup: NSPopUpButton?
    var updateVoiceChoices: (() -> Void)?

    @objc func accept() {
        result = .OK
        NSApp.stopModal()
    }

    @objc func cancel() {
        result = .cancel
        NSApp.stopModal()
    }

    @objc func updateControls() {
        let isStoredVoiceFetch = sourcePopup?.indexOfSelectedItem == 1
        instrumentPopup?.isEnabled = !isStoredVoiceFetch
        bankPopup?.isEnabled = isStoredVoiceFetch
        voicePopup?.isEnabled = isStoredVoiceFetch
        updateVoiceChoices?()
    }
}

@MainActor
final class ConfigurationFetchDialogController: NSObject {
    var result: NSApplication.ModalResponse = .cancel

    @objc func accept() {
        result = .OK
        NSApp.stopModal()
    }

    @objc func cancel() {
        result = .cancel
        NSApp.stopModal()
    }
}

final class DoneDialogController: NSObject {
    @MainActor
    @objc func done() {
        NSApp.stopModal()
    }
}
