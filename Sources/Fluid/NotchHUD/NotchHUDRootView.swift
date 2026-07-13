import Combine
import SwiftUI

/// Observable state shared between the controller (AppKit side) and the SwiftUI view.
@MainActor
final class NotchHUDState: ObservableObject {
    /// Size of the collapsed shape: physical notch footprint (+wings added by content).
    @Published var closedSize: CGSize = .init(width: 185, height: 32)
    @Published var isExpanded: Bool = false
    /// True while the recording overlay owns the notch — HUD renders nothing.
    @Published var isSuppressed: Bool = false
}

/// Collapsed/expanded layout. Expansion is driven entirely by
/// NotchHUDController's mouse-position poll — deliberately NOT SwiftUI
/// `.onHover`: when this view resizes, its hover tracking area is rebuilt and
/// fires a spurious exit, producing an expand/collapse oscillation (observed
/// live before switching to polling).
struct NotchHUDRootView: View {
    @ObservedObject var state: NotchHUDState
    @ObservedObject var tasks: TasksStore = .shared
    @State private var doneHovering = false
    @State private var hoveredRowID: UUID?

    // MARK: - Shared geometry (controller hit-test uses the same math)

    /// Symmetric wing width either side of the physical notch when collapsed.
    static let wingWidth: CGFloat = 152
    static let expandedWidth: CGFloat = 460
    static let maxUpcomingShown = 5

    static func collapsedWidth(closedSize: CGSize) -> CGFloat {
        closedSize.width + Self.wingWidth * 2
    }

    /// Content-driven expanded height: notch clearance + eyebrow + NOW block
    /// + divider + upcoming rows + bottom padding.
    static func expandedSize(closedHeight: CGFloat, upcomingCount: Int) -> CGSize {
        let rows = min(max(upcomingCount, 1), Self.maxUpcomingShown)
        let overflow: CGFloat = upcomingCount > Self.maxUpcomingShown ? 20 : 0
        let height = closedHeight + 30 + 56 + 21 + CGFloat(rows) * 26 + overflow + 18
        return CGSize(width: Self.expandedWidth, height: height)
    }

    private var accent: Color { SettingsStore.shared.accentColor }

