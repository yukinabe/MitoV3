import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct MitoEntry: TimelineEntry {
    let date: Date
    let streak: Int
    let activeToday: Bool
    let due: Int
    let questsDone: Int
    let buddyName: String
    let buddyAsset: String
    let mood: String
    let moodLine: String
    let cardID: String?
    let cardDeck: String
    let cardFront: String
    let cardBack: String
    let cardRevealed: Bool
}

struct MitoProvider: TimelineProvider {
    private func snapshot() -> MitoEntry {
        let d = WidgetReviewStore.defaults
        let dueCards = WidgetReviewStore.dueCards()
        let firstDue = dueCards.first
        let cardID = firstDue?.id.uuidString ?? d?.string(forKey: "widget.card.id")
        return MitoEntry(
            date: Date(),
            streak: d?.integer(forKey: "widget.streak") ?? 0,
            activeToday: d?.bool(forKey: "widget.activeToday") ?? false,
            due: dueCards.isEmpty ? (d?.integer(forKey: "widget.due") ?? 0) : dueCards.count,
            questsDone: d?.integer(forKey: "widget.quests") ?? 0,
            buddyName: d?.string(forKey: "widget.buddy.name") ?? "Mito",
            buddyAsset: d?.string(forKey: "widget.buddy.asset") ?? "hero-mito-hop",
            mood: d?.string(forKey: "widget.buddy.mood") ?? "relaxed",
            moodLine: d?.string(forKey: "widget.buddy.line") ?? "I'm keeping watch.",
            cardID: cardID,
            cardDeck: firstDue?.deckName.isEmpty == false ? (firstDue?.deckName ?? "") : (firstDue?.deckID ?? d?.string(forKey: "widget.card.deck") ?? "Review"),
            cardFront: firstDue?.front ?? d?.string(forKey: "widget.card.front") ?? "",
            cardBack: firstDue?.back ?? d?.string(forKey: "widget.card.back") ?? "",
            cardRevealed: WidgetReviewStore.isRevealed(cardID: cardID)
        )
    }

    func placeholder(in context: Context) -> MitoEntry {
        MitoEntry(
            date: .now,
            streak: 3,
            activeToday: false,
            due: 12,
            questsDone: 1,
            buddyName: "Mito",
            buddyAsset: "hero-mito-hop",
            mood: "waiting",
            moodLine: "One card together?",
            cardID: UUID().uuidString,
            cardDeck: "Biology",
            cardFront: "What organelle makes ATP?",
            cardBack: "Mitochondria",
            cardRevealed: false
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (MitoEntry) -> Void) {
        completion(snapshot())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MitoEntry>) -> Void) {
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: .now)
            ?? .now.addingTimeInterval(3600)
        completion(Timeline(entries: [snapshot()], policy: .after(next)))
    }
}

struct MitoWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: MitoEntry

    var body: some View {
        switch family {
        case .systemMedium:
            MediumBioBudWidget(entry: entry)
        case .accessoryCircular:
            AccessoryCircleWidget(entry: entry)
        case .accessoryRectangular:
            AccessoryRectWidget(entry: entry)
        default:
            SmallBioBudWidget(entry: entry)
        }
    }
}

private struct SmallBioBudWidget: View {
    let entry: MitoEntry

    var body: some View {
        ZStack {
            WidgetPalette.bg
            VStack(spacing: 6) {
                HStack(alignment: .top, spacing: 4) {
                    BuddySprite(asset: entry.buddyAsset, size: 62, mood: entry.mood)
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("🔥 \(entry.streak)")
                            .font(.system(size: 17, weight: .black, design: .monospaced))
                            .foregroundStyle(entry.activeToday ? WidgetPalette.gold : WidgetPalette.cream)
                        Text("\(entry.due)")
                            .font(.system(size: 30, weight: .black, design: .rounded))
                            .foregroundStyle(entry.due > 0 ? WidgetPalette.red : WidgetPalette.green)
                        Text(entry.due == 1 ? "DUE" : "DUE")
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .foregroundStyle(WidgetPalette.cream.opacity(0.8))
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.buddyName.uppercased())
                        .font(.system(size: 12, weight: .black, design: .monospaced))
                        .foregroundStyle(WidgetPalette.gold)
                    Text(entry.moodLine)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(WidgetPalette.cream)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
        }
        .widgetURL(URL(string: "mitov3://battle/endless"))
        .containerBackground(for: .widget) { WidgetPalette.bg }
    }
}

private struct MediumBioBudWidget: View {
    let entry: MitoEntry

