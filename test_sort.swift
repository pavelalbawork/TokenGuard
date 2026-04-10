import Foundation

struct Window {
    let label: String?
}

var uniqueWindows = [
    Window(label: "FLASH"),
    Window(label: "PRO")
]

let order = ["PRO": 0, "FLASH": 1, "LITE": 2]

uniqueWindows.sort {
    (order[$0.label ?? ""] ?? 99) < (order[$1.label ?? ""] ?? 99)
}

for w in uniqueWindows {
    print(w.label!)
}
