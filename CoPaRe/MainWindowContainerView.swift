import SwiftUI

struct MainWindowContainerView: View {
    @EnvironmentObject private var windowCoordinator: WindowCoordinator
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ContentView()
            .onAppear {
                windowCoordinator.setOpenMainWindowAction {
                    openWindow(id: "main")
                }
            }
    }
}
