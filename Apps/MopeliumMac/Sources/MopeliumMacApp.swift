#if canImport(SwiftUI)
import SwiftUI

@main
struct MopeliumMacApp: App {
    var body: some Scene {
        WindowGroup {
            MopeliumMacRootView()
        }
    }
}
#else
@main
struct MopeliumMacApp {
    static func main() {
        print("MopeliumMac is a macOS SwiftUI app.")
    }
}
#endif
