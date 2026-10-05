import ExtensionFoundation
import ExtensionKit
import SwiftUI

struct SpikeConfiguration<E: SpikeUIExtension>: AppExtensionConfiguration {
    let appExtension: E
    init(_ appExtension: E) { self.appExtension = appExtension }
    func accept(connection: NSXPCConnection) -> Bool {
        NSLog("[ext] accept(connection:) called")
        HostLink.shared.attach(connection)
        return true
    }
}

protocol SpikeUIExtension: AppExtension {
    associatedtype Body: SpikeScene
    var body: Body { get }
}

protocol SpikeScene: AppExtensionScene {}

struct SpikeExtensionScene<Content: View>: SpikeScene {
    let sceneID = "main"
    private let content: () -> Content
    init(content: @escaping () -> Content) { self.content = content }

    var body: some AppExtensionScene {
        PrimitiveAppExtensionScene(id: sceneID) {
            content()
        } onConnection: { connection in
            NSLog("[ext] scene onConnection called")
            HostLink.shared.attach(connection)
            return true
        }
    }
}

extension SpikeUIExtension {
    var configuration: AppExtensionSceneConfiguration {
        AppExtensionSceneConfiguration(self.body, configuration: SpikeConfiguration(self))
    }
}

@main
final class JarvisUIExtension: SpikeUIExtension {
    required init() {
        _ = AuthHelper.shared
        HostLink.shared.report("ext-init pid \(getpid())")
    }

    @AppExtensionPoint.Bind
    var boundExtensionPoint: AppExtensionPoint {
        AppExtensionPoint.Identifier(host: "dev.de0ch.shellspike", name: "jarvisUI")
    }

    var body: some SpikeScene {
        SpikeExtensionScene {
            RNContainer().ignoresSafeArea()
        }
    }
}

/// The extension's side of the XPC link to the shell. React Native reaches it through
/// SpikeBridge (ObjC) → NotificationCenter, so no Swift/ObjC bridging header is needed.
final class HostLink: NSObject {
    static let shared = HostLink()
    private var connection: NSXPCConnection?
    private var pending: [(String, String)] = []

    override init() {
        super.init()
        NotificationCenter.default.addObserver(forName: Notification.Name("SpikeHostCall"), object: nil, queue: .main) { [weak self] n in
            let method = n.userInfo?["method"] as? String ?? ""
            let arg = n.userInfo?["arg"] as? String ?? ""
            self?.call(method, arg)
        }
    }

    func attach(_ c: NSXPCConnection) {
        NSLog("[ext] attach connection %@", String(describing: c))
        c.remoteObjectInterface = NSXPCInterface(with: HostService.self)
        c.exportedInterface = NSXPCInterface(with: ExtensionService.self)
        c.exportedObject = ExtensionServiceImpl()
        c.invalidationHandler = { NSLog("[ext] connection invalidated") }
        c.interruptionHandler = { NSLog("[ext] connection interrupted") }
        c.resume()
        connection = c
        let queued = pending
        pending = []
        for (m, a) in queued { call(m, a) }
        report("xpc attached in extension")
    }

    func report(_ s: String) { call("report", s) }

    func call(_ method: String, _ arg: String) {
        guard let c = connection else { NSLog("[ext] queued %@ (no connection yet)", method); pending.append((method, arg)); return }
        NSLog("[ext] call %@ %@", method, arg)
        let proxy = c.remoteObjectProxyWithErrorHandler { e in NSLog("[ext] xpc error %@", String(describing: e)) } as? HostService
        if method == "secure" { proxy?.requestSecureMode(arg) } else { proxy?.report(arg) }
    }
}

final class ExtensionServiceImpl: NSObject, ExtensionService {
    func hello(_ reply: @escaping (String) -> Void) { reply("hello from extension pid \(getpid())") }
}
