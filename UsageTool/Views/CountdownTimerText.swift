import SwiftUI

struct CountdownTimerText: View {
    let resetDate: Date

    var body: some View {
        let now = Date()
        let end = resetDate > now ? resetDate : now
        Text(timerInterval: now...end, countsDown: true)
            .font(.system(.caption, design: .rounded).monospacedDigit())
            .foregroundStyle(.secondary)
    }
}
