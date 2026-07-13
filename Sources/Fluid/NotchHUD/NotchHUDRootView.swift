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

    static let openSize = CGSize(width: 420, height: 180)
    private static let maxUpcomingShown = 5

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
        ZStack(alignment: .top) {
            NotchHUDShape(
                topCornerRadius: self.state.isExpanded ? 12 : 6,
                bottomCornerRadius: self.state.isExpanded ? 20 : 13
            )
            .fill(.black)

            if self.state.isExpanded {
                self.expandedContent
                    .transition(.scale(scale: 0.8, anchor: .top).combined(with: .opacity))
            } else {
                self.collapsedContent
                    .transition(.scale(scale: 0.8, anchor: .top).combined(with: .opacity))
            }
        }
        .frame(
            width: self.state.isExpanded ? Self.openSize.width : self.collapsedWidth,
            height: self.state.isExpanded ? Self.openSize.height : self.state.closedSize.height
        )
    }

    /// Collapsed visual width: notch footprint plus the right text wing.
    /// Kept in sync with NotchHUDController's hit-test math.
    static func collapsedWidth(closedSize: CGSize) -> CGFloat {
        closedSize.width + 140
    }

    // MARK: - Task content

    /// Collapsed: the notch footprint plus a right "wing" for the current task.
    private var collapsedWidth: CGFloat {
        Self.collapsedWidth(closedSize: self.state.closedSize)
    }

    private var collapsedTitle: String {
        self.tasks.currentTask?.title
            ?? self.tasks.upcomingTasks.first.map { "Next: \($0.title)" }
            ?? "No task"
    }

    private var collapsedContent: some View {
        HStack(spacing: 0) {
            // Left wing spacer + the physical notch footprint stay empty (black).
            Spacer(minLength: self.state.closedSize.width)
            Text(self.collapsedTitle)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(self.tasks.currentTask == nil ? 0.45 : 0.85))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 132, alignment: .leading)
                .padding(.trailing, 8)
        }
        .frame(height: self.state.closedSize.height)
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 7) {
            // Keep clear of the physical notch cutout.
            Spacer(minLength: self.state.closedSize.height)

            Text("NOW")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
                .kerning(0.8)
            Text(self.tasks.currentTask?.title ?? "Nothing in progress")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(self.tasks.currentTask == nil ? .white.opacity(0.5) : .white)
                .lineLimit(2)

            Divider().overlay(.white.opacity(0.15))

            Text("UP NEXT")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
                .kerning(0.8)
            if self.tasks.upcomingTasks.isEmpty {
                Text("Nothing queued")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
            } else {
                ForEach(self.tasks.upcomingTasks.prefix(Self.maxUpcomingShown)) { task in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(.white.opacity(0.3))
                            .frame(width: 4, height: 4)
                        Text(task.title)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                if self.tasks.upcomingTasks.count > Self.maxUpcomingShown {
                    Text("+\(self.tasks.upcomingTasks.count - Self.maxUpcomingShown) more")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            Spacer(minLength: 6)
        }
        .padding(.horizontal, 20)
        .frame(width: Self.openSize.width, height: Self.openSize.height, alignment: .topLeading)
    }
}
