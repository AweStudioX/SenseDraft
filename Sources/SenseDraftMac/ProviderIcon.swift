import AppKit
import SwiftUI

struct ProviderIcon: View {
    let name: String
    let size: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if let url = Bundle.main.url(forResource: assetName, withExtension: "png", subdirectory: "ProviderIcons"),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "sparkles")
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.18)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var assetName: String {
        switch name {
        case "DeepSeek": "deepseek"
        case "Kimi": "kimi"
        default: colorScheme == .dark ? "openai-dark" : "openai-light"
        }
    }
}
