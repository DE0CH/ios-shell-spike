# ios-shell-spike

Test build for a hardened iOS app structure: a small native Swift **shell** (main process) that hosts the
whole React Native UI inside a bundled **ExtensionKit extension** (separate process, iOS 26+) and can switch
to a **secure mode** where it removes the extension's view and shows its own native sheet. Anything may ask to
enter secure mode (over XPC, with options); only the shell's own code leaves it.

CI (`.github/workflows/ios.yml`) builds it on a GitHub macOS runner and runs a UI test on a simulator that
checks: separate process, React Native start time, input across the process boundary, keyboard, a WebView,
XPC both ways, secure mode, background/resume, ASWebAuthenticationSession from the extension, and the
extension's memory limit. Results are screenshots + notes in the `results` artifact.
