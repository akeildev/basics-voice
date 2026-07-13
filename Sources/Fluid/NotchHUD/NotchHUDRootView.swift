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

/// Hover state machine + collapsed/expanded layout.
///
/// Hover contract (values proven by an existing notch companion implementation):
/// 0.3 s dwell before expanding (prevents accidental flicks), 100 ms debounce
/// before collapsing (prevents flicker crossing internal gaps).
struct NotchHUDRootView: View {
    @ObservedObject var state: NotchHUDState

    @State private var hoverTask: Task<Void, Never>?

    private static let openSize = CGSize(width: 420, height: 180)

    var body: some View {
        VStack(spacing: 0) {
            if !self.state.isSuppressed {
                self.notchBody
                    .onHover { hovering in self.handleHover(hovering) }
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

    // MARK: - Spike content (Unit 1 only — replaced by TaskListWidget in Unit 3)

    /// Collapsed: the notch footprint plus a right "wing" for the current task.
    private var collapsedWidth: CGFloat {
        self.state.closedSize.width + 140
    }

    private var collapsedContent: some View {
        HStack(spacing: 0) {
            // Left wing spacer + the physical notch footprint stay empty (black).
            Spacer(minLength: self.state.closedSize.width)
            Text("Current: spike task")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .frame(width: 132, alignment: .leading)
                .padding(.trailing, 8)
        }
        .frame(height: self.state.closedSize.height)
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Keep clear of the physical notch cutout.
            Spacer(minLength: self.state.closedSize.height)
            Text("NOW")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
            Text("Spike task — prove coexistence")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Divider().overlay(.white.opacity(0.15))
            Text("UP NEXT")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
            Text("Static row one")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.8))
            Text("Static row two")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.8))
            Spacer(minLength: 6)
        }
        .padding(.horizontal, 20)
        .frame(width: Self.openSize.width, height: Self.openSize.height, alignment: .topLeading)
    }

    // MARK: - Hover machine

    private func handleHover(_ hovering: Bool) {
        self.hoverTask?.cancel()
        self.hoverTask = Task { @MainActor in
            if hovering {
                // Dwell before expanding.
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                self.state.isExpanded = true
            } else {
                // Short debounce before collapsing.
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard !Task.isCancelled else { return }
                self.state.isExpanded = false
            }
        }
    }
}
