import ServiceManagement
import SwiftUI

// ponytail: options hardcoded from the RAC_056905_WW profile; read GET /devices/{id}/profile if another model differs
let temperatureRange = 18.0...30.0
let temperatureStep = 1.0
let modes = [("AUTO", "Auto"), ("COOL", "Cool"), ("AIR_DRY", "Dry"), ("FAN", "Fan")]
let fanSpeeds = [("AUTO", "Auto"), ("LOW", "Low"), ("MID", "Mid"), ("HIGH", "High")]

extension AC {
    var modeName: String { modes.first { $0.0 == mode }?.1 ?? mode.capitalized }

    var tint: Color {
        switch mode {
        case "COOL": .blue
        case "AIR_DRY": .teal
        case "FAN": .gray
        default: .green
        }
    }
}

/// Text beside the menu bar icon: the target of the only running AC, or how many are running.
func menuBarText(_ devices: [AC]) -> String? {
    let running = devices.filter(\.on)
    if running.count > 1 { return "\(running.count)" }
    return running.first?.target.map { "\($0.formatted())°" }
}

/// Target after one +/- click, kept inside the supported range.
func nextTarget(_ target: Double, by step: Double) -> Double {
    min(max(target + step, temperatureRange.lowerBound), temperatureRange.upperBound)
}

@main
enum Main {
    @MainActor static func main() {
        let delegate = AppDelegate()
        NSApplication.shared.delegate = delegate
        NSApp.setActivationPolicy(.accessory)
        NSApp.run()
    }
}

/// Owns the menu bar item and its popover. AppKit instead of SwiftUI's `MenuBarExtra`,
/// which ignores right (two-finger) clicks and offers no way to handle them.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let state = AppState()
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var outsideClicks: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let host = NSHostingController(rootView: ContentView().environment(state))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        popover.behavior = .transient
        popover.delegate = self

        item.button?.target = self
        item.button?.action = #selector(toggle)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.button?.imagePosition = .imageLeading
        updateLabel()
    }

    @objc private func toggle() {
        guard let button = item.button else { return }
        if popover.isShown { return popover.performClose(nil) }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate()
        // `.transient` only closes the popover when this app is active, which macOS does not guarantee for a
        // menu bar app, so clicks in other apps are watched too. Clicks on the menu bar item go to `toggle`.
        outsideClicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.item.button?.window?.frame.contains(NSEvent.mouseLocation) != true else { return }
                self.popover.performClose(nil)
            }
        }
        Task { await state.refresh() }
    }

    func popoverDidClose(_ notification: Notification) {
        if let outsideClicks { NSEvent.removeMonitor(outsideClicks) }
        outsideClicks = nil
    }

    /// Redraws the menu bar item, and again whenever the state it read changes.
    private func updateLabel() {
        withObservationTracking {
            let symbol = state.error != nil
                ? "exclamationmark.triangle"
                : state.devices.contains(where: \.on) ? "air.conditioner.horizontal.fill" : "air.conditioner.horizontal"
            item.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "AC Bar")
            item.button?.title = menuBarText(state.devices) ?? ""
        } onChange: { [weak self] in
            Task { @MainActor in self?.updateLabel() }
        }
    }
}

@MainActor @Observable
final class AppState {
    var devices: [AC] = []
    var error: String?
    var update: Update?
    var loading = false
    var pat = Keychain.get() ?? ""
    /// LG needs the account's country on every request; the Mac's region stands in for it.
    let country = Locale.current.region?.identifier ?? "US"

    /// Counts local changes, so a refresh that started before one does not overwrite it.
    private var edits = 0
    private var temperatureTasks: [String: Task<Void, Never>] = [:]
    private var targetBeforeClicks: [String: Double?] = [:]
    private var api: ThinQ { ThinQ(pat: pat, country: country) }

    init() {
        loading = !pat.isEmpty
        Task {
            while true {
                update = await Update.check()
                try? await Task.sleep(for: .seconds(86400))
            }
        }
        Task {
            while true {
                await refresh()
                try? await Task.sleep(for: .seconds(300))
            }
        }
    }

    func refresh() async {
        guard !pat.isEmpty else { return }
        loading = true
        defer { loading = false }
        let before = edits
        do {
            let fresh = try await api.devices()
            if edits == before { devices = fresh }
            error = nil
        } catch let failure {
            error = failure.localizedDescription
        }
    }

