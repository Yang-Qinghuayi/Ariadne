import AppKit
import AriadneCore
import SwiftUI

struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = .active
    }
}

struct LauncherView: View {
    @ObservedObject var viewModel: LauncherViewModel
    @ObservedObject var settingsStore: AppSettingsStore
    let onSearchFieldReady: (NSTextField) -> Void

    @State private var hoveredProjectID: String?
    @State private var lastTappedProjectID: String?
    @State private var lastTapTime: Date = .distantPast

    var body: some View {
        ZStack {
            VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)

            VStack(spacing: 0) {
                searchHeader

                Divider()
                    .opacity(0.45)

                if let errorMessage = viewModel.errorMessage {
                    errorBanner(errorMessage)
                }

                if let toast = viewModel.statusToast {
                    toastBanner(toast)
                }

                if viewModel.showingActionMenu, let project = viewModel.selectedProject {
                    actionMenuView(for: project)
                } else {
                    resultsArea
                }

                Divider()
                    .opacity(0.45)

                footerBar
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
        )
        .frame(width: 680)
    }

    // MARK: - Search Header

    private var searchHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(.secondary)

            SearchFieldRepresentable(
                text: $viewModel.query,
                placeholder: "Search VS Code projects…",
                onFieldReady: onSearchFieldReady,
                onMoveUp: { viewModel.moveSelectionUp() },
                onMoveDown: { viewModel.moveSelectionDown() },
                onSubmit: { cmd, opt in
                    viewModel.triggerReturn(commandPressed: cmd, optionPressed: opt)
                },
                onEscape: { viewModel.handleEscape() },
                onToggleActions: { viewModel.toggleActionMenu() }
            )
            .frame(height: 28)

            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            if !viewModel.query.isEmpty {
                Button {
                    viewModel.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            } else {
                Text(settingsStore.hotKey.displayString)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.07))
                    )
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 58)
    }

    // MARK: - Banners

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 12))
                .lineLimit(2)
            Spacer()
            Button("Open Settings") {
                viewModel.onOpenSettings?()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Button {
                viewModel.errorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Color.orange.opacity(0.14))
    }

    private func toastBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(Color.green.opacity(0.12))
    }

    // MARK: - Results List

    @ViewBuilder
    private var resultsArea: some View {
        if viewModel.filteredProjects.isEmpty {
            emptyStateView
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(Array(viewModel.filteredProjects.enumerated()), id: \.element.id) { index, item in
                            ProjectRowView(
                                scored: item,
                                index: index,
                                isSelected: index == viewModel.selectedIndex,
                                isHovered: hoveredProjectID == item.id,
                                onOpenVSCode: {
                                    viewModel.execute(action: .vscode, on: item.project)
                                },
                                onOpenKitty: {
                                    viewModel.execute(action: .kitty, on: item.project)
                                },
                                onOpenBoth: {
                                    viewModel.execute(action: .both, on: item.project)
                                },
                                onTogglePin: {
                                    settingsStore.togglePin(for: item.project.path)
                                }
                            )
                            .id(item.id)
                            .onHover { hovering in
                                hoveredProjectID = hovering ? item.id : (hoveredProjectID == item.id ? nil : hoveredProjectID)
                            }
                            .onTapGesture {
                                handleRowTap(index: index, project: item.project)
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
                .frame(height: listHeight)
                .onChange(of: viewModel.selectedIndex) { newIndex in
                    guard viewModel.filteredProjects.indices.contains(newIndex) else { return }
                    let targetID = viewModel.filteredProjects[newIndex].id
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(targetID, anchor: .center)
                    }
                }
            }
        }
    }

    private var listHeight: CGFloat {
        let count = viewModel.filteredProjects.count
        let visibleRows = min(max(count, 1), 7)
        let rowHeight: CGFloat = 58
        let verticalPadding: CGFloat = 16
        return CGFloat(visibleRows) * rowHeight + verticalPadding
    }

    private var emptyStateView: some View {
        VStack(spacing: 10) {
            if viewModel.isLoading {
                ProgressView()
                Text("Loading VS Code projects…")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            } else if !viewModel.query.isEmpty {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 24))
                    .foregroundStyle(.tertiary)
                Text("No projects matching \"\(viewModel.query)\"")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "folder.badge.questionmark")
                    .font(.system(size: 26))
                    .foregroundStyle(.tertiary)
                Text("No VS Code projects discovered yet")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button("Refresh") {
                        viewModel.refreshProjects()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Configure Sources…") {
                        viewModel.onOpenSettings?()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 130)
    }

    // MARK: - Action Menu (Tab / ⌘K)

    private func actionMenuView(for project: Project) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: project.kind == .workspace ? "square.stack.3d.up.fill" : "folder.fill")
                    .foregroundStyle(Color.accentColor)
                Text("Actions for \(project.name)")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("Tab / Esc to return")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.04))

            Divider().opacity(0.35)

            VStack(spacing: 4) {
                ForEach(Array(viewModel.availableMenuActions.enumerated()), id: \.element.id) { index, action in
                    let isSelected = index == viewModel.actionMenuIndex
                    Button {
                        viewModel.showingActionMenu = false
                        viewModel.execute(action: action, on: project)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: iconName(for: action))
                                .frame(width: 18)
                                .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                            Text(action.title)
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            if let shortcutHint = shortcutHint(for: action) {
                                KeyCapView(text: shortcutHint)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isSelected ? Color.accentColor.opacity(0.24) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
        }
    }

    // MARK: - Footer Bar

    private var footerBar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 8) {
                Text("\(viewModel.filteredProjects.count) projects")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Button {
                    viewModel.refreshProjects()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Refresh projects (⌘R)")

                Button {
                    viewModel.onOpenSettings?()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 11))
                        Text("Settings")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Open Settings (⌘,)")
            }

            Spacer()

            HStack(spacing: 12) {
                ShortcutLegend(keys: "⏎", label: settingsStore.defaultEnterAction.actionType.shortLabel)
                ShortcutLegend(keys: "⌘⏎", label: settingsStore.defaultEnterAction.commandReturnActionType.shortLabel)
                ShortcutLegend(keys: "⌥⏎", label: "Both")
                ShortcutLegend(keys: "⌘P", label: "Pin")
                ShortcutLegend(keys: "Tab", label: "Actions")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 36)
        .background(Color.primary.opacity(0.03))
    }

    private func handleRowTap(index: Int, project: Project) {
        let now = Date()
        let isDoubleTap = lastTappedProjectID == project.id && now.timeIntervalSince(lastTapTime) < 0.35
        lastTappedProjectID = project.id
        lastTapTime = now
        viewModel.selectedIndex = index
        if isDoubleTap {
            viewModel.execute(action: settingsStore.defaultEnterAction.actionType, on: project)
        }
    }

    private func iconName(for action: OpenActionType) -> String {
        switch action {
        case .vscode:
            return "chevron.left.forwardslash.chevron.right"
        case .kitty:
            return "terminal.fill"
        case .both:
            return "rectangle.split.2x1.fill"
        case .revealInFinder:
            return "folder"
        case .copyPath:
            return "doc.on.doc"
        }
    }

    private func shortcutHint(for action: OpenActionType) -> String? {
        if action == settingsStore.defaultEnterAction.actionType {
            return "⏎"
        }
        if action == settingsStore.defaultEnterAction.commandReturnActionType {
            return "⌘⏎"
        }
        if action == .both {
            return "⌥⏎"
        }
        return nil
    }
}

