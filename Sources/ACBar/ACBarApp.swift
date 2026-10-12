import SwiftUI

@main
struct ACBarApp: App {
    var body: some Scene {
        MenuBarExtra("AC Bar", systemImage: "air.conditioner.horizontal") {
            Text("AC Bar").padding()
        }
        .menuBarExtraStyle(.window)
    }
}
