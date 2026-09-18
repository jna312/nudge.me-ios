import Foundation

extension String {
    /// Convert number words to digits (one -> 1, two -> 2, etc.)
    func normalizeNumberWords() -> String {
        let map: [String: String] = [
            "one":"1","two":"2","three":"3","four":"4","five":"5","six":"6",
            "seven":"7","eight":"8","nine":"9","ten":"10","eleven":"11","twelve":"12",
            "thirteen":"13","fourteen":"14","fifteen":"15","sixteen":"16","seventeen":"17",
            "eighteen":"18","nineteen":"19","twenty":"20","thirty":"30","forty":"40","fifty":"50","sixty":"60"
        ]
        var result = self.lowercased()
        for (word, digit) in map {
            result = result.replacingOccurrences(of: "\\b\(word)\\b", with: digit, options: .regularExpression)
        }
        result = result.replacingOccurrences(of: #"\b(at|by)\s+(\d{1,2})\s+(\d{2})\b"#, with: "$1 $2:$3", options: .regularExpression)
        return result
    }
}
