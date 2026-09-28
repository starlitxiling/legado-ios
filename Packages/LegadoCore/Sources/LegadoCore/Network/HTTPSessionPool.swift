import Foundation
import Security

final class HTTPSessionPool: @unchecked Sendable {
    struct Key: Hashable {
        let proxy: HttpProxy?
        let tlsHost: String?
        let direct: Bool
    }
    struct Entry {
        let session: URLSession
        let delegate: HTTPSessionDelegate
    }
    private let lock = NSLock()
    private let protocolClasses: [AnyClass]
    private var entries: [Key: Entry] = [:]
    private var order: [Key] = []

    init(protocolClasses: [AnyClass]) { self.protocolClasses = protocolClasses }
    deinit { for entry in entries.values { entry.session.finishTasksAndInvalidate() } }

    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return entries.count
    }

    func entry(for route: NetworkRoute) -> Entry {
        let key = Key(proxy: route.request.proxy, tlsHost: route.tlsHost, direct: route.direct)
        lock.lock(); defer { lock.unlock() }
        order.removeAll { $0 == key }; order.append(key)
        if let entry = entries[key] { return entry }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForResource = 7 * 24 * 60 * 60
        if !protocolClasses.isEmpty { configuration.protocolClasses = protocolClasses }
        if let proxy = key.proxy { proxy.apply(to: configuration) }
        else if key.direct { configuration.connectionProxyDictionary = [:] }
        let delegate = HTTPSessionDelegate(proxy: key.proxy, tlsHost: key.tlsHost)
        let entry = Entry(session: URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil), delegate: delegate)
        entries[key] = entry
        if order.count > 32, let removed = entries.removeValue(forKey: order.removeFirst()) {
            removed.session.finishTasksAndInvalidate()
        }
        return entry
    }
}

final class HTTPSessionDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let proxy: HttpProxy?
    private let tlsHost: String?
    private var transfers: [Int: BoundedTransfer] = [:]

    init(proxy: HttpProxy?, tlsHost: String?) { self.proxy = proxy; self.tlsHost = tlsHost }

    func register(_ transfer: BoundedTransfer, for task: URLSessionTask) {
        lock.lock(); defer { lock.unlock() }
        transfers[task.taskIdentifier] = transfer
    }

    private func transfer(_ task: URLSessionTask, removing: Bool = false) -> BoundedTransfer? {
        lock.lock(); defer { lock.unlock() }
        return removing ? transfers.removeValue(forKey: task.taskIdentifier) : transfers[task.taskIdentifier]
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let transfer = transfer(dataTask) else { completionHandler(.cancel); return }
        transfer.urlSession(session, dataTask: dataTask, didReceive: response, completionHandler: completionHandler)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        transfer(dataTask)?.urlSession(session, dataTask: dataTask, didReceive: data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        transfer(task, removing: true)?.urlSession(session, task: task, didCompleteWithError: error)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        lock.lock()
        let pending = Array(transfers.values)
        transfers.removeAll()
        lock.unlock()
        for transfer in pending { transfer.finish(.failure(error ?? URLError(.networkConnectionLost))) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let space = challenge.protectionSpace
        if space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let tlsHost {
            guard let trust = space.serverTrust else {
                transfer(task)?.finish(.failure(URLError(.serverCertificateUntrusted)))
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }
            SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, tlsHost as CFString))
            if SecTrustEvaluateWithError(trust, nil) { completionHandler(.useCredential, URLCredential(trust: trust)) }
            else {
                transfer(task)?.finish(.failure(URLError(.serverCertificateUntrusted)))
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
        } else if space.isProxy(), let proxy, space.host.caseInsensitiveCompare(proxy.host) == .orderedSame,
                  space.port == proxy.port, let user = proxy.username, let password = proxy.password {
            if challenge.previousFailureCount == 0 {
                completionHandler(.useCredential, URLCredential(user: user, password: password, persistence: .forSession))
            } else {
                transfer(task)?.finish(.failure(URLError(.userAuthenticationRequired)))
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
        } else { completionHandler(.performDefaultHandling, nil) }
    }
}