    var body: some View {
        ZStack {
            WidgetPalette.bg
            HStack(spacing: 10) {
                VStack(spacing: 5) {
                    BuddySprite(asset: entry.buddyAsset, size: 72, mood: entry.mood)
                    Text(entry.buddyName.uppercased())
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundStyle(WidgetPalette.gold)
                        .lineLimit(1)
                    Text(entry.moodLine)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(WidgetPalette.cream.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                }
                .frame(width: 92)

                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 6) {
                        MetricChip(text: "🔥 \(entry.streak)", active: entry.activeToday)
                        MetricChip(text: "\(entry.due) DUE", active: entry.due > 0)
                        Spacer(minLength: 0)
                        Button(intent: ContinueReviewIntent()) {
                            Text("OPEN")
                                .font(.system(size: 9, weight: .black, design: .monospaced))
                                .foregroundStyle(WidgetPalette.dark)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(WidgetPalette.cream)
                        }
                        .buttonStyle(.plain)
                    }

                    if entry.due > 0, let cardID = entry.cardID {
                        Text(entry.cardDeck.uppercased())
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                            .foregroundStyle(WidgetPalette.gold.opacity(0.9))
                            .lineLimit(1)
                        Text(entry.cardRevealed ? entry.cardBack : entry.cardFront)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(WidgetPalette.cream)
                            .lineLimit(3)
                            .minimumScaleFactor(0.72)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)

                        if entry.cardRevealed {
                            GradeButtons()
                        } else {
                            Button(intent: RevealWidgetCardIntent(cardID: cardID)) {
                                Text("REVEAL")
                                    .font(.system(size: 12, weight: .black, design: .monospaced))
                                    .foregroundStyle(WidgetPalette.dark)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(WidgetPalette.gold)
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        Spacer(minLength: 0)
                        Text("NO CARDS DUE")
                            .font(.system(size: 14, weight: .black, design: .monospaced))
                            .foregroundStyle(WidgetPalette.green)
                        Text("Your Bio Bud is resting until the next review.")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(WidgetPalette.cream.opacity(0.9))
                            .lineLimit(2)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(12)
        }
        .containerBackground(for: .widget) { WidgetPalette.bg }
    }
}

private struct GradeButtons: View {
    var body: some View {
        HStack(spacing: 4) {
            GradeButton(title: "AG", color: WidgetPalette.red, rating: .again)
            GradeButton(title: "HD", color: WidgetPalette.orange, rating: .hard)
            GradeButton(title: "GD", color: WidgetPalette.green, rating: .good)
            GradeButton(title: "EZ", color: WidgetPalette.blue, rating: .easy)
        }
    }
}

private struct GradeButton: View {
    let title: String
    let color: Color
    let rating: MitoWidgetRatingChoice

    var body: some View {
        Button(intent: GradeWidgetCardIntent(rating: rating)) {
            Text(title)
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundStyle(WidgetPalette.cream)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(color)
        }
        .buttonStyle(.plain)
    }
}

private struct AccessoryCircleWidget: View {
    let entry: MitoEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(entry.buddyAsset)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                Text("\(entry.due)")
                    .font(.system(size: 15, weight: .black, design: .rounded))
            }
        }
        .widgetURL(URL(string: "mitov3://battle/endless"))
    }
}

private struct AccessoryRectWidget: View {
    let entry: MitoEntry

