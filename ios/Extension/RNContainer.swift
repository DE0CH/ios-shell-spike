import React
import React_RCTAppDelegate
import ReactAppDependencyProvider
import SwiftUI
import UIKit

final class RNDelegate: RCTDefaultReactNativeFactoryDelegate {
    override func sourceURL(for bridge: RCTBridge) -> URL? { bundleURL() }
    override func bundleURL() -> URL? { Bundle.main.url(forResource: "main", withExtension: "jsbundle") }
}

/// One React Native instance per extension process; the root view is reused if the scene is rebuilt.
enum RN {
    static let delegate: RNDelegate = {
        let d = RNDelegate()
        d.dependencyProvider = RCTAppDependencyProvider()
        return d
    }()
    static let factory = RCTReactNativeFactory(delegate: delegate)
    static let rootView: UIView = {
        HostLink.shared.report("rn-factory start, bundle=\(Bundle.main.url(forResource: "main", withExtension: "jsbundle") != nil)")
        return factory.rootViewFactory.view(withModuleName: "SpikeApp")
    }()
}

struct RNContainer: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let host = UIView()
        let v = RN.rootView
        v.removeFromSuperview()
        v.frame = host.bounds
        v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.addSubview(v)
        AuthHelper.shared.anchorView = v
        return host
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
