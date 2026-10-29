import Foundation

/// Small status snapshot the app writes into the shared App Group container and
/// the widget reads. Compiled into both the app and the widget extension, so it
/// depends on Foundation only.
struct WidgetSnapshot: Codable {
    var dayKey: String
    var done: Int
    var total: Int
    var penaltyPending: Bool
    var deload: Bool
    var streak: Int
    var level: Int
    var rank: String
    var rankTitle: String
    var xpInto: Int
    var xpSpan: Int
    var eveningMinutes: Int
    var pending: [String]
    var updated: Date

    var complete: Bool { total > 0 && done >= total }

    static let baseGroup = "group.org.zyco.system"
    static let fileName = "widget-snapshot.json"

    /// App Group identifiers to try, most specific first. AltStore/SideStore can
    /// rewrite group ids when re-signing with a free account (usually by
    /// appending the team id), so the base id alone is not enough.
    static var groupCandidates: [String] {
        var ids: [String] = []
        if let alt = Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] {
            ids += alt.filter { $0.hasPrefix(baseGroup) }
        }
        ids.append(baseGroup)
        // SideStore re-signs as org.zyco.system.<TEAMID>[.widget]; the widget's
        // bundle id has the team id in the middle, so scan every component.
        if let bid = Bundle.main.bundleIdentifier,
           let team = bid.split(separator: ".").first(where: { c in
               c.count == 10 && c.allSatisfy { $0.isUppercase || $0.isNumber }
           }) {
            ids.append(baseGroup + "." + team)
        }
        return ids
    }

    static func containerURL() -> URL? {
        for id in groupCandidates {
            if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) {
                return url
            }
        }
        return nil
    }

    static var fileURL: URL? { containerURL()?.appendingPathComponent(fileName) }

    static func load() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// Returns false when there is no shared container (widget simply shows its
    /// "open the app" state).
    @discardableResult
    func write() -> Bool {
        guard let url = Self.fileURL, let data = try? JSONEncoder().encode(self) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    /// Same content, ignoring the timestamp; used to skip redundant widget reloads.
    func sameContent(as other: WidgetSnapshot?) -> Bool {
        guard var o = other else { return false }
        o.updated = updated
        let e = JSONEncoder()
        e.outputFormatting = .sortedKeys
        return (try? e.encode(o)) == (try? e.encode(self))
    }

    static func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    static let sample = WidgetSnapshot(dayKey: dayKey(.now), done: 3, total: 5, penaltyPending: false, deload: false,
                                       streak: 6, level: 7, rank: "D", rankTitle: "Initiate", xpInto: 90, xpSpan: 220,
                                       eveningMinutes: 20 * 60, pending: ["Perception: Reaction", "Reach Out"],
                                       updated: .now)
}
