import SwiftUI

/// 时间窗口的分钟制与展示换算
enum ScheduleTime {
    static func date(fromMinutes minutes: Int, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
    }

    static func minutes(from date: Date, calendar: Calendar = .current) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    static func display(minutes: Int) -> String {
        date(fromMinutes: minutes).formatted(date: .omitted, time: .shortened)
    }
}

struct ScheduleEditorView: View {
    let isEnabling: Bool
    let onSave: ([ScheduleRule]) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var rules: [ScheduleRule]
    @State private var saveFailed = false

    init(rules: [ScheduleRule], isEnabling: Bool = false,
         onSave: @escaping ([ScheduleRule]) -> Bool) {
        _rules = State(initialValue: rules)
        self.isEnabling = isEnabling
        self.onSave = onSave
    }

    private var weekdays: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }

    var body: some View {
        NavigationStack {
            XLScreen(spacing: XL.Space.l) {
                ForEach($rules) { $rule in
                    XLCard(padding: XL.Space.m) {
                        VStack(alignment: .leading, spacing: XL.Space.m) {
                            HStack {
                                Text("rules.window", tableName: "ScheduleExperience")
                                    .font(.headline)
                                Spacer()
                                Button(role: .destructive) {
                                    rules.removeAll { $0.id == rule.id }
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .accessibilityLabel(Text("rules.remove", tableName: "ScheduleExperience"))
                            }
                            HStack(spacing: 4) {
                                ForEach(weekdays, id: \.self) { weekday in
                                    Button {
                                        if rule.weekdays.contains(weekday) {
                                            rule.weekdays.remove(weekday)
                                        } else {
                                            rule.weekdays.insert(weekday)
                                        }
                                    } label: {
                                        Text(Calendar.current.veryShortWeekdaySymbols[weekday - 1])
                                            .font(.subheadline.weight(.semibold))
                                            .frame(maxWidth: .infinity, minHeight: 44)
                                            .background(rule.weekdays.contains(weekday) ? XL.primary.opacity(0.18) : XL.bg)
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                    }
                                    .accessibilityLabel(Calendar.current.weekdaySymbols[weekday - 1])
                                    .accessibilityAddTraits(rule.weekdays.contains(weekday) ? .isSelected : [])
                                }
                            }
                            DatePicker("schedule.start", selection: timeBinding($rule.startMinutes),
                                       displayedComponents: .hourAndMinute)
                            DatePicker("schedule.end", selection: timeBinding($rule.endMinutes),
                                       displayedComponents: .hourAndMinute)
                            if !LockSchedule.isValid(rule: rule) {
                                Text("rules.invalid", tableName: "ScheduleExperience")
                                    .font(.footnote).foregroundStyle(XL.danger)
                            } else if rule.endMinutes < rule.startMinutes {
                                Text("rules.overnight", tableName: "ScheduleExperience")
                                    .font(.footnote).foregroundStyle(XL.muted)
                            }
                        }
                        .foregroundStyle(XL.ink)
                    }
                }
                Button {
                    rules.append(ScheduleRule(startMinutes: 21 * 60, endMinutes: 7 * 60))
                } label: {
                    Label {
                        Text("rules.add", tableName: "ScheduleExperience")
                    } icon: {
                        Image(systemName: "plus")
                    }
                }
                .disabled(rules.count >= LockSchedule.maximumRules)
                Text("rules.description", tableName: "ScheduleExperience")
                    .font(.footnote).foregroundStyle(XL.muted)
                if saveFailed {
                    Text("rules.save.failed", tableName: "ScheduleExperience")
                        .font(.footnote).foregroundStyle(XL.danger)
                }
                Button(isEnabling ? "schedule.enable" : "schedule.save") {
                    if onSave(rules) { dismiss() } else { saveFailed = true }
                }
                .buttonStyle(XLPrimaryButtonStyle())
                .disabled(!LockSchedule.isValid(rules: rules))
            }
            .navigationTitle(isEnabling ? "schedule.enable.title" : "schedule.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("common.close") { dismiss() }.foregroundStyle(XL.ink)
            }
            .toolbarBackground(XL.bg, for: .navigationBar)
        }
        .tint(XL.primary)
    }

    private func timeBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(get: { ScheduleTime.date(fromMinutes: minutes.wrappedValue) },
                set: { minutes.wrappedValue = ScheduleTime.minutes(from: $0) })
    }
}
