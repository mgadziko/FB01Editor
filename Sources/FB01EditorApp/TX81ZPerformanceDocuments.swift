import FB01Editor
import SwiftUI

@MainActor
final class TX81ZPerformanceDocumentModel: ObservableObject, Identifiable {
    let id = UUID()
    let performance: TX81ZPerformanceData
    let slotNumber: Int?
    let systemChannel: Int
    let statusMessage: String

    init(performance: TX81ZPerformanceData, slotNumber: Int?, systemChannel: Int, statusMessage: String) {
        self.performance = performance
        self.slotNumber = slotNumber
        self.systemChannel = systemChannel
        self.statusMessage = statusMessage
    }

    var title: String {
        performance.name.isEmpty ? "Untitled Performance" : performance.name
    }
}

private struct TX81ZPerformanceSelectorItem: Identifiable {
    let number: Int
    let performance: TX81ZPerformanceData
    var id: Int { number }
}

struct TX81ZPerformanceDocumentWindow: View {
    @ObservedObject var document: TX81ZPerformanceDocumentModel
    @ObservedObject var device: DocumentModel
    var closeDocument: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Read Only")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.blue)
                    Spacer()
                    Text(document.performance.isEditBuffer ? "Current Edit Buffer" : "Performance Bank")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                DocumentMIDIContextView(device: device, editingDevice: .tx81z, documentSystemChannel: document.systemChannel)

                SummaryPanel(rows: [
                    KeyValueRow("Performance", document.title),
                    KeyValueRow("Slot", document.slotNumber.map { "\($0)" } ?? "Current Edit Buffer"),
                    KeyValueRow("Data", document.performance.isEditBuffer ? "PCED (120 bytes)" : "PMEM (76 bytes)"),
                ])

                GroupBox("Instruments") {
                    VStack(spacing: 0) {
                        ForEach(Array(document.performance.instruments.enumerated()), id: \.offset) { index, instrument in
                            HStack {
                                Text("Instrument \(index + 1)")
                                    .frame(width: 96, alignment: .leading)
                                if let maximumNotes = instrument.maximumNotes {
                                    Text(maximumNotes == 0 ? "Inactive" : (instrument.voiceLocation ?? "Unknown"))
                                        .frame(width: 76, alignment: .leading)
                                    Text(instrument.receiveChannel.map { "Ch \($0)" } ?? "Omni")
                                        .frame(width: 72, alignment: .leading)
                                    Text("Notes \(maximumNotes)")
                                } else {
                                    Text("Compact PMEM data")
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let volume = instrument.volume {
                                    Text("Vol \(volume)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .font(.callout)
                            .padding(.vertical, 7)
                            if index < 7 { Divider() }
                        }
                    }
                    .padding(.horizontal, 8)
                }

                Text(document.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("TX81Z Performance - \(document.title)")
        .environment(\.forestHoverTextEnabled, device.hoverTextEnabled)
        .background(WindowActivationObserver(
            onBecomeKey: { device.selectDevice(.tx81z) },
            onResignKey: {}
        ))
        .onAppear { device.selectDevice(.tx81z) }
        .background(WindowIdentifierSetter(identifier: EditorDocumentWorkspace.tx81zPerformanceWindowIdentifier(for: document.id)))
        .onDisappear(perform: closeDocument)
    }
}

struct TX81ZPerformanceSelectorWindow: View {
    @ObservedObject var document: DocumentModel
    @ObservedObject var workspace: EditorDocumentWorkspace
    @Environment(\.openWindow) private var openWindow
    @State private var performances: [TX81ZPerformanceData] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        let layout = TX81ZModuleServices.shared.module.configurationBankSelectorLayout
            ?? TX81ZModuleServices.shared.module.voiceBankSelectorLayout
        SelectorWindowLayout(
            title: "TX81Z Performance Bank",
            subtitle: "Select a Performance to open it in a read-only Performance Document.",
            isLoading: isLoading,
            errorMessage: errorMessage,
            layout: layout,
            statusBadgeText: "24 Writable / 8 Initial",
            statusBadgeColor: .blue
        ) {
            selectorGrid(items: performances.enumerated().map { TX81ZPerformanceSelectorItem(number: $0.offset + 1, performance: $0.element) }, layout: layout) { item in
                let number = item.number
                let performance = item.performance
                SelectorGridButton(
                    number: number,
                    title: performance.name.isEmpty ? "Performance \(number)" : performance.name,
                    buttonWidth: layout.buttonWidth
                ) {
                    let id = workspace.createTX81ZPerformanceDocument(
                        performance: performance,
                        slotNumber: number,
                        systemChannel: document.systemChannel,
                        statusMessage: "Opened cached TX81Z Performance \(number)."
                    )
                    openWindow(id: "tx81z-performance-document", value: id)
                }
                .disabled(document.isBusy)
            }
        }
        .task { await loadPerformances() }
        .onChange(of: document.configurationSelectorRevision) { _, _ in
            performances = document.tx81zCachedPerformanceBank()?.performances ?? []
        }
        .background(WindowIdentifierSetter(identifier: EditorDocumentWorkspace.configurationBankSelectorWindowIdentifier))
        .environment(\.forestHoverTextEnabled, document.hoverTextEnabled)
    }

    @MainActor
    private func loadPerformances() async {
        isLoading = true
        errorMessage = nil
        performances = await document.ensureTX81ZPerformanceBank()?.performances ?? []
        if performances.isEmpty { errorMessage = document.errorMessage ?? "TX81Z Performances could not be fetched." }
        isLoading = false
    }
}
