import ExtensionFoundation
import ExtensionKit
import SwiftUI

extension AppExtensionPoint {
    @Definition
    public static var jarvisUI: AppExtensionPoint {
        Name("jarvisUI")
        UserInterface()
    }
}

@main
struct HostApp: App {
    var body: some Scene { WindowGroup { RootView() } }
}

enum Mode { case normal, secure }

/// The trusted shell's state. Only code in this process changes `mode` back to .normal.
@Observable
final class Shell {
    var mode: Mode = .normal
    var secureOptions = ""
    var identity: AppExtensionIdentity?
    var lines: [String] = []
    private var monitor: AppExtensionPoint.Monitor?
    private let t0 = Date()

    func log(_ s: String) {
        let line = String(format: "%.1f ", Date().timeIntervalSince(t0)) + s
        NSLog("[shell] %@", line)
        lines.append(line)
    }

    func load() async {
        log("host pid \(getpid())")
        do {
            let m = try await AppExtensionPoint.Monitor(appExtensionPoint: .jarvisUI)
            monitor = m
            log("identities \(m.identities.count) disabled \(m.state.disabledCount) unapproved \(m.state.unapprovedCount)")
            identity = m.identities.first
        } catch {
            log("monitor error \(error)")
        }
    }
}

final class HostServiceImpl: NSObject, HostService {
    let shell: Shell
    init(shell: Shell) { self.shell = shell }
    func requestSecureMode(_ options: String) {
        DispatchQueue.main.async { [shell] in
            shell.log("enter secure requested: \(options)")
            shell.secureOptions = options
            shell.mode = .secure
        }
    }
    func report(_ line: String) {
        DispatchQueue.main.async { [shell] in shell.log("ext: " + line) }
    }
}

struct RootView: View {
    @State private var shell = Shell()

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch shell.mode {
                case .normal:
                    if let identity = shell.identity {
                        ExtensionHost(identity: identity, shell: shell)
                            .accessibilityIdentifier("extension-host")
                    } else {
                        Text("No extension").accessibilityIdentifier("no-extension")
                    }
                case .secure:
                    SecureSheet(shell: shell)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Host-owned log strip (test instrumentation): survives the extension dying.
            ScrollView {
                Text(shell.lines.suffix(40).joined(separator: "\n"))
                    .font(.system(size: 9, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("full-log")
                    .accessibilityLabel(shell.lines.joined(separator: "\n"))
            }
            .frame(height: 150)
            .background(Color.yellow.opacity(0.2))
        }
        .task { await shell.load() }
    }
}

struct SecureSheet: View {
    let shell: Shell
    @State private var store = "low"
    var body: some View {
        VStack(spacing: 24) {
            Text("SECURE MODE (native shell)").font(.title2).bold().accessibilityIdentifier("secure-title")
            Text("requested options: \(shell.secureOptions)").font(.caption).accessibilityIdentifier("secure-options")
            Picker("Store", selection: $store) {
                Text("low").tag("low")
                Text("high").tag("high")
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("secure-store")
            Button("Done (shell exits secure mode)") {
                shell.log("shell exits secure mode, store=\(store)")
                shell.mode = .normal
            }
            .accessibilityIdentifier("secure-done")
            Text("host pid \(getpid())").font(.caption)
        }
        .padding()
    }
}

struct ExtensionHost: UIViewControllerRepresentable {
    let identity: AppExtensionIdentity
    let shell: Shell

    func makeCoordinator() -> Coordinator { Coordinator(shell: shell) }

    func makeUIViewController(context: Context) -> EXHostViewController {
        let vc = EXHostViewController()
        vc.delegate = context.coordinator
        vc.configuration = EXHostViewController.Configuration(appExtension: identity, sceneID: "main")
        shell.log("host view created")
        return vc
    }

    func updateUIViewController(_ vc: EXHostViewController, context: Context) {}

    final class Coordinator: NSObject, EXHostViewControllerDelegate {
        let shell: Shell
        var connection: NSXPCConnection?
        init(shell: Shell) { self.shell = shell }

        func hostViewControllerDidActivate(_ viewController: EXHostViewController) {
            shell.log("extension activated")
            do {
                let c = try viewController.makeXPCConnection()
                c.exportedInterface = NSXPCInterface(with: HostService.self)
                c.exportedObject = HostServiceImpl(shell: shell)
                c.invalidationHandler = { [shell] in DispatchQueue.main.async { shell.log("xpc invalidated") } }
                c.interruptionHandler = { [shell] in DispatchQueue.main.async { shell.log("xpc interrupted (extension died?)") } }
                c.resume()
                connection = c
                shell.log("xpc up")
            } catch {
                shell.log("xpc error \(error)")
            }
        }

        func hostViewControllerWillDeactivate(_ viewController: EXHostViewController, error: (any Error)?) {
            shell.log("extension deactivating \(error.map { String(describing: $0) } ?? "")")
        }
    }
}
