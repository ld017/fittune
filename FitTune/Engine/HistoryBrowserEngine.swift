import Foundation

enum HistoryBrowserItemType: String, CaseIterable, Hashable {
    case strength
    case cardio
    case sport
}

struct HistorySportProjection: Identifiable, Equatable {
    var id: UUID
    var date: Date
    var title: String
    var searchTerms: [String]
}

struct HistoryBrowserItem: Identifiable, Equatable {
    var id: UUID
    var type: HistoryBrowserItemType
    var date: Date
    var title: String
    var searchTerms: [String]
}

struct HistoryBrowserFilter: Equatable {
    var types: Set<HistoryBrowserItemType>
    var startDate: Date?
    var endDate: Date?
    var query: String

    init(
        types: Set<HistoryBrowserItemType> = Set(HistoryBrowserItemType.allCases),
        startDate: Date? = nil,
        endDate: Date? = nil,
        query: String = ""
    ) {
        self.types = types
        self.startDate = startDate
        self.endDate = endDate
        self.query = query
    }
}

enum HistoryBrowserEngine {
    static func browse(
        strength: [WorkoutRecord],
        cardio: [CardioWorkoutRecord],
        sports: [HistorySportProjection],
        filter: HistoryBrowserFilter = HistoryBrowserFilter()
    ) -> [HistoryBrowserItem] {
        let items = strength.map(item)
            + cardio.map(item)
            + sports.map(item)
        let query = filter.query.trimmingCharacters(in: .whitespacesAndNewlines)

        return items.filter { item in
            guard filter.types.contains(item.type),
                  filter.startDate.map({ item.date >= $0 }) ?? true,
                  filter.endDate.map({ item.date <= $0 }) ?? true else {
                return false
            }
            guard !query.isEmpty else { return true }
            return ([item.title] + item.searchTerms).contains {
                $0.localizedCaseInsensitiveContains(query)
            }
        }
        .sorted {
            if $0.date != $1.date { return $0.date > $1.date }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private static func item(_ record: WorkoutRecord) -> HistoryBrowserItem {
        HistoryBrowserItem(
            id: record.id,
            type: .strength,
            date: record.completedAt,
            title: record.sessionName,
            searchTerms: record.sets.map(\.exerciseName)
        )
    }

    private static func item(_ record: CardioWorkoutRecord) -> HistoryBrowserItem {
        HistoryBrowserItem(
            id: record.id,
            type: .cardio,
            date: record.date,
            title: record.modality.title,
            searchTerms: [record.intensity.title, record.source]
        )
    }

    private static func item(_ record: HistorySportProjection) -> HistoryBrowserItem {
        HistoryBrowserItem(
            id: record.id,
            type: .sport,
            date: record.date,
            title: record.title,
            searchTerms: record.searchTerms
        )
    }
}
