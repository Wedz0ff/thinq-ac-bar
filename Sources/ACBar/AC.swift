import Foundation

/// One air conditioner and its last known state.
struct AC: Identifiable, Equatable, Sendable {
    let id: String
    var name: String
    var on = false
    var current: Double?
    var target: Double?
    var mode = "COOL"
    var fan = "AUTO"
    var swing = false
    var powerSave = false

    /// `state` is the `response` object of `GET /devices/{id}/state`.
    init(id: String, name: String, state: [String: Any]) {
        func value<T>(_ group: String, _ key: String) -> T? {
            (state[group] as? [String: Any])?[key] as? T
        }
        self.id = id
        self.name = name
        on = (value("operation", "airConOperationMode") as String?) == "POWER_ON"
        current = value("temperature", "currentTemperature")
        target = value("temperature", "targetTemperature")
        mode = value("airConJobMode", "currentJobMode") ?? mode
        fan = value("airFlow", "windStrength") ?? fan
        swing = value("windDirection", "rotateUpDown") ?? false
        powerSave = value("powerSave", "powerSaveEnabled") ?? false
    }
}
