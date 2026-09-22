import Foundation
import GRDB

extension Error {
    var isCancellation: Bool {
        var current: Error = self
        var visited = Set<ObjectIdentifier>()
        let cancellation = CancellationError() as NSError
        for _ in 0..<16 {
            if current is CancellationError { return true }
            if let database = current as? DatabaseError, database.resultCode == .SQLITE_INTERRUPT { return true }
            let error = current as NSError
            if error.domain == NSURLErrorDomain && error.code == URLError.cancelled.rawValue { return true }
            if error.domain == cancellation.domain && error.code == cancellation.code { return true }
            guard visited.insert(ObjectIdentifier(error)).inserted,
                  let underlying = error.userInfo[NSUnderlyingErrorKey] as? Error else { return false }
            current = underlying
        }
        return false
    }

    var presentableMessage: String? {
        isCancellation ? nil : localizedDescription
    }
}
