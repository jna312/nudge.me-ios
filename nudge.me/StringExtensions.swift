import Foundation

extension String {
    /// Convert number words to digits (one -> 1, two -> 2, etc.)
    func normalizeNumberWords() -> String {
        let map: [String: String] = [
            "one":"1","two":"2","three":"3","four":"4","five":"5","six":"6",
            "seven":"7","eight":"8","nine":"9","ten":"10","eleven":"11","twelve":"12"
        ]
        var result = self.lowercased()
        for (word, digit) in map {
            result = result.replacingOccurrences(of: "\\b\(word)\\b", with: digit, options: .regularExpression)
        }
        return result
    }
}