    /// Saves the settings only if LG accepts the token. Returns the error to show in the form, if any.
    func save(pat: String) async -> String? {
        do {
            let fresh = try await ThinQ(pat: pat, country: country).devices()
            let status = Keychain.set(pat)
            self.pat = pat
            edits += 1
            devices = fresh
            error = status == errSecSuccess
                ? nil
                : "Could not save the token to the Keychain (error \(status)). It will be asked for again next launch."
            return nil
        } catch let failure {
            return failure.localizedDescription
        }
    }

    /// Updates the device locally first, then sends the command; a failure puts the old value back.
    func set(_ id: String, _ body: [String: Any], apply: (inout AC) -> Void) {
        guard let index = devices.firstIndex(where: { $0.id == id }) else { return }
        let previous = devices[index]
        apply(&devices[index])
        send(id, body) { $0 = previous }
    }

    private func send(_ id: String, _ body: [String: Any], revert: @escaping (inout AC) -> Void) {
        edits += 1
        let data = try! JSONSerialization.data(withJSONObject: body)
        Task {
            do {
                try await api.control(id, data)
                edits += 1
                error = nil
            } catch let failure {
                if let index = devices.firstIndex(where: { $0.id == id }) { revert(&devices[index]) }
                edits += 1
                await refresh()
                error = failure.localizedDescription
            }
        }
    }

    /// Debounced so repeated +/- clicks send one command.
    func setTemperature(_ id: String, _ temperature: Double) {
        guard let index = devices.firstIndex(where: { $0.id == id }) else { return }
        let previous = targetBeforeClicks[id] ?? devices[index].target
        targetBeforeClicks[id] = previous
        devices[index].target = temperature
        edits += 1
        temperatureTasks[id]?.cancel()
        temperatureTasks[id] = Task {
            try? await Task.sleep(for: .milliseconds(600))
            if Task.isCancelled { return }
            targetBeforeClicks[id] = nil
            // The API rejects a temperature change while the AC is off.
            guard devices.first(where: { $0.id == id })?.on == true else { return }
            send(id, ["temperature": ["targetTemperature": temperature, "unit": "C"]]) { $0.target = previous }
        }
    }
}

struct ContentView: View {
    @Environment(AppState.self) private var state
    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if state.pat.isEmpty || showSettings {
                SettingsView { showSettings = false }
            } else if state.devices.isEmpty {
                if state.loading {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity)
                } else {
                    Text("No air conditioners found").foregroundStyle(.secondary)
                }
            } else {
                ForEach(state.devices) { DeviceCard(ac: $0) }
            }

            if let error = state.error {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    Text(error).font(.caption).lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Dismiss", systemImage: "xmark") { state.error = nil }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                }
                .padding(8)
                .background(.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }

            if let update = state.update {
                HStack {
                    Image(systemName: "arrow.down.circle.fill").foregroundStyle(.blue)
                    Text("Version \(update.version) is available").font(.caption)
                    Spacer()
                    Button("Download") { NSWorkspace.shared.open(update.url) }
                        .controlSize(.small)
                }
                .padding(8)
                .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }

            Divider()
            HStack {
                if state.loading {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Refresh", systemImage: "arrow.clockwise") { Task { await state.refresh() } }
                        .help("Refresh")
                }
                Button("Settings", systemImage: "gearshape") { showSettings.toggle() }
                    .help("Settings")
                Button("About", systemImage: "info.circle", action: showAbout)
                    .help("About AC Bar")
                Spacer()
                Button("Quit", systemImage: "power") { NSApp.terminate(nil) }
                    .help("Quit AC Bar")
                    .keyboardShortcut("q")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 300)
    }
}

/// The standard macOS About panel; name, version, and copyright come from Info.plist.
@MainActor private func showAbout() {
    let centered = NSMutableParagraphStyle()
    centered.alignment = .center
    let text: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
        .foregroundColor: NSColor.secondaryLabelColor,
        .paragraphStyle: centered,
    ]
    let credits = NSMutableAttributedString(string: "Unofficial app. Not affiliated with LG Electronics.\n", attributes: text)
    credits.append(NSAttributedString(
        string: "github.com/Wedz0ff/thinq-ac-bar",
        attributes: text.merging([.link: URL(string: "https://github.com/Wedz0ff/thinq-ac-bar")!]) { $1 }
    ))
    NSApp.activate()
    NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
}

