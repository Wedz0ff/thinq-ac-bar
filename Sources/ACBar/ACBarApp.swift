import ServiceManagement
import SwiftUI

// ponytail: options hardcoded from the RAC_056905_WW profile; read GET /devices/{id}/profile if another model differs
let temperatureRange = 18.0...30.0
let temperatureStep = 1.0
let modes = [("AUTO", "Auto"), ("COOL", "Cool"), ("AIR_DRY", "Dry"), ("FAN", "Fan")]
let fanSpeeds = [("AUTO", "Auto"), ("LOW", "Low"), ("MID", "Mid"), ("HIGH", "High")]

@main
struct ACBarApp: App {
    @State private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            ContentView().environment(state)
        } label: {
            let running = state.devices.first(where: \.on)
            Image(systemName: running == nil ? "air.conditioner.horizontal" : "air.conditioner.horizontal.fill")
            if let target = running?.target { Text("\(target.formatted())°") }
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

    private var temperatureTasks: [String: Task<Void, Never>] = [:]
    private var api: ThinQ { ThinQ(pat: pat, country: country) }

    init() {
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
        do {
            devices = try await api.devices()
            error = nil
        } catch let failure {
            error = failure.localizedDescription
        }
    }

    func save(pat: String, country: String) async {
        self.pat = pat
        self.country = country
        Keychain.set(pat)
        UserDefaults.standard.set(country, forKey: "country")
        await refresh()
    }

    /// Updates the device locally first, then sends the command; a failure reloads the real state.
    func set(_ id: String, _ body: [String: Any], apply: (inout AC) -> Void) {
        guard let index = devices.firstIndex(where: { $0.id == id }) else { return }
        apply(&devices[index])
        let data = try! JSONSerialization.data(withJSONObject: body)
        Task {
            do {
                try await api.control(id, data)
                error = nil
            } catch let failure {
                await refresh()
                error = failure.localizedDescription
            }
        }
    }

    /// Debounced so repeated +/- clicks send one command.
    func setTemperature(_ id: String, _ temperature: Double) {
        guard let index = devices.firstIndex(where: { $0.id == id }) else { return }
        devices[index].target = temperature
        temperatureTasks[id]?.cancel()
        temperatureTasks[id] = Task {
            try? await Task.sleep(for: .milliseconds(600))
            if Task.isCancelled { return }
            set(id, ["temperature": ["targetTemperature": temperature, "unit": "C"]]) { _ in }
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
                Text(state.loading ? "Loading…" : "No air conditioners found")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(state.devices) { DeviceCard(ac: $0) }
            }

            if let error = state.error {
                Text(error).font(.caption).foregroundStyle(.red).lineLimit(3)
            }

            Divider()
            HStack {
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await state.refresh() } }
                    .disabled(state.loading)
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
                VStack(alignment: .leading) {
                    Text(ac.name).font(.headline)
                    if let current = ac.current {
                        Text("Room \(current.formatted())°").font(.caption).foregroundStyle(.secondary)
                    }
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
                    Text(ac.target.map { "\($0.formatted())°" } ?? "--")
                        .font(.system(size: 34, weight: .light))
                        .monospacedDigit()
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
        }
    }

    private func stepButton(_ symbol: String, by step: Double) -> some View {
        let next = (ac.target ?? 0) + step
        return Button { state.setTemperature(ac.id, next) } label: {
            Image(systemName: symbol).frame(width: 28, height: 28)
        }
        .disabled(ac.target == nil || !temperatureRange.contains(next))
        .accessibilityLabel(step < 0 ? "Decrease temperature" : "Increase temperature")
    }

    private func picker(_ title: String, _ options: [(String, String)], _ selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            ForEach(options, id: \.0) { Text($0.1).tag($0.0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
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
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LG ThinQ").font(.headline)
            SecureField("Personal Access Token", text: $pat)
            TextField("Country (BR, US…)", text: $country)
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    try? enabled ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                }
            Button("Save") {
                Task { await state.save(pat: pat.trimmingCharacters(in: .whitespacesAndNewlines), country: country.uppercased()) }
                done()
            }
            .disabled(pat.isEmpty || country.isEmpty)
        }
        .textFieldStyle(.roundedBorder)
        .onAppear {
            pat = state.pat
            country = state.country
        }
    }
}
