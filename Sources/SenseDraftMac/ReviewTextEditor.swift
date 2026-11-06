import AppKit
import SwiftUI

enum ReviewEditorHeight {
    static func calculate(text: String, width: CGFloat, minimum: CGFloat, maximum: CGFloat,
                          verticalInset: CGFloat = 24) -> CGFloat {
        if text.utf16.count > 2_000 { return maximum }
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let availableWidth = max(1, width - 26)
        let visibleText = text.isEmpty ? " " : text + (text.hasSuffix("\n") ? " " : "")
        let bounds = (visibleText as NSString).boundingRect(
            with: CGSize(width: availableWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        return min(maximum, max(minimum, ceil(bounds.height) + verticalInset))
    }
}

struct ReviewTextEditor: View {
    @Binding var text: String
    let minimumHeight: CGFloat
    let maximumHeight: CGFloat
    let enabled: Bool
    @State private var width: CGFloat = 500

    var body: some View {
        TextEditor(text: $text)
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(5)
            .frame(maxWidth: .infinity)
            .frame(height: ReviewEditorHeight.calculate(text: text, width: width,
                                                       minimum: minimumHeight, maximum: maximumHeight))
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color(nsColor: .separatorColor)))
            .background {
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { width = geometry.size.width }
                        .onChange(of: geometry.size.width) { _, newWidth in width = newWidth }
                }
            }
            .disabled(!enabled)
    }
}
