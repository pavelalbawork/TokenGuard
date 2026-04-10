import SwiftUI

struct CountdownTimerText: View {
    let resetDate: Date

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 60)) { context in
            Text(remainingText(now: context.date))
        }
    }

    private func remainingText(now: Date) -> String {
        let interval = resetDate.timeIntervalSince(now)
        guard interval > 0 else { return "now" }

        let totalMinutes = max(1, Int(ceil(interval / 60)))
        let days = totalMinutes / 1_440
        let hours = (totalMinutes % 1_440) / 60
        let minutes = totalMinutes % 60

        if days > 0 {
            let daysText = days == 1 ? "1 day" : "\(days) days"
            guard hours > 0 else { return daysText }
            let hoursText = hours == 1 ? "1 hour" : "\(hours) hours"
            return "\(daysText), \(hoursText)"
        }

        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }

        return "\(minutes)m"
    }
}
