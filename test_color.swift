import Foundation

let hex = "#111111".trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
var int: UInt64 = 0
Scanner(string: hex).scanHexInt64(&int)
print("hex string:", hex)
print("parsed int:", int)

let a = 255
let r = int >> 16
let g = int >> 8 & 0xFF
let b = int & 0xFF
print("r:\(r) g:\(g) b:\(b) a:\(a)")
