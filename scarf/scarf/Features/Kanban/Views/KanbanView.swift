import SwiftUI
import ScarfCore
import ScarfDesign

/// Top-level Mac Kanban surface — toggles between the v2.7.5 board view
/// (drag-and-drop, full read/write) and the legacy v2.6 read-only list.
/// Kept as a single AppCoordinator route so users can switch between
/// presentations without leaving the route, and so accessibility users
/// (or anyone with a narrow window) keep a usable list fallback.
///
/// Capability-gated upstream: `SidebarView` only lists this route when
/// `HermesCapabilities.hasKanban` is true.
struct KanbanView: View {
    let context: ServerContext

    @AppStorage("kanban.viewMode") private var rawMode: String = ViewMode.board.rawValue

    enum ViewMode: String {
        case board
        case list
    }

    var body: some View {
        VStack(spacing: 0) {
            modeBar
            ScarfDivider()
            switch ViewMode(rawValue: rawMode) ?? .board {
            case .board:
                KanbanBoardView(context: context)
            case .list:
                KanbanListView(context: context)
            }
        }
        .background(ScarfColor.backgroundPrimary)
    }

    private var modeBar: some View {
        HStack(spacing: ScarfSpace.s2) {
            Spacer()
            Picker("View", selection: $rawMode) {
                Text("Board").tag(ViewMode.board.rawValue)
                Text("List").tag(ViewMode.list.rawValue)
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
        }
        .padding(.horizontal, ScarfSpace.s3)
        .padding(.vertical, ScarfSpace.s2)
    }
}
