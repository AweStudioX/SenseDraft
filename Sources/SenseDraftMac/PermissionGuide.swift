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
                Text("If SenseDraft is already enabled in System Settings, remove its old entry, add the current SenseDraft.app again, then restart SenseDraft. Rebuilding a locally signed app can invalidate its earlier grant.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Request access") { PermissionGuide.request(); refresh() }
                Button("Open System Settings") { PermissionGuide.openSystemSettings() }
                Button("Check again") { refresh() }
            }
            Spacer()
        }
        .padding(24)
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }

    private func refresh() { authorized = PermissionGuide.isAuthorized }
}
