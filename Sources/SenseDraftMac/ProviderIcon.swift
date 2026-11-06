import AppKit
import SwiftUI

struct ProviderIcon: View {
    let name: String
    let size: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if let assetName,
               let url = Bundle.main.url(forResource: assetName, withExtension: "png", subdirectory: "ProviderIcons"),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: symbolName)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.18)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var assetName: String? {
        switch name {
        case "DeepSeek": "deepseek"
        case "Kimi": "kimi"
        case "OpenAI", "OpenAI API", "ChatGPT plan": colorScheme == .dark ? "openai-dark" : "openai-light"
        case "Claude": "claude"
        case "Gemini": "gemini"
        case "OpenRouter": colorScheme == .dark ? "openrouter-dark" : "openrouter-light"
        case "Qwen": "qwen"
        case "Ollama": "ollama"
        default: nil
        }
    }

    private var symbolName: String {
        switch name {
        case "Custom endpoint": "slider.horizontal.3"
        case "Apple on-device": "apple.logo"
        default: "sparkles"
        }
    }
}
