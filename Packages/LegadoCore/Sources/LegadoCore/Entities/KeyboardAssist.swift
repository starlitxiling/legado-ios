import Foundation
import GRDB

public struct KeyboardAssist: StorageRow {
    public static let databaseTableName = "keyboardAssists"
    public var type: Int = 0
    public var key: String = ""
    public var value: String = ""
    public var serialNo: Int = 0

    public init() {}

    public init(row: Row) {
        type = row["type"]
        key = row["key"]
        value = row["value"]
        serialNo = row["serialNo"]
    }

    private enum CodingKeys: String, CodingKey {
        case type, key, value, serialNo
    }

    public init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.gsonInt(forKey: .type) ?? type
        key = try container.gsonString(forKey: .key) ?? key
        value = try container.gsonString(forKey: .value) ?? value
        serialNo = try container.gsonInt(forKey: .serialNo) ?? serialNo
    }
}

public typealias KeyboardAssistRepository = Repository<KeyboardAssist>


extension KeyboardAssist {
    static func seedIfEmpty(_ db: Database) throws {
        guard try fetchCount(db) == 0 else { return }
        let values = try GsonJSONDecoder().decode([KeyboardAssist].self, from: Data(defaultJSON.utf8))
        for var value in values { try value.insert(db) }
    }

    // Kotlin cb664b84d: assets/defaultData/keyboardAssists.json。
    private static let defaultJSON = #"""
[
  {
    "key": "@css:",
    "value": "@css:",
    "serialNo": 0
  },
  {
    "key": "<js>",
    "value": "<js></js>",
    "serialNo": 1
  },
  {
    "key": "{{}}",
    "value": "{{}}",
    "serialNo": 2
  },
  {
    "key": "##",
    "value": "##",
    "serialNo": 3
  },
  {
    "key": "&&",
    "value": "&&",
    "serialNo": 4
  },
  {
    "key": "%%",
    "value": "%%",
    "serialNo": 5
  },
  {
    "key": "||",
    "value": "||",
    "serialNo": 6
  },
  {
    "key": "//",
    "value": "//",
    "serialNo": 7
  },
  {
    "key": "\\",
    "value": "\\",
    "serialNo": 8
  },
  {
    "key": "$.",
    "value": "$.",
    "serialNo": 9
  },
  {
    "key": "@",
    "value": "@",
    "serialNo": 10
  },
  {
    "key": ":",
    "value": ":",
    "serialNo": 11
  },
  {
    "key": "class",
    "value": "class",
    "serialNo": 12
  },
  {
    "key": "text",
    "value": "text",
    "serialNo": 13
  },
  {
    "key": "href",
    "value": "href",
    "serialNo": 14
  },
  {
    "key": "textNodes",
    "value": "textNodes",
    "serialNo": 15
  },
  {
    "key": "ownText",
    "value": "ownText",
    "serialNo": 16
  },
  {
    "key": "all",
    "value": "all",
    "serialNo": 17
  },
  {
    "key": "html",
    "value": "html",
    "serialNo": 18
  },
  {
    "key": "[",
    "value": "[",
    "serialNo": 19
  },
  {
    "key": "]",
    "value": "]",
    "serialNo": 20
  },
  {
    "key": "<",
    "value": "<",
    "serialNo": 21
  },
  {
    "key": ">",
    "value": ">",
    "serialNo": 22
  },
  {
    "key": "#",
    "value": "#",
    "serialNo": 23
  },
  {
    "key": "!",
    "value": "!",
    "serialNo": 24
  },
  {
    "key": ".",
    "value": ".",
    "serialNo": 25
  },
  {
    "key": "+",
    "value": "+",
    "serialNo": 26
  },
  {
    "key": "-",
    "value": "-",
    "serialNo": 27
  },
  {
    "key": "*",
    "value": "*",
    "serialNo": 28
  },
  {
    "key": "/",
    "value": "/",
    "serialNo": 29
  },
  {
    "key": "=",
    "value": "=",
    "serialNo": 30
  },
  {
    "key": "useWebView",
    "value": ",{\"webView\": true}",
    "serialNo": 31
  }
]
"""#
}
