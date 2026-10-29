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
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Permissions").font(.title2.bold())
                    Text("Control how SenseDraft works with other apps.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            Divider()
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("ACCESS")
                        .font(.caption2.weight(.semibold)).tracking(0.8)
                        .foregroundStyle(.secondary)
                        .padding(16)
                    Label("Accessibility", systemImage: "hand.raised")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.accentColor.opacity(0.15),
                                    in: RoundedRectangle(cornerRadius: 9))
                        .padding(.horizontal, 8)
                    Spacer()
                }
                .frame(width: 258)
                .background(Color(nsColor: .controlBackgroundColor))
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            Text("Accessibility").font(.title3.weight(.semibold))
                            Spacer()
                            Label(authorized ? "Access granted" : "Access needed",
                                  systemImage: authorized ? "checkmark.circle.fill" : "exclamationmark.circle")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(authorized ? .green : .orange)
                        }
                        Divider()
                        Text("SenseDraft reads the focused input only after you press Analyze. Accessibility access lets it read and replace text in other apps.")
                            .font(.callout)
                        if !authorized {
                            Text("After rebuilding an ad hoc signed app, macOS may keep an older permission entry. Remove that entry, add this build, then reopen SenseDraft.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 8) {
                            Button("Request access") { PermissionGuide.request(); refresh() }
                            Button("Open System Settings") { PermissionGuide.openSystemSettings() }
                            Button("Check again") { refresh() }
                        }
                        Button("Reveal this app in Finder") { PermissionGuide.revealCurrentApp() }
                            .buttonStyle(.link)
                    }
                    .frame(maxWidth: 510, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(24)
                }
            }
        }
        .navigationTitle("Permissions")
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }
    private func refresh() { authorized = PermissionGuide.isAuthorized }
}