struct DeviceCard: View {
    @Environment(AppState.self) private var state
    let ac: AC

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "air.conditioner.horizontal.fill")
                    .foregroundStyle(ac.on ? ac.tint : .secondary)
                VStack(alignment: .leading) {
                    Text(ac.name).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Power", isOn: binding(\.on) {
                    ["operation": ["airConOperationMode": $0 ? "POWER_ON" : "POWER_OFF"]]
                })
                .toggleStyle(.switch)
                .labelsHidden()
            }

            Group {
                HStack {
                    stepButton("minus", by: -temperatureStep)
                    Text(ac.on ? ac.target.map { "\($0.formatted())°" } ?? "--" : "Off")
                        .font(.system(size: 40, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(ac.on ? ac.tint : .secondary)
                        .frame(maxWidth: .infinity)
                    stepButton("plus", by: temperatureStep)
                }

                picker("Mode", modes, binding(\.mode) { ["airConJobMode": ["currentJobMode": $0]] })
                picker("Fan", fanSpeeds, binding(\.fan) { ["airFlow": ["windStrength": $0]] })

                HStack {
                    pill("Swing", "arrow.up.and.down", binding(\.swing) { ["windDirection": ["rotateUpDown": $0]] })
                    pill("Energy saving", "leaf.fill", binding(\.powerSave) { ["powerSave": ["powerSaveEnabled": $0]] })
                }
            }
            .disabled(!ac.on)
            .opacity(ac.on ? 1 : 0.5)
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    private var subtitle: String {
        [ac.current.map { "Room \($0.formatted())°" }, ac.on ? ac.modeName : "Off"]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private func stepButton(_ symbol: String, by step: Double) -> some View {
        let next = nextTarget(ac.target ?? 0, by: step)
        return Button { state.setTemperature(ac.id, next) } label: {
            Image(systemName: symbol).font(.title3).frame(width: 36, height: 36)
                .background(.quaternary, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(ac.target == nil || next == ac.target)
        .accessibilityLabel(step < 0 ? "Decrease temperature" : "Increase temperature")
    }

    private func pill(_ title: String, _ symbol: String, _ isOn: Binding<Bool>) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            Label(title, systemImage: symbol)
                .font(.callout)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .foregroundStyle(isOn.wrappedValue ? Color.white : Color.primary)
                .background(isOn.wrappedValue ? AnyShapeStyle(ac.tint) : AnyShapeStyle(.quaternary), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn.wrappedValue ? .isSelected : [])
    }

    private func picker(_ title: String, _ options: [(String, String)], _ selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Picker(title, selection: selection) {
                ForEach(options, id: \.0) { Text($0.1).tag($0.0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private func binding<T>(_ keyPath: WritableKeyPath<AC, T>, _ body: @escaping (T) -> [String: Any]) -> Binding<T> {
        Binding(
            get: { ac[keyPath: keyPath] },
            set: { value in state.set(ac.id, body(value)) { $0[keyPath: keyPath] = value } }
        )
    }
}

struct SettingsView: View {
    @Environment(AppState.self) private var state
    @State private var pat = ""
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var saving = false
    @State private var failure: String?
    let done: () -> Void

    private var token: String { pat.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LG ThinQ").font(.headline)
            Text("AC Bar needs a ThinQ Personal Access Token. It is kept in your Keychain and sent only to LG.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Link("Create a token at connect-pat.lgthinq.com", destination: URL(string: "https://connect-pat.lgthinq.com")!)
                .font(.caption)
            SecureField("Personal Access Token", text: $pat)
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    try? enabled ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }
            if let failure {
                Text(failure).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if !state.pat.isEmpty { Button("Cancel", action: done) }
                Spacer()
                if saving { ProgressView().controlSize(.small) }
                Button("Save") {
                    saving = true
                    Task {
                        failure = await state.save(pat: token)
                        saving = false
                        if failure == nil { done() }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(token.isEmpty || saving)
            }
        }
        .textFieldStyle(.roundedBorder)
        .onAppear { pat = state.pat }
    }
}
