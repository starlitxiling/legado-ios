import Foundation

public struct ReturnData<Value: Encodable>: Encodable {
    public let isSuccess: Bool
    public let errorMsg: String
    public let data: Value?

    public init(data: Value) {
        isSuccess = true; errorMsg = ""; self.data = data
    }

    public init(errorMsg: String = "未知错误,请联系开发者!") {
        isSuccess = false; self.errorMsg = errorMsg; data = nil
    }
}
