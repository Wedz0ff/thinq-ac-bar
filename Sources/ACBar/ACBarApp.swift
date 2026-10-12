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
struct ACBarApp: App {
    @State private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            ContentView().environment(state)
        } label: {
            if state.error != nil {
                Image(systemName: "exclamationmark.triangle")
            } else {
                Image(systemName: state.devices.contains(where: \.on) ? "air.conditioner.horizontal.fill" : "air.conditioner.horizontal")
            }
            if let text = menuBarText(state.devices) { Text(text) }
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor @Observable
final class AppState {
    var devices: [AC] = []
    var error: String?
    var loading = false
    var pat = Keychain.get() ?? ""
    var country = UserDefaults.standard.string(forKey: "country") ?? "BR"

    /// Counts local changes, so a refresh that started before one does not overwrite it.
    private var edits = 0
    private var temperatureTasks: [String: Task<Void, Never>] = [:]
    private var targetBeforeClicks: [String: Double?] = [:]
    private var api: ThinQ { ThinQ(pat: pat, country: country) }

    init() {
        loading = !pat.isEmpty
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
    func save(pat: String, country: String) async -> String? {
        do {
            let fresh = try await ThinQ(pat: pat, country: country).devices()
            let status = Keychain.set(pat)
            UserDefaults.standard.set(country, forKey: "country")
            self.pat = pat
            self.country = country
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

            Divider()
            HStack {
                if state.loading {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Refresh", systemImage: "arrow.clockwise") { Task { await state.refresh() } }
                }
                Button("Settings", systemImage: "gearshape") { showSettings.toggle() }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 300)
        .task { await state.refresh() }
    }
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
                    Toggle("Swing", isOn: binding(\.swing) { ["windDirection": ["rotateUpDown": $0]] })
                    Spacer()
                    Toggle("Energy saving", isOn: binding(\.powerSave) { ["powerSave": ["powerSaveEnabled": $0]] })
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
    @State private var country = ""
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
            TextField("Country code (BR, US…)", text: $country)
                .onChange(of: country) { _, value in
                    country = String(value.filter(\.isLetter).uppercased().prefix(2))
                }
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
                        failure = await state.save(pat: token, country: country)
                        saving = false
                        if failure == nil { done() }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(token.isEmpty || country.count != 2 || saving)
            }
        }
        .textFieldStyle(.roundedBorder)
        .onAppear {
            pat = state.pat
            country = state.country
        }
    }
}
