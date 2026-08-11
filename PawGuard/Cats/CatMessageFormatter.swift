import Foundation

enum CatMessage {
    private static let detectedMessages = [
        "%@ found the keyboard 🐾",
        "%@'s paws are on the keys",
        "Keyboard paused for %@",
        "Tiny paws detected near %@",
        "%@ is guarding the keyboard",
    ]

    static func detected(catName: String) -> String {
        let template = detectedMessages.randomElement() ?? "%@ is typing! 🐾"
        return String(format: template, catName)
    }

    static func released(catName: String) -> String {
        "\(catName) has left the keyboard ✨"
    }

    static func subtitle(remaining: TimeInterval) -> String {
        "Input is paused for \(max(0, Int(remaining.rounded(.up)))) more seconds."
    }
}
