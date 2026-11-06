import SwiftUI

@main
struct TailDeskMobileApp: App {
    @StateObject private var client = RemoteClient()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(client)
        }
    }
}

