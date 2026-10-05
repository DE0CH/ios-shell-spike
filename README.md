# ios-shell-spike

Test build for a hardened iOS app structure: a small native Swift **shell** (main process) that hosts the
whole React Native UI inside a bundled **ExtensionKit extension** (separate process, iOS 26+) and can switch
to a **secure mode** where it removes the extension's view and shows its own native sheet. Anything may ask to
enter secure mode (over XPC, with options); only the shell's own code leaves it.

CI (`.github/workflows/ios.yml`) builds it on a GitHub macOS runner and runs a UI test on a simulator that
checks: separate process, React Native start time, input across the process boundary, keyboard, a WebView,
XPC both ways, secure mode, background/resume, ASWebAuthenticationSession from the extension, and the
extension's memory limit. Results are screenshots + notes in the `results` artifact.

## Results (2026-10-05, GitHub macos-26 runner, Xcode 26.6, iPhone 17 simulator, iOS 26.5, React Native 0.87.1)

| Question | Result |
|---|---|
| Separate process | Yes: shell and extension have different pids |
| React Native inside the extension | Works (New Architecture, Hermes, bundled JS). Cold start on the CI simulator: extension activated 2.3–5.7 s after launch, RN mounted 1.2–3.4 s later |
| Taps and typing across the process boundary | Work (TextInput gets keystrokes, autocorrect included) |
| WebView inside RN inside the extension | Works (react-native-webview, JS runs, postMessage arrives) |
| XPC both ways | Works once the host sends a first message (see pitfalls) |
| Enter secure mode on request from the extension | Works; the shell removes the extension's view (none of its elements remain in the accessibility tree) |
| Only the shell exits secure mode | By construction: the XPC interface has no exit call |
| Extension survives secure mode | Yes: same pid, React Native state kept (counter 1 → 2, not reset) |
| Seamless look | Shell snapshots the live extension view (drawHierarchy captures the remote content), swaps it in without a crossfade, dims it, slides its own sheet up; on exit the snapshot stays over the re-added live view until the extension has drawn — no flash |
| Keyboard | Natively the extension sees the real keyboard frame and a window the shell has shrunk; RN's own `keyboardDidShow` reports height 0, so keyboard avoidance must come from the shell resizing the extension's area |
| ASWebAuthenticationSession from the extension | Works: iOS asks "“Host” Wants to Use … to Sign In", then the sheet loads (shown within the extension's area) |
| Background / resume | Works |
| Memory limit | Not measurable on the simulator (`os_proc_available_memory` = 0); needs a real device |

## Pitfalls hit

- `EX_ENABLE_EXTENSION_POINT_GENERATION = YES` is required, otherwise `AppExtensionPoint.Monitor` fails with "Host is not entitled observe".
- CocoaPods adds no "Embed Pods Frameworks" phase to an ExtensionKit target: the extension dies at launch with "Library not loaded: @rpath/React.framework". Run `Pods-Extension-frameworks.sh` as a post-build script of the extension.
- The extension target needs `-lc++` (React Native's C++ symbols).
- A Swift `@objc protocol` shared by both targets gets a module-prefixed ObjC name in each; give it a fixed one (`@objc(HostService)`).
- XPC connections are lazy: the extension's `PrimitiveAppExtensionScene … onConnection` only fires when the host sends a first message on `makeXPCConnection()`'s connection.
- XCUITest `typeText` can't type into a field in the extension's remote view ("no keyboard focus"); tap `app.keyboards.keys[...]` instead (keys may be upper- or lowercase).
