import AriadneCore
import Combine
import Foundation

@MainActor
final class LauncherViewModel: ObservableObject {
    @Published var query: String = "" {
        didSet {
            selectedIndex = 0
            recomputeFilter()
        }
    }

    @Published private(set) var allProjects: [Project] = []
    @Published private(set) var filteredProjects: [ScoredProject] = []
    @Published var selectedIndex: Int = 0
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var statusToast: String?
    @Published var showingActionMenu: Bool = false
    @Published var actionMenuIndex: Int = 0

    let settingsStore: AppSettingsStore
    private let loader: VSCodeProjectLoader
    private let launcher: ProjectLauncher

    var onDismiss: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    private var cancellables: Set<AnyCancellable> = []
    private var refreshTask: Task<Void, Never>?
    private var toastDismissTask: Task<Void, Never>?

    let availableMenuActions: [OpenActionType] = [
        .vscode,
        .kitty,
        .both,
        .revealInFinder,
        .copyPath
    ]

    init(
        settingsStore: AppSettingsStore,
        loader: VSCodeProjectLoader = VSCodeProjectLoader(),
        launcher: ProjectLauncher = ProjectLauncher()
    ) {
        self.settingsStore = settingsStore
        self.loader = loader
        self.launcher = launcher

        settingsStore.$includeVSCode
            .combineLatest(
                settingsStore.$includeVSCodeInsiders,
                settingsStore.$includeProjectManager,
                settingsStore.$hideMissingProjects
            )
            .dropFirst()
            .sink { [weak self] _ in
                self?.refreshProjects()
            }
            .store(in: &cancellables)

        settingsStore.$customScanDirectories
            .dropFirst()
            .sink { [weak self] _ in
                self?.refreshProjects()
            }
            .store(in: &cancellables)

        settingsStore.$pinnedPaths
            .dropFirst()
            .sink { [weak self] _ in
                self?.refreshProjects()
            }
            .store(in: &cancellables)
    }

    var selectedProject: Project? {
        guard filteredProjects.indices.contains(selectedIndex) else {
            return nil
        }
        return filteredProjects[selectedIndex].project
    }

    func prepareForDisplay() {
        errorMessage = nil
        statusToast = nil
        showingActionMenu = false
        actionMenuIndex = 0
        query = ""
        selectedIndex = 0
        refreshProjects()
    }

    func refreshProjects() {
        refreshTask?.cancel()
        let config = settingsStore.discoveryConfig
        let loaderRef = loader
        isLoading = true

        refreshTask = Task.detached(priority: .userInitiated) { [weak self] in
            let loaded = loaderRef.loadProjects(config: config)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                self.allProjects = loaded
                self.isLoading = false
                self.recomputeFilter()
            }
        }
    }

    func moveSelectionDown() {
        if showingActionMenu {
            if !availableMenuActions.isEmpty {
                actionMenuIndex = min(actionMenuIndex + 1, availableMenuActions.count - 1)
            }
            return
        }
        guard !filteredProjects.isEmpty else { return }
        selectedIndex = min(selectedIndex + 1, filteredProjects.count - 1)
    }

    func moveSelectionUp() {
        if showingActionMenu {
            actionMenuIndex = max(actionMenuIndex - 1, 0)
            return
        }
        guard !filteredProjects.isEmpty else { return }
        selectedIndex = max(selectedIndex - 1, 0)
    }

    func toggleActionMenu() {
        guard selectedProject != nil else { return }
        showingActionMenu.toggle()
        actionMenuIndex = 0
    }

    func handleEscape() {
        if showingActionMenu {
            showingActionMenu = false
            return
        }
        onDismiss?()
    }

    func triggerReturn(commandPressed: Bool, optionPressed: Bool) {
        if showingActionMenu, let project = selectedProject {
            let action = availableMenuActions[actionMenuIndex]
            showingActionMenu = false
            execute(action: action, on: project)
            return
        }

        guard let project = selectedProject else { return }
        let action: OpenActionType
        if optionPressed {
            action = .both
        } else if commandPressed {
            action = settingsStore.defaultEnterAction.commandReturnActionType
        } else {
            action = settingsStore.defaultEnterAction.actionType
        }
        execute(action: action, on: project)
    }

    func triggerQuickIndex(_ index: Int) {
        guard filteredProjects.indices.contains(index) else { return }
        selectedIndex = index
        execute(action: settingsStore.defaultEnterAction.actionType, on: filteredProjects[index].project)
    }

    func togglePinSelected() {
        guard let project = selectedProject else { return }
        settingsStore.togglePin(for: project.path)
        let message = project.isPinned ? "Unpinned \(project.name)" : "Pinned \(project.name)"
        showToast(message)
    }

    func execute(action: OpenActionType, on project: Project) {
        errorMessage = nil

        if action == .copyPath {
            launcher.copyPathToPasteboard(project: project)
            showToast("Copied path: \(project.displayPath)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                self?.onDismiss?()
            }
            return
        }

        if action == .revealInFinder {
            launcher.revealInFinder(project: project)
            onDismiss?()
            return
        }

        settingsStore.recordOpened(projectPath: project.path)

        let customVSCode = settingsStore.customVSCodePath
        let customKitty = settingsStore.customKittyPath
        let kittyMode = settingsStore.kittyLaunchMode
        let remoteSocket = settingsStore.kittyRemoteSocket

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.launcher.perform(
                    action: action,
                    on: project,
                    customVSCodePath: customVSCode,
                    customKittyPath: customKitty,
                    kittyMode: kittyMode,
                    kittyRemoteSocket: remoteSocket
                )
                self.onDismiss?()
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    private func recomputeFilter() {
        let scored = FuzzyMatcher.filterAndSort(projects: allProjects, query: query)
        filteredProjects = scored
        if scored.isEmpty {
            selectedIndex = 0
            showingActionMenu = false
        } else {
            selectedIndex = min(selectedIndex, scored.count - 1)
        }
    }

    private func showToast(_ text: String) {
        toastDismissTask?.cancel()
        statusToast = text
        toastDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard !Task.isCancelled else { return }
            self?.statusToast = nil
        }
    }
}