    var body: some View {
        VStack(spacing: 0) {
            if !self.state.isSuppressed {
                self.notchBody
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(
            self.state.isExpanded
                ? .spring(response: 0.42, dampingFraction: 0.8)
                : .spring(response: 0.45, dampingFraction: 1.0),
            value: self.state.isExpanded
        )
        .animation(.easeOut(duration: 0.15), value: self.state.isSuppressed)
    }

    private var notchBody: some View {
        let expandedSize = Self.expandedSize(
            closedHeight: self.state.closedSize.height,
            upcomingCount: self.tasks.upcomingTasks.count
        )
        return ZStack(alignment: .top) {
            NotchHUDShape(
                topCornerRadius: self.state.isExpanded ? 14 : 8,
                bottomCornerRadius: self.state.isExpanded ? 24 : 14
            )
            .fill(.black)
            .overlay {
                // Hairline edge so the panel reads as an object on dark backgrounds.
                NotchHUDShape(
                    topCornerRadius: self.state.isExpanded ? 14 : 8,
                    bottomCornerRadius: self.state.isExpanded ? 24 : 14
                )
                .stroke(.white.opacity(self.state.isExpanded ? 0.09 : 0.06), lineWidth: 1)
            }
            .shadow(color: .black.opacity(self.state.isExpanded ? 0.55 : 0.0), radius: 18, y: 6)

            if self.state.isExpanded {
                self.expandedContent
                    .transition(.scale(scale: 0.86, anchor: .top).combined(with: .opacity))
            } else {
                self.collapsedContent
                    .transition(.scale(scale: 0.86, anchor: .top).combined(with: .opacity))
            }
        }
        .frame(
            width: self.state.isExpanded ? expandedSize.width : Self.collapsedWidth(closedSize: self.state.closedSize),
            height: self.state.isExpanded ? expandedSize.height : self.state.closedSize.height
        )
    }

    // MARK: - Collapsed

    private var collapsedContent: some View {
        HStack(spacing: 0) {
            // LEFT WING — quiet queue count, trailing-aligned toward the notch.
            HStack(spacing: 5) {
                Spacer(minLength: 0)
                if !self.tasks.upcomingTasks.isEmpty {
                    Image(systemName: "text.badge.checkmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.38))
                    Text("\(self.tasks.upcomingTasks.count)")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                        .monospacedDigit()
                }
            }
            .frame(width: Self.wingWidth - 14)
            .padding(.leading, 14)

            // The physical notch cutout — keep it pure black.
            Color.clear.frame(width: self.state.closedSize.width)

            // RIGHT WING — accent dot + current task, leading-aligned.
            HStack(spacing: 6) {
                if self.tasks.currentTask != nil {
                    Circle()
                        .fill(self.accent)
                        .frame(width: 5, height: 5)
                        .shadow(color: self.accent.opacity(0.8), radius: 3)
                }
                Text(self.collapsedTitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(self.tasks.currentTask == nil ? 0.4 : 0.92))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .frame(width: Self.wingWidth - 14)
            .padding(.trailing, 14)
        }
        .frame(height: self.state.closedSize.height)
    }

    private var collapsedTitle: String {
        self.tasks.currentTask?.compactLabel
            ?? self.tasks.upcomingTasks.first.map { "Next: \($0.compactLabel)" }
            ?? "No tasks"
    }

    // MARK: - Expanded

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Clear the physical notch cutout.
            Color.clear.frame(height: self.state.closedSize.height)

            // Eyebrow row
            HStack {
                Text("TASKS")
                    .font(.system(size: 9.5, weight: .semibold))
                    .kerning(1.4)
                    .foregroundStyle(.white.opacity(0.38))
                Spacer()
                Text(self.upNextCountLabel)
                    .font(.system(size: 9.5, weight: .medium))
                    .kerning(0.4)
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(.top, 12)
            .padding(.bottom, 12)

            // NOW block
            HStack(spacing: 10) {
                Capsule()
                    .fill(self.tasks.currentTask == nil ? Color.white.opacity(0.15) : self.accent)
                    .frame(width: 3, height: 30)
                    .shadow(color: self.accent.opacity(self.tasks.currentTask == nil ? 0 : 0.6), radius: 4)
                VStack(alignment: .leading, spacing: 2) {
                    Text(self.tasks.currentTask?.title ?? "Nothing in progress")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(self.tasks.currentTask == nil ? .white.opacity(0.45) : .white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(self.tasks.currentTask == nil ? "hold ⌥` and say “start …”" : "in progress")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(self.tasks.currentTask == nil ? .white.opacity(0.28) : self.accent.opacity(0.85))
                }
                Spacer(minLength: 0)
                if self.tasks.currentTask != nil {
                    Button {
                        _ = self.tasks.apply([TaskOp(op: .done)])
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 22, weight: .regular))
                            .foregroundStyle(
                                self.doneHovering ? self.accent : .white.opacity(0.28),
                                self.doneHovering ? self.accent.opacity(0.22) : .white.opacity(0.08)
                            )
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .onHover { self.doneHovering = $0 }
                    .help("Mark done")
                }
            }
            .padding(.bottom, 12)

            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 1)
                .padding(.bottom, 8)

            // Upcoming rows
            if self.tasks.upcomingTasks.isEmpty {
                HStack(spacing: 7) {
                    Image(systemName: "circle.dashed")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.22))
                    Text("Nothing queued")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.white.opacity(0.35))
                }
                .frame(height: 26)
            } else {
                ForEach(self.tasks.upcomingTasks.prefix(Self.maxUpcomingShown)) { task in
                    self.upcomingRow(task)
                }
                if self.tasks.upcomingTasks.count > Self.maxUpcomingShown {
                    Text("+\(self.tasks.upcomingTasks.count - Self.maxUpcomingShown) more")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.3))
                        .padding(.leading, 19)
                        .frame(height: 20)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .frame(
            width: Self.expandedWidth,
            height: Self.expandedSize(
                closedHeight: self.state.closedSize.height,
                upcomingCount: self.tasks.upcomingTasks.count
            ).height,
            alignment: .topLeading
        )
    }

    /// One interactive queue row: click the circle to complete THIS task
    /// (regardless of what's current); click the title to make it current.
    private func upcomingRow(_ task: FluidTask) -> some View {
        let hovered = self.hoveredRowID == task.id
        return HStack(spacing: 9) {
            Button {
                _ = self.tasks.apply([TaskOp(op: .done, id: task.id.uuidString)])
            } label: {
                Image(systemName: hovered ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: hovered ? 12 : 10, weight: .medium))
                    .foregroundStyle(hovered ? self.accent : .white.opacity(0.25))
                    .frame(width: 14)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Complete “\(task.title)”")

            Button {
                _ = self.tasks.apply([TaskOp(op: .start, id: task.id.uuidString)])
            } label: {
                Text(task.title)
                    .font(.system(size: 12.5, weight: hovered ? .medium : .regular))
                    .foregroundStyle(.white.opacity(hovered ? 0.95 : 0.82))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Start “\(task.title)”")

            Spacer(minLength: 0)
        }
        .frame(height: 26)
        .onHover { self.hoveredRowID = $0 ? task.id : (self.hoveredRowID == task.id ? nil : self.hoveredRowID) }
    }

    private var upNextCountLabel: String {
        let count = self.tasks.upcomingTasks.count
        switch count {
        case 0: return "queue empty"
        case 1: return "1 up next"
        default: return "\(count) up next"
        }
    }
}
