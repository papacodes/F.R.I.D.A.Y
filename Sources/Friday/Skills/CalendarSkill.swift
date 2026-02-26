import Foundation

struct CalendarSkill {
    static func addEvent(title: String, startTime: String, endTime: String?) -> String {
        let endPart = endTime != nil ? ", end date:date \"\(endTime!)\"" : ""
        let script = "tell application \"Calendar\"\n" +
                     "try\n" +
                     "  set targetCal to first calendar whose name is \"Calendar\" or name is \"Work\"\n" +
                     "  tell targetCal\n" +
                     "    make new event with properties {summary:\"\(title)\", start date:date \"\(startTime)\"\(endPart)}\n" +
                     "  end tell\n" +
                     "  return \"Successfully added \(title) to \" & name of targetCal\n" +
                     "on error err\n" +
                     "  return \"Error adding event: \" & err\n" +
                     "end try\n" +
                     "end tell"
        return MusicSkill.executeAppleScript(script)
    }

    static func getSchedule(forDate dateString: String? = nil) -> String {
        let targetDateScript = (dateString != nil && !dateString!.isEmpty) ? "date \"\(dateString!)\"" : "current date"
        
        let script = "tell application \"Calendar\"\n" +
                     "try\n" +
                     "  set targetDate to \(targetDateScript)\n" +
                     "on error\n" +
                     "  set targetDate to current date\n" +
                     "end try\n" +
                     "set time of targetDate to 0\n" +
                     "set endOfPeriod to targetDate + (24 * 60 * 60)\n" +
                     "set output to \"\"\n" +
                     "repeat with i from 1 to count of calendars\n" +
                     "  set aCal to calendar i\n" +
                     "  set calName to name of aCal\n" +
                     "  if calName is not \"Birthdays\" and calName is not \"Siri Suggestions\" then\n" +
                     "    try\n" +
                     "      set dailyEvents to (every event of aCal whose (start date is greater than or equal to targetDate and start date is less than endOfPeriod) or (start date is less than targetDate and end date is greater than targetDate))\n" +
                     "      repeat with anEvent in dailyEvents\n" +
                     "        set output to output & \"(\" & calName & \") \" & summary of anEvent & \" at \" & (time string of (get start date of anEvent)) & \"\\n\"\n" +
                     "      end repeat\n" +
                     "    end try\n" +
                     "  end if\n" +
                     "end repeat\n" +
                     "if output is \"\" then return \"I checked your calendars but found no events for this period.\"\n" +
                     "return output\n" +
                     "end tell"
        return MusicSkill.executeAppleScript(script)
    }
}
