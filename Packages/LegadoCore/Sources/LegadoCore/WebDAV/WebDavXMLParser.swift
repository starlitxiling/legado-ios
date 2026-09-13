import Foundation

public enum WebDavXMLParser {
    public static func parse(_ data: Data, relativeTo url: URL) throws -> [WebDavFile] {
        guard !String(decoding: data, as: UTF8.self).uppercased().contains("<!DOCTYPE") else { throw WebDavError.invalidXML }
        let delegate = MultistatusDelegate(baseURL: url)
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), delegate.isMultistatus else { throw WebDavError.invalidXML }
        return delegate.files
    }
}

private final class MultistatusDelegate: NSObject, XMLParserDelegate {
    let baseURL: URL
    var files: [WebDavFile] = []
    var isMultistatus = false
    private var stack: [(name: String, namespace: String?, text: String)] = []
    private var href = ""
    private var properties: [String: String] = [:]
    private var pending: [String: String] = [:]
    private var propStatus = ""
    private var responseStatus = ""
    private var inResponse = false
    private var inPropstat = false

    init(baseURL: URL) { self.baseURL = baseURL }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        if stack.isEmpty { isMultistatus = elementName == "multistatus" && namespaceURI == "DAV:" }
        stack.append((elementName, namespaceURI, ""))
        guard namespaceURI == "DAV:" else { return }
        switch elementName {
        case "response":
            inResponse = true; href = ""; properties = [:]; responseStatus = ""
        case "propstat":
            inPropstat = true; pending = [:]; propStatus = ""
        case "collection" where inPropstat:
            pending["collection"] = "true"
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if !stack.isEmpty { stack[stack.count - 1].text += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard let node = stack.popLast(), namespaceURI == "DAV:" else { return }
        let value = node.text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "href" where inResponse: href = value
        case "status":
            if inPropstat { propStatus = value } else { responseStatus = value }
        case "propstat":
            if successful(propStatus) { properties.merge(pending) { _, new in new } }
            inPropstat = false
        case "response":
            if responseStatus.isEmpty || successful(responseStatus) { appendFile() }
            inResponse = false
        case "displayname", "getcontentlength", "getcontenttype", "getlastmodified", "resourcetype":
            if inPropstat { pending[elementName] = value }
        default: break
        }
    }

    private func successful(_ status: String) -> Bool {
        let parts = status.split(separator: " ")
        guard parts.count >= 2, let code = Int(parts[1]) else { return false }
        return (200..<300).contains(code)
    }

    private func appendFile() {
        guard !href.isEmpty, !properties.isEmpty,
              var url = URL(string: href, relativeTo: baseURL)?.absoluteURL else { return }
        let isDirectory = properties["collection"] == "true" || properties["getcontenttype"] == "httpd/unix-directory"
        if isDirectory && !url.hasDirectoryPath { url.appendPathComponent("") }
        let encodedName = properties["displayname"] ?? ""
        let name = encodedName.isEmpty ? url.lastPathComponent : (encodedName.removingPercentEncoding ?? encodedName)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        files.append(WebDavFile(url: url, displayName: name, size: Int64(properties["getcontentlength"] ?? "") ?? 0,
                                isDirectory: isDirectory, lastModified: properties["getlastmodified"].flatMap(formatter.date)))
    }
}
