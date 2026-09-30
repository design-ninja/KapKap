import AppKit
import ScreenCaptureKit

enum CapturePermissions {
    static func isDenied(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == SCStreamErrorDomain && error.code == SCStreamError.Code.userDeclined.rawValue
    }
}
