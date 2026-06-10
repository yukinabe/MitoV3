import WidgetKit
import SwiftUI

// The app writes this snapshot into the shared App Group container
// (see WidgetBridge in Engagement.swift) and pings reloadAllTimelines.
private let suiteName = "group.com.yukinabe.mitov3"

struct MitoEntry: TimelineEntry {
    let date: Date
    let streak: Int
    let activeToday: Bool
    let due: Int
    let questsDone: Int
}

struct MitoProvider: TimelineProvider {
    private func snapshot() -> MitoEntry {
        let d = UserDefaults(suiteName: suiteName)
        return MitoEntry(
            date: Date(),
            streak: d?.integer(forKey: "widget.streak") ?? 0,
            activeToday: d?.bool(forKey: "widget.activeToday") ?? false,
            due: d?.integer(forKey: "widget.due") ?? 0,
            questsDone: d?.integer(forKey: "widget.quests") ?? 0
        )
    }

    func placeholder(in context: Context) -> MitoEntry {
        MitoEntry(date: .now, streak: 3, activeToday: false, due: 12, questsDone: 1)
    }

    func getSnapshot(in context: Context, completion: @escaping (MitoEntry) -> Void) {
        completion(snapshot())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MitoEntry>) -> Void) {
        // The app pushes a reload on every real change; this refresh cadence
        // just keeps "due" from going stale overnight.
        let next = Calendar.current.date(byAdding: .hour, value: 4, to: .now)
            ?? .now.addingTimeInterval(4 * 3600)
        completion(Timeline(entries: [snapshot()], policy: .after(next)))
    }
}

struct MitoWidgetView: View {
    var entry: MitoEntry

    private let cream = Color(red: 0.957, green: 0.902, blue: 0.753)   // F4E6C0
    private let amber = Color(red: 0.969, green: 0.788, blue: 0.263)   // F7C943
    private let bark = Color(red: 0.420, green: 0.263, blue: 0.141)    // 6B4324

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text("🔥")
                Text("\(entry.streak)")
                    .font(.system(size: 30, weight: .heavy, design: .monospaced))
                    .foregroundStyle(entry.activeToday ? amber : cream)
                Spacer()
            }
            Text(entry.activeToday ? "STREAK SAFE" : "STUDY TODAY")
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundStyle(entry.activeToday ? amber : cream.opacity(0.85))

            Spacer(minLength: 2)

            Text(entry.due == 1 ? "1 CARD DUE" : "\(entry.due) CARDS DUE")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(cream)

            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Rectangle()
                        .fill(i < entry.questsDone ? amber : cream.opacity(0.25))
                        .frame(height: 5)
                }
            }
        }
        .padding(2)
        .containerBackground(for: .widget) {
            Color(red: 0.102, green: 0.063, blue: 0.035)               // 1A1009
        }
        .widgetURL(URL(string: "mitov3://home"))
    }
}

struct MitoWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MitoWidget", provider: MitoProvider()) { entry in
            MitoWidgetView(entry: entry)
        }
        .configurationDisplayName("Mito")
        .description("Your streak, due cards, and daily quests.")
        .supportedFamilies([.systemSmall])
    }
}

@main
struct MitoWidgetBundle: WidgetBundle {
    var body: some Widget {
        MitoWidget()
    }
}
