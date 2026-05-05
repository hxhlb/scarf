import Foundation
import os
import Observation
import ScarfCore

/// State + commit logic for the "New Project from Scratch" wizard.
/// Drives `NewProjectSheet`. Hosts the form fields, derives a default
/// slug from the project name, validates inputs, and runs the
/// `ProjectScaffolder` on commit.
///
/// Pattern matches `TemplateConfigViewModel`: a tightly-scoped view
/// model that owns its sheet's state, exposes typed bindings, and
/// surfaces a single error string the sheet renders inline.
@Observable
@MainActor
final class NewProjectViewModel {
    private let logger = Logger(subsystem: "com.scarf", category: "NewProjectViewModel")
    private let context: ServerContext

    // MARK: - Form fields

    var projectName: String = "" {
        didSet {
            // Auto-derive slug from name as long as the user hasn't
            // edited the slug field manually. Once they edit it, we
            // stop tracking — the user's choice wins.
            if !slugManuallyEdited {
                folderName = ProjectScaffolder.suggestedSlug(from: projectName)
            }
        }
    }

    var folderName: String = "" {
        didSet {
            // Mark manually edited only if the change isn't from our
            // own auto-derivation. The didSet on projectName sets
            // folderName too — we differentiate by checking whether
            // the new value matches what suggestedSlug would produce.
            if folderName != ProjectScaffolder.suggestedSlug(from: projectName) {
                slugManuallyEdited = true
            }
        }
    }

    var parentDirectory: String = ""

    var description: String = ""

    /// User-facing error from the most recent commit attempt. Cleared
    /// when the user edits any field. Sheet renders this as an inline
    /// banner above the footer.
    var errorMessage: String?

    // MARK: - Internal state

    /// Tracks whether the user has typed in the folder-name field.
    /// Once true, we stop overriding their value when they edit the
    /// project name.
    private var slugManuallyEdited: Bool = false

    /// True while a commit is in flight. Disables the Create button
    /// to prevent double-taps.
    private(set) var isCommitting: Bool = false

    init(context: ServerContext) {
        self.context = context
        self.parentDirectory = Self.defaultParentDirectory()
    }

    // MARK: - Validation

    var canCommit: Bool {
        guard !isCommitting else { return false }
        guard !projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        guard ProjectScaffolder.isValidSlug(folderName) else { return false }
        guard !parentDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return true
    }

    /// Resolved absolute path the project will land at — shown as a
    /// preview line above the footer so the user sees exactly what
    /// gets created.
    var resolvedProjectPath: String {
        let parent = ProjectScaffolder.normalizeDirectoryPath(parentDirectory)
        return parent + "/" + folderName
    }

    // MARK: - Commit

    /// Attempt to scaffold the project. Returns the registered
    /// `ProjectEntry` on success, nil on validation/scaffolder
    /// failure (with `errorMessage` populated for the sheet).
    func commit() -> ProjectEntry? {
        guard canCommit else {
            errorMessage = "Fill in the name, folder, and parent directory."
            return nil
        }
        isCommitting = true
        defer { isCommitting = false }
        errorMessage = nil

        let scaffolder = ProjectScaffolder(context: context)
        do {
            let entry = try scaffolder.scaffold(
                name: projectName.trimmingCharacters(in: .whitespacesAndNewlines),
                slug: folderName,
                parentDir: parentDirectory,
                description: description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil
                    : description.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            logger.info("scaffolded \(entry.name, privacy: .public) at \(entry.path, privacy: .public)")
            return entry
        } catch {
            errorMessage = error.localizedDescription
            logger.warning("scaffold failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Build the auto-prompt the wizard hands to ChatViewModel after
    /// scaffolding. Mentions the absolute path so the agent has the
    /// project's location even if the chat session's cwd slot ever
    /// drifts; appends the user's optional description so the agent
    /// can tailor its first question.
    func buildInitialPrompt(for entry: ProjectEntry) -> String {
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        var prompt = "I just created a new Scarf project at \(entry.path). "
            + "Use the `scarf-template-author` skill to walk me through configuring it — "
            + "design the dashboard, optionally schedule cron jobs, and write AGENTS.md instructions."
        if !trimmedDescription.isEmpty {
            prompt += " Here's what it's for: \(trimmedDescription)"
        }
        return prompt
    }

    // MARK: - Defaults

    /// Default parent directory for new projects: `~/Projects` if it
    /// exists, else `~`. Matches Scarf's convention of preferring the
    /// user's `~/Projects` folder when available without forcing it.
    private static func defaultParentDirectory() -> String {
        let home = NSHomeDirectory()
        let projectsDir = home + "/Projects"
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: projectsDir, isDirectory: &isDir),
           isDir.boolValue {
            return projectsDir
        }
        return home
    }
}
