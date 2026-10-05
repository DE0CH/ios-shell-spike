import Foundation

/// Exported by the host shell over the ExtensionKit XPC connection; called by the extension.
/// Anyone (the untrusted extension included) may ask to ENTER secure mode with options. There is
/// deliberately no call to EXIT it: only the shell's own code leaves secure mode.
@objc(HostService) public protocol HostService {
    func requestSecureMode(_ options: String)
    func report(_ line: String)
}

/// Exported by the extension; the host calls `hello` right after connecting, because an XPC connection
/// only reaches the other side when the first message is sent.
@objc(ExtensionService) public protocol ExtensionService {
    func hello(_ reply: @escaping (String) -> Void)
}
