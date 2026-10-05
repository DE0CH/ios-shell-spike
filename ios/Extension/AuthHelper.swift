import AuthenticationServices
import UIKit

/// Tests whether ASWebAuthenticationSession (the pairing sign-in sheet) can be started from inside the extension.
final class AuthHelper: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = AuthHelper()
    weak var anchorView: UIView?
    private var session: ASWebAuthenticationSession?

    override init() {
        super.init()
        NotificationCenter.default.addObserver(forName: Notification.Name("SpikeAuth"), object: nil, queue: .main) { [weak self] _ in self?.start() }
    }

    func start() {
        let s = ASWebAuthenticationSession(url: URL(string: "https://example.com/")!, callbackURLScheme: "spikecb") { url, err in
            HostLink.shared.report("auth done url=\(url?.absoluteString ?? "nil") err=\(err.map { String(describing: $0) } ?? "nil")")
        }
        s.presentationContextProvider = self
        session = s
        let ok = s.start()
        HostLink.shared.report("auth start returned \(ok), anchor window=\(anchorView?.window != nil)")
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchorView?.window ?? ASPresentationAnchor()
    }
}