// MARK: - Project Row

private struct ProjectRowView: View {
    let scored: ScoredProject
    let index: Int
    let isSelected: Bool
    let isHovered: Bool
    let onOpenVSCode: () -> Void
    let onOpenKitty: () -> Void
    let onOpenBoth: () -> Void
    let onTogglePin: () -> Void

    private var project: Project { scored.project }

    var body: some View {
        HStack(spacing: 12) {
            projectIcon

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(highlightedName)
                        .lineLimit(1)

                    if project.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                    }

                    if project.kind == .workspace {
                        Text("Workspace")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.indigo)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                Capsule()
                                    .fill(Color.indigo.opacity(0.14))
                            )
                    }

                    if let branch = project.gitBranch, !branch.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 9))
                            Text(branch)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .lineLimit(1)
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(
                            Capsule()
                                .fill(Color.primary.opacity(0.07))
                        )
                    }
                }

                Text(project.displayPath)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            if isSelected || isHovered {
                HStack(spacing: 5) {
                    RowActionButton(
                        icon: "chevron.left.forwardslash.chevron.right",
                        label: "VS Code",
                        tint: .blue,
                        action: onOpenVSCode
                    )
                    .help("Open in VS Code")

                    RowActionButton(
                        icon: "terminal.fill",
                        label: "Kitty",
                        tint: .purple,
                        action: onOpenKitty
                    )
                    .help("Open directory in Kitty (⌘⏎)")

                    RowActionButton(
                        icon: "rectangle.split.2x1.fill",
                        label: nil,
                        tint: .teal,
                        action: onOpenBoth
                    )
                    .help("Open in both VS Code & Kitty (⌥⏎)")

                    Button(action: onTogglePin) {
                        Image(systemName: project.isPinned ? "pin.slash" : "pin")
                            .font(.system(size: 11))
                            .foregroundStyle(project.isPinned ? Color.orange : Color.secondary)
                            .frame(width: 24, height: 24)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.primary.opacity(0.06))
                            )
                    }
                    .buttonStyle(.plain)
                    .help(project.isPinned ? "Unpin project (⌘P)" : "Pin project (⌘P)")
                }
            } else if index < 9 {
                Text("⌘\(index + 1)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 54)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.42) : Color.clear, lineWidth: 1)
        )
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.18)
        }
        if isHovered {
            return Color.primary.opacity(0.05)
        }
        return Color.clear
    }

    private var projectIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: project.kind == .workspace
                            ? [Color.indigo.opacity(0.85), Color.purple.opacity(0.75)]
                            : [Color.blue.opacity(0.85), Color.cyan.opacity(0.75)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 34, height: 34)

            Image(systemName: project.kind == .workspace ? "square.stack.3d.up.fill" : "folder.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    private var highlightedName: AttributedString {
        let chars = Array(project.name)
        var result = AttributedString()
        var idx = 0

        while idx < chars.count {
            let isMatched = scored.matchedNameIndices.contains(idx)
            var end = idx + 1
            while end < chars.count && scored.matchedNameIndices.contains(end) == isMatched {
                end += 1
            }

            var segment = AttributedString(String(chars[idx..<end]))
            if isMatched {
                segment.foregroundColor = .accentColor
                segment.font = .system(size: 14, weight: .bold)
            } else {
                segment.font = .system(size: 14, weight: .medium)
            }
            result.append(segment)
            idx = end
        }

        return result
    }
}

private struct RowActionButton: View {
    let icon: String
    let label: String?
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                if let label {
                    Text(label)
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .foregroundStyle(tint)
            .padding(.horizontal, label == nil ? 7 : 8)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(tint.opacity(0.14))
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ShortcutLegend: View {
    let keys: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            KeyCapView(text: keys)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}

private struct KeyCapView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
            )
    }
}
