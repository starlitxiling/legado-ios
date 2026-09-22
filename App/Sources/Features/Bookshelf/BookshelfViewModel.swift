import Observation
import LegadoCore

protocol BookshelfReading {
    func list(groupID: Int64, sort: BookshelfSort) async throws -> [BookRow]
}

extension Repository: BookshelfReading where Record == BookRow {}

protocol BookGroupReading {
    func list() async throws -> [BookGroupRow]
}

extension Repository: BookGroupReading where Record == BookGroupRow {}

@Observable
@MainActor
final class BookshelfViewModel {
    private(set) var books: [BookRow] = []
    private(set) var groups: [BookGroupRow] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    var selectedGroupID: Int64 = -1
    var folderMode = false
    private(set) var groupPreviews: [Int64: [BookRow]] = [:]
    private(set) var groupCounts: [Int64: Int] = [:]
    private(set) var recentBook: BookRow?
    private(set) var shelfBookCount = 0
    private(set) var readingCount = 0
    var sort: BookshelfSort = .lastRead
    var isEmpty: Bool { books.isEmpty && !isLoading && errorMessage == nil }

    private let bookshelf: any BookshelfReading
    private let groupRepository: any BookGroupReading
    private var generation = 0

    init(bookshelf: any BookshelfReading, groups: any BookGroupReading) {
        self.bookshelf = bookshelf
        groupRepository = groups
    }

    func load() async {
        generation += 1
        let request = generation
        let groupID = selectedGroupID
        isLoading = true
        errorMessage = nil
        defer { if request == generation { isLoading = false } }
        do {
            let loadedGroups = try await groupRepository.list()
            let groupSort = loadedGroups.first { $0.groupId == groupID }?.bookSort ?? -1
            let effectiveSort: BookshelfSort
            switch groupSort {
            case 0: effectiveSort = .lastRead
            case 1: effectiveSort = .latestUpdate
            case 2: effectiveSort = .name
            case 3: effectiveSort = .manual
            case 4: effectiveSort = .combined
            case 5: effectiveSort = .author
            default: effectiveSort = sort
            }
            let loadedBooks = try await bookshelf.list(groupID: groupID, sort: effectiveSort)
            let allBooks = groupID == -1 ? loadedBooks : try await bookshelf.list(groupID: -1, sort: .lastRead)
            guard !Task.isCancelled, request == generation, groupID == selectedGroupID else { return }
            var previews: [Int64: [BookRow]] = [:]
            var counts: [Int64: Int] = [:]
            if folderMode && groupID == -100 {
                for group in loadedGroups where group.show {
                    let groupBooks = try await bookshelf.list(groupID: group.groupId, sort: BookshelfSort(rawValue: group.bookSort) ?? sort)
                    previews[group.groupId] = Array(groupBooks.prefix(4))
                    counts[group.groupId] = groupBooks.count
                }
            }
            guard !Task.isCancelled, request == generation, groupID == selectedGroupID else { return }
            books = loadedBooks
            groups = loadedGroups.filter { $0.show }
            groupPreviews = previews
            groupCounts = counts
            shelfBookCount = allBooks.count
            readingCount = allBooks.filter { $0.durChapterIndex > 0 || $0.durChapterPos > 0 }.count
            recentBook = allBooks.max {
                let firstStarted = $0.durChapterIndex > 0 || $0.durChapterPos > 0
                let secondStarted = $1.durChapterIndex > 0 || $1.durChapterPos > 0
                if firstStarted != secondStarted { return !firstStarted }
                return $0.durChapterTime < $1.durChapterTime
            }
        } catch {
            guard !error.isCancellation, request == generation, groupID == selectedGroupID else { return }
            errorMessage = error.presentableMessage
        }
    }
}
