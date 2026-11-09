import AppKit

@MainActor enum Uninstaller {
    private static let identifier = "com.anazih.lumapulse"

    static func run(prepare: () -> Void, finish: () -> Void) {
        let bundle = Bundle.main.bundleURL
        guard Bundle.main.bundleIdentifier == identifier,
              bundle.pathExtension == "app",
              bundle.resolvingSymlinksInPath().pathComponents.contains("AppTranslocation") == false else {
            show("LumaPulse could not be removed", "Run LumaPulse from its installed location and try again.")
            return
        }

        let confirmation = NSAlert()
        confirmation.alertStyle = .warning
        confirmation.messageText = "Uninstall LumaPulse?"
        confirmation.informativeText = "This moves this copy of LumaPulse to the Trash and clears its bookmarks, settings, and saved provider credentials for this macOS account."
        confirmation.addButton(withTitle: "Cancel")
        confirmation.addButton(withTitle: "Continue…")
        guard confirmation.runModal() == .alertSecondButtonReturn else { return }

        let parent = bundle.deletingLastPathComponent()
        let panel = NSOpenPanel()
        panel.message = "Select the folder containing this copy of LumaPulse to grant removal access."
        panel.prompt = "Allow Removal"
        panel.directoryURL = parent
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        guard panel.runModal() == .OK, let selected = panel.url else { return }
        do {
            // NSOpenPanel starts security-scoped access for its returned URL.
            defer { selected.stopAccessingSecurityScopedResource() }
            guard matchesInstallFolder(selected, parent) else {
                show("LumaPulse could not be removed", "Select the folder containing this copy of LumaPulse: \(parent.path)")
                return
            }
            try FileManager.default.trashItem(at: bundle, resultingItemURL: nil)
        } catch {
            show("LumaPulse could not be moved to the Trash", error.localizedDescription)
            return
        }

        prepare()
        let credentialsRemoved = ProviderKeychain.removeAll()
        UserDefaults.standard.removePersistentDomain(forName: identifier)
        if !credentialsRemoved {
            show("Some saved credentials could not be removed", "In Keychain Access, remove any LumaPulse provider entries for com.anazih.lumapulse.providers.")
        }
        finish()
    }

    static func matchesInstallFolder(_ selection: URL, _ parent: URL) -> Bool {
        selection.isFileURL && selection.resolvingSymlinksInPath().standardizedFileURL.path
            == parent.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private static func show(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
