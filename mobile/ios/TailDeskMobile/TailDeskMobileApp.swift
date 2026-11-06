import SwiftUI

@main
struct TailDeskMobileApp: App {
    @StateObject private var client = RemoteClient()
    @StateObject private var history = ConnectionHistoryStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(client)
                .environmentObject(history)
        }
    }
}

