import Foundation

enum DistanceUnit: String, CaseIterable, Identifiable {
    case kilometers
    case miles

    var id: String { rawValue }

    var title: String {
        switch self {
        case .kilometers: return "Kilometers"
        case .miles: return "Miles"
        }
    }

    var abbreviation: String {
        switch self {
        case .kilometers: return "km"
        case .miles: return "mi"
        }
    }

    var metersPerUnit: Double {
        switch self {
        case .kilometers: return 1000
        case .miles: return 1609.344
        }
    }

    func value(fromMeters meters: Double) -> Double {
        meters / metersPerUnit
    }
}

/// Shared display formatting so every screen shows numbers the same way.
enum Format {
    private static let integerFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()

    static func steps(_ steps: Int) -> String {
        integerFormatter.string(from: NSNumber(value: steps)) ?? "\(steps)"
    }

    /// "4.52" (no unit).
    static func distanceValue(_ meters: Double, unit: DistanceUnit) -> String {
        String(format: "%.2f", unit.value(fromMeters: max(0, meters)))
    }

    /// "4.52 km".
    static func distance(_ meters: Double, unit: DistanceUnit) -> String {
        "\(distanceValue(meters, unit: unit)) \(unit.abbreviation)"
    }

    /// Short distance for turn-by-turn: "120 m" / "0.3 km", or "400 ft" / "0.3 mi".
    static func shortDistance(_ meters: Double, unit: DistanceUnit) -> String {
        let meters = max(0, meters)
        switch unit {
        case .kilometers:
            if meters < 950 {
                return "\(Int((meters / 10).rounded()) * 10) m"
            }
            return String(format: "%.1f km", meters / 1000)
        case .miles:
            let feet = meters * 3.28084
            if feet < 1000 {
                return "\(Int((feet / 10).rounded()) * 10) ft"
            }
            return String(format: "%.1f mi", meters / unit.metersPerUnit)
        }
    }

    /// "44:58" or "1:04:58".
    static func duration(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    /// Short duration estimate: "45 min" / "1 h 20 min".
    static func durationEstimate(_ interval: TimeInterval) -> String {
        let minutes = max(1, Int((interval / 60).rounded()))
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    /// Pace like 9'09" per km / mi. Returns "--" when there is no meaningful pace yet.
    static func pace(distance meters: Double, duration: TimeInterval, unit: DistanceUnit) -> String {
        guard meters > 20, duration > 0 else { return "--" }
        let secondsPerUnit = duration / unit.value(fromMeters: meters)
        guard secondsPerUnit.isFinite, secondsPerUnit < 60 * 60 else { return "--" }
        let total = Int(secondsPerUnit.rounded())
        return String(format: "%d'%02d\"", total / 60, total % 60)
    }

    static func calories(_ kcal: Double) -> String {
        integerFormatter.string(from: NSNumber(value: kcal.rounded())) ?? "\(Int(kcal))"
    }

    static func elevation(_ meters: Double, unit: DistanceUnit) -> String {
        switch unit {
        case .kilometers: return "\(Int(meters.rounded())) m"
        case .miles: return "\(Int((meters * 3.28084).rounded())) ft"
        }
    }
}