    var body: some View {
        HStack(spacing: 6) {
            Image(entry.buddyAsset)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.due > 0 ? "\(entry.due) cards due" : "All clear")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                Text(entry.buddyName)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .widgetURL(URL(string: "mitov3://battle/endless"))
    }
}

private struct BuddySprite: View {
    let asset: String
    let size: CGFloat
    let mood: String

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(asset)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .frame(width: size, height: size)
                .shadow(color: glow.opacity(0.45), radius: 8)
            Text(face)
                .font(.system(size: size * 0.22, weight: .black))
                .padding(3)
                .background(WidgetPalette.cream)
                .clipShape(Circle())
                .offset(x: 3, y: 2)
        }
    }

    private var face: String {
        switch mood {
        case "worried": "!"
        case "waiting": "?"
        case "proud": "✓"
        case "sleepy": "z"
        default: "•"
        }
    }

    private var glow: Color {
        switch mood {
        case "worried": WidgetPalette.red
        case "waiting": WidgetPalette.gold
        case "proud": WidgetPalette.green
        case "sleepy": WidgetPalette.blue
        default: WidgetPalette.cream
        }
    }
}

private struct MetricChip: View {
    let text: String
    let active: Bool

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .black, design: .monospaced))
            .foregroundStyle(active ? WidgetPalette.dark : WidgetPalette.cream)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(active ? WidgetPalette.gold : WidgetPalette.cream.opacity(0.14))
    }
}

struct MitoWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MitoWidget", provider: MitoProvider()) { entry in
            MitoWidgetView(entry: entry)
        }
        .configurationDisplayName("Bio Bud")
        .description("Your home-screen Bio Bud, due cards, and streak.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

struct MitoFocusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MitoFocusActivityAttributes.self) { context in
            HStack(spacing: 10) {
                Image(context.attributes.buddyAsset)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(context.attributes.modeLabel)
                        .font(.system(size: 14, weight: .black, design: .monospaced))
                    Text(context.state.message)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .lineLimit(2)
                    Text(activityTime(context))
                        .font(.system(size: 18, weight: .black, design: .monospaced))
                }
                Spacer()
                Text(context.state.remainingDue > 0 ? "\(context.state.remainingDue) due" : "safe")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(context.state.remainingDue > 0 ? WidgetPalette.gold : WidgetPalette.green)
            }
            .padding(14)
            .activityBackgroundTint(WidgetPalette.bg)
            .activitySystemActionForegroundColor(WidgetPalette.gold)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(context.attributes.buddyAsset)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(context.attributes.buddyName)
                            .font(.system(size: 13, weight: .black, design: .rounded))
                        Text(context.state.message)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .lineLimit(2)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(activityTime(context))
                        .font(.system(size: 16, weight: .black, design: .monospaced))
                }
            } compactLeading: {
                Image(context.attributes.buddyAsset)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 24, height: 24)
            } compactTrailing: {
                Text(shortTime(context.state.elapsedSeconds))
                    .font(.system(size: 12, weight: .black, design: .monospaced))
            } minimal: {
                Image(context.attributes.buddyAsset)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
            }
        }
    }

    private func activityTime(_ context: ActivityViewContext<MitoFocusActivityAttributes>) -> String {
        if context.attributes.targetSeconds > 0 {
            return shortTime(max(0, context.attributes.targetSeconds - context.state.elapsedSeconds))
        }
        return shortTime(context.state.elapsedSeconds)
    }

    private func shortTime(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

enum WidgetPalette {
    static let bg = Color(red: 0.102, green: 0.063, blue: 0.035)
    static let dark = Color(red: 0.102, green: 0.063, blue: 0.035)
    static let cream = Color(red: 0.957, green: 0.902, blue: 0.753)
    static let gold = Color(red: 0.969, green: 0.788, blue: 0.263)
    static let green = Color(red: 0.29, green: 0.54, blue: 0.24)
    static let red = Color(red: 0.78, green: 0.27, blue: 0.22)
    static let orange = Color(red: 0.78, green: 0.49, blue: 0.18)
    static let blue = Color(red: 0.28, green: 0.48, blue: 0.66)
}

@main
struct MitoWidgetBundle: WidgetBundle {
    var body: some Widget {
        MitoWidget()
        MitoFocusLiveActivity()
    }
}
