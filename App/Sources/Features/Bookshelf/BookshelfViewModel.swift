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
    var usesGrid = false
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
            guard request == generation, groupID == selectedGroupID else { return }
            books = loadedBooks
            groups = loadedGroups.filter { $0.show && $0.groupId != -1 }
        } catch {
            guard request == generation, groupID == selectedGroupID else { return }
            errorMessage = error.localizedDescription
        }
    }
}
