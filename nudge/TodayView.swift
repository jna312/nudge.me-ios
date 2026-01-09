import SwiftUI
import SwiftData

struct TodayView: View {
    @Query(sort: \ReminderItem.createdAt, order: .reverse) private var reminders: [ReminderItem]

    var body: some View {
        List {
            ForEach(reminders.filter { $0.status == .open }) { r in
                VStack(alignment: .leading, spacing: 4) {
                    Text(r.title)
                    if let due = r.dueAt {
                        Text("\(due, style: .date) \(due, style: .time)")
                    }
                }
            }
        }
        .navigationTitle("Today")
    }
}
