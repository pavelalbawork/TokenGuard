import SwiftUI

struct CountdownTimerText: View {
    let resetDate: Date

    var body: some View {
        let referenceNow = Date()
        let interval = resetDate.timeIntervalSince(referenceNow)
        
        if interval > 86400 {
            TimelineView(.periodic(from: referenceNow, by: 60)) { context in
                let now = context.date
                let currentInterval = resetDate.timeIntervalSince(now)
                
                if currentInterval > 86400 {
                    let days = Int(currentInterval / 86400)
                    let hours = Int((currentInterval.truncatingRemainder(dividingBy: 86400)) / 3600)
                    let daysStr = days == 1 ? "1 day" : "\(days) days"
                    let hoursStr = hours == 1 ? "1 hour" : "\(hours) hours"
                    Text("\(daysStr), \(hoursStr)")
                } else {
                    let end = resetDate > now ? resetDate : now
                    Text(timerInterval: now...end, countsDown: true)
                }
            }
        } else {
            let end = resetDate > referenceNow ? resetDate : referenceNow
            Text(timerInterval: referenceNow...end, countsDown: true)
        }
    }
}
