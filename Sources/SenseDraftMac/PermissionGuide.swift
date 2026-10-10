import AppKit
import ApplicationServices
import SwiftUI

@MainActor
enum PermissionGuide {
    static var isAuthorized: Bool { AXIsProcessTrusted() }

    static func request() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    static func revealCurrentApp() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }
}

struct PermissionSettingsView: View {
    @State private var authorized = PermissionGuide.isAuthorized

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Accessibility access")
                .font(.title2.bold())
            Text("SenseDraft reads the focused input only when you press Analyze. It needs macOS Accessibility access to read and replace text in other apps.")
                .fixedSize(horizontal: false, vertical: true)
            Label(authorized ? "Access granted" : "Access needed", systemImage: authorized ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(authorized ? .green : .orange)
            if !authorized {
                Text("This build uses an ad hoc signature. After the app code changes, macOS may keep an old SenseDraft switch on while denying the new build. Remove the old entry, reveal and add this exact app, then quit and reopen it.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Request access") { PermissionGuide.request(); refresh() }
                Button("Open System Settings") { PermissionGuide.openSystemSettings() }
                Button("Check again") { refresh() }
            }
            Button("Reveal this app in Finder") { PermissionGuide.revealCurrentApp() }
            Spacer()
        }
        .padding(24)
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }

    private func refresh() { authorized = PermissionGuide.isAuthorized }
}
