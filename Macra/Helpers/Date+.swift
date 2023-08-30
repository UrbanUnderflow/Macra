import Foundation

extension Date {
    var year: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        formatter.locale = Locale(identifier: "en_US_POSIX") // English language
        return formatter.string(from: self)
    }
    
    var monthDayHourFormat: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM dd, h:mma"
        formatter.amSymbol = "am"
        formatter.pmSymbol = "pm"
        return formatter.string(from: self)
    }
    
    var monthDayFormat: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM dd"
        return formatter.string(from: self)
    }
    
    var dayMonthYearFormat: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd-MMMM-yyyy"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: self)
    }
}

//Used for calendar
extension Date {
    var monthYearFormat: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMMM yyyy"
        return dateFormatter.string(from: self)
    }
    
    var dayFormat: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "d"
        return dateFormatter.string(from: self)
    }
    
    var startOfMonth: Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Calendar.current.startOfDay(for: self)))!
    }
}


extension Date {
    var timeFormat: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mma"
        formatter.amSymbol = "am"
        formatter.pmSymbol = "pm"
        return formatter.string(from: self)
    }
    
    static func random(between startYear: Int, and endYear: Int) -> Date? {
            guard startYear <= endYear else { return nil }
            
            let startOfYear = Calendar.current.date(from: DateComponents(year: startYear, month: 1, day: 1))
            let endOfYear = Calendar.current.date(from: DateComponents(year: endYear, month: 12, day: 31))
            
            guard let start = startOfYear, let end = endOfYear else { return nil }
            
            return Date.random(from: start, to: end)
    }
    
    static func random(from startDate: Date, to endDate: Date) -> Date {
            let interval = endDate.timeIntervalSince(startDate)
            let randomInterval = TimeInterval(arc4random_uniform(UInt32(interval)))
            return startDate.addingTimeInterval(randomInterval)
    }
}
