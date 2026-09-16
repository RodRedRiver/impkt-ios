import SwiftUI
import CoreBluetooth
import NordicDFU

/// Firmware updates over Bluetooth, from the phone, with no laptop involved.
///
/// This is the whole point of the app existing rather than a web page: the wraps
/// speak Nordic's legacy DFU protocol, Nordic ship the iOS implementation of it,
/// and a phone in the same room as a wrap can therefore do what previously
/// needed a Mac, a cable and this repository. Send somebody the app and they can
/// update wraps on another continent.
///
/// The image is bundled with the app, so a firmware release IS an app release.
/// That is deliberate for a pilot: it means a tester cannot mix a stale zip with
/// a current app, and there is exactly one answer to "what is on my wraps".
final class Updater: NSObject, ObservableObject {

    enum Phase: Equatable {
        case idle, connecting, sending, done, failed(String)
    }

    @Published var phase: Phase = .idle
    @Published var progress: Double = 0
    @Published var detail: String = ""
    @Published var target: FoundWrap?

    private var controller: DFUServiceController?

    static var bundledZip: URL? {
        Bundle.main.url(forResource: "firmware", withExtension: "zip")
    }

    static var bundledVersion: String {
        guard let url = Bundle.main.url(forResource: "firmware-version", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "unknown" }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func start(_ wrap: FoundWrap) {
        guard let zip = Updater.bundledZip else {
            phase = .failed("no firmware is bundled with this build of the app")
            return
        }
        guard let peripheral = WrapCentral.shared.peripheral(wrap.id) else {
            phase = .failed("the phone cannot see that wrap any more")
            return
        }

        let firmware: DFUFirmware
        do {
            firmware = try DFUFirmware(urlToZipFile: zip)
        } catch {
            phase = .failed("the bundled firmware package would not open: \(error.localizedDescription)")
            return
        }

        target = wrap
        phase = .connecting
        progress = 0
        detail = "Waking the wrap's bootloader"

        // Our own connection has to go first. The DFU library opens its own, and
        // two links to one peripheral do not fail cleanly: the update simply
        // stalls part way with nothing said, which on a bench looks like a bad
        // board.
        WrapCentral.shared.release(wrap.id)
        WrapCentral.shared.stopScan()

        let initiator = DFUServiceInitiator().with(firmware: firmware)
        initiator.delegate = self
        initiator.progressDelegate = self
        initiator.logger = self
        // The firmware announces the jump to its bootloader and reconnects under a
        // different address. Letting the library handle that is the entire reason
        // for using it rather than writing the protocol here.
        initiator.alternativeAdvertisingNameEnabled = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            self.controller = initiator.start(target: peripheral)
        }
    }

    func cancel() {
        _ = controller?.abort()
        controller = nil
        phase = .idle
        detail = ""
        progress = 0
    }
}

extension Updater: DFUServiceDelegate {
    func dfuStateDidChange(to state: DFUState) {
        switch state {
        case .connecting:      phase = .connecting; detail = "Connecting"
        case .starting:        phase = .connecting; detail = "Starting the update"
        case .enablingDfuMode: phase = .connecting; detail = "Rebooting into the bootloader"
        case .uploading:       phase = .sending;    detail = "Sending the firmware"
        case .validating:      phase = .sending;    detail = "The wrap is checking the image"
        case .disconnecting:   phase = .sending;    detail = "Finishing"
        case .completed:
            phase = .done
            detail = "Updated. The wrap has restarted on the new firmware."
            progress = 1
            controller = nil
        case .aborted:
            phase = .idle
            detail = "Stopped. The wrap kept the firmware it had."
            controller = nil
        }
    }

    func dfuError(_ error: DFUError, didOccurWithMessage message: String) {
        // Said in full, including the library's own message. An update that fails
        // silently leaves somebody in another country holding a board they think
        // is broken, and the recovery is nearly always "charge it and press again".
        phase = .failed(message)
        detail = ""
        controller = nil
    }
}

extension Updater: DFUProgressDelegate {
    func dfuProgressDidChange(for part: Int, outOf totalParts: Int, to percentage: Int,
                              currentSpeedBytesPerSecond: Double,
                              avgSpeedBytesPerSecond: Double) {
        progress = Double(percentage) / 100.0
        detail = "Sending the firmware, \(percentage)%"
    }
}

extension Updater: LoggerDelegate {
    func logWith(_ level: LogLevel, message: String) {
        NSLog("DFU [\(level.rawValue)] \(message)")
    }
}

struct UpdateView: View {

    @ObservedObject private var central = WrapCentral.shared
    @StateObject private var updater = Updater()

    var body: some View {
        NavigationView {
            List {
                Section {
                    switch updater.phase {
                    case .idle:
                        Text("Wake a wrap by shaking it, pick it below, and it will be "
                             + "updated over Bluetooth. Keep the phone next to it.")
                            .font(.footnote).foregroundColor(.secondary)
                    case .connecting, .sending:
                        VStack(alignment: .leading, spacing: 8) {
                            ProgressView(value: updater.progress)
                            Text(updater.detail).font(.footnote).foregroundColor(.secondary)
                            Text("Do not close the app or walk away with the phone.")
                                .font(.caption).foregroundColor(.secondary)
                            Button("Stop") { updater.cancel() }
                                .font(.footnote)
                        }
                    case .done:
                        Label(updater.detail, systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green).font(.footnote)
                    case .failed(let why):
                        VStack(alignment: .leading, spacing: 6) {
                            Label("The update did not finish", systemImage: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange).font(.footnote)
                            Text(why).font(.caption).foregroundColor(.secondary)
                            Text("Charge the wrap, shake it awake and try once more. The wrap "
                                 + "keeps working on its old firmware until an update finishes.")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Firmware in this app: \(Updater.bundledVersion)")
                }

                Section("Wraps nearby") {
                    if central.found.isEmpty {
                        Text(central.poweredOn
                             ? "Nothing yet. Shake a wrap to wake it."
                             : "Bluetooth is off for this app. Turn it on in Settings.")
                            .font(.footnote).foregroundColor(.secondary)
                    }
                    ForEach(central.found.sorted { $0.rssi > $1.rssi }) { wrap in
                        Button {
                            updater.start(wrap)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(wrap.name)
                                    Text("signal \(wrap.rssi) dBm")
                                        .font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                if updater.target?.id == wrap.id,
                                   updater.phase == .connecting || updater.phase == .sending {
                                    ProgressView()
                                } else {
                                    Text("Update").font(.footnote)
                                }
                            }
                        }
                        .disabled(updater.phase == .connecting || updater.phase == .sending)
                    }
                }

                Section {
                    Text("An update needs the phone and the wrap in the same room: "
                         + "Bluetooth reaches a few metres and nothing about this goes "
                         + "over the internet. It takes a minute or two per wrap.")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            .navigationTitle("Update")
            .onAppear { central.startScan() }
            .onDisappear {
                if updater.phase != .sending && updater.phase != .connecting {
                    central.stopScan()
                }
            }
        }
    }
}
