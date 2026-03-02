import EventKit
import Foundation
import SwiftUI

// Lightweight struct the UI uses — no EKEvent dependency outside this file.
struct CalendarEventItem: Identifiable {
    let id = UUID()
    let title: String
    let startDate: Date
    let isAllDay: Bool
    let calendarTitle: String
    let calendarColor: Color
}

struct CalendarSkill {

    // MARK: - Access

    private static func authorized() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14.0, *) {
            if status == .fullAccess { return true }
        } else {
            if status == .authorized { return true }
        }

        let store = EKEventStore()
        if #available(macOS 14.0, *) {
            return (try? await store.requestFullAccessToEvents()) ?? false
        } else {
            return await withCheckedContinuation { cont in
                store.requestAccess(to: .event) { granted, _ in
                    cont.resume(returning: granted)
                }
            }
        }
    }

    // MARK: - Get Schedule

    static func getSchedule(forDate dateString: String? = nil) async -> String {
        guard await authorized() else {
            return "I don't have calendar access yet. Please allow it in System Settings → Privacy & Security → Calendars, then try again."
        }

        let targetDate: Date
        if let ds = dateString, !ds.isEmpty {
            targetDate = DateHelper.parseDate(ds) ?? Date()
        } else {
            targetDate = Date()
        }

        let store = EKEventStore()
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: targetDate)
        let endOfDay   = cal.date(byAdding: .day, value: 1, to: startOfDay)!

        let pred   = store.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: nil)
        let events = store.events(matching: pred).sorted { $0.startDate < $1.startDate }

        let dayFmt = DateFormatter()
        dayFmt.dateStyle = .full
        dayFmt.timeStyle = .none

        let timeFmt = DateFormatter()
        timeFmt.timeStyle = .short
        timeFmt.dateStyle = .none

        if events.isEmpty {
            return "No events on \(dayFmt.string(from: targetDate))."
        }

        let lines = events.map { e -> String in
            let title = e.title ?? "Untitled"
            let calName = e.calendar.title
            if e.isAllDay { return "• [\(calName)] \(title) — all day" }
            return "• [\(calName)] \(title) at \(timeFmt.string(from: e.startDate))"
        }

        return "Schedule for \(dayFmt.string(from: targetDate)):\n" + lines.joined(separator: "\n")
    }

    // MARK: - Structured Events (for UI)

    /// Returns today's events as structured items ready for the calendar tab view.
    static func todayEvents(for date: Date = Date()) async -> [CalendarEventItem] {
        guard await authorized() else { return [] }

        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        let end   = cal.date(byAdding: .day, value: 1, to: start)!

        let store = EKEventStore()
        let pred  = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: pred)
            .sorted { $0.startDate < $1.startDate }
            .map { e in
                CalendarEventItem(
                    title:         e.title ?? "Untitled",
                    startDate:     e.startDate,
                    isAllDay:      e.isAllDay,
                    calendarTitle: e.calendar.title,
                    calendarColor: Color(cgColor: e.calendar.cgColor)
                )
            }
    }

    // MARK: - Add Event

    static func addEvent(title: String, startTimeString: String, endTimeString: String?) async -> String {
        guard await authorized() else {
            return "I don't have calendar access. Please allow it in System Settings → Privacy & Security → Calendars."
        }

        guard let start = DateHelper.parseDate(startTimeString) else {
            return "I couldn't understand the start time '\(startTimeString)'. Try something like 'today at 3pm' or 'tomorrow at 9am'."
        }

        let end: Date
        if let es = endTimeString, let parsed = DateHelper.parseDate(es) {
            end = parsed
        } else {
            end = start.addingTimeInterval(3600) // default 1 hour
        }

        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.title     = title
        event.startDate = start
        event.endDate   = end
        event.calendar  = store.defaultCalendarForNewEvents

        do {
            try store.save(event, span: .thisEvent)
            let fmt = DateFormatter()
            fmt.dateStyle = .medium
            fmt.timeStyle = .short
            return "Added '\(title)' on \(fmt.string(from: start))."
        } catch {
            return "Couldn't save the event: \(error.localizedDescription)"
        }
    }
}
