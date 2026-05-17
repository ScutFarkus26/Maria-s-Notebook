import SwiftUI

struct BookClubRootView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case packets
        case sessions

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .packets: return "Packets"
            case .sessions: return "Sessions"
            }
        }
    }

    @SceneStorage("bookClub.tab") private var rawTab: String = Tab.packets.rawValue

    private var selectedTab: Tab {
        get { Tab(rawValue: rawTab) ?? .packets }
    }

    private var tabBinding: Binding<Tab> {
        Binding(
            get: { Tab(rawValue: rawTab) ?? .packets },
            set: { rawTab = $0.rawValue }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: tabBinding) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.displayName).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            Divider()

            Group {
                switch selectedTab {
                case .packets:
                    BookClubPacketsListView()
                case .sessions:
                    BookClubSessionsListView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
