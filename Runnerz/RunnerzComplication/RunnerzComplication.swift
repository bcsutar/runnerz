import SwiftUI
import WidgetKit

struct RunnerzLauncherEntry: TimelineEntry {
    let date: Date
}

struct RunnerzLauncherProvider: TimelineProvider {
    func placeholder(in context: Context) -> RunnerzLauncherEntry {
        RunnerzLauncherEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (RunnerzLauncherEntry) -> Void) {
        completion(RunnerzLauncherEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RunnerzLauncherEntry>) -> Void) {
        completion(Timeline(entries: [RunnerzLauncherEntry(date: .now)], policy: .never))
    }
}

struct RunnerzLauncherWidget: Widget {
    let kind = "com.runnerz.watch.launcher"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RunnerzLauncherProvider()) { _ in
            RunnerzLauncherView()
                .containerBackground(for: .widget) {
                    Color.clear
                }
        }
        .configurationDisplayName("Runnerz")
        .description("Tap to open Runnerz.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
            .accessoryCorner
        ])
    }
}

@main
struct RunnerzComplicationBundle: WidgetBundle {
    var body: some Widget {
        RunnerzLauncherWidget()
    }
}

private struct RunnerzLauncherView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            RunnerzTreadmillIcon(size: 32)
        case .accessoryRectangular:
            HStack(spacing: 6) {
                RunnerzTreadmillIcon(size: 22)
                Text("Runnerz")
                    .font(.headline)
            }
        case .accessoryInline:
            Label {
                Text("Runnerz")
            } icon: {
                RunnerzTreadmillIcon(size: 14)
            }
        case .accessoryCorner:
            RunnerzTreadmillIcon(size: 24)
                .widgetLabel {
                    Text("Runnerz")
                }
        @unknown default:
            RunnerzTreadmillIcon(size: 28)
        }
    }
}

private struct RunnerzTreadmillIcon: View {
    let size: CGFloat

    var body: some View {
        Canvas { context, _ in
            let scale = size / 1024
            context.scaleBy(x: scale, y: scale)

            var handle = Path()
            handle.move(to: CGPoint(x: 352, y: 638))
            handle.addLine(to: CGPoint(x: 423, y: 298))
            handle.addLine(to: CGPoint(x: 622, y: 298))
            context.stroke(handle,
                           with: .color(.white),
                           style: StrokeStyle(lineWidth: 84,
                                              lineCap: .round,
                                              lineJoin: .round))

            var deck = Path()
            deck.move(to: CGPoint(x: 278, y: 607))
            deck.addCurve(to: CGPoint(x: 207, y: 639),
                          control1: CGPoint(x: 250, y: 605),
                          control2: CGPoint(x: 226, y: 617))
            deck.addCurve(to: CGPoint(x: 180, y: 713),
                          control1: CGPoint(x: 190, y: 659),
                          control2: CGPoint(x: 180, y: 685))
            deck.addCurve(to: CGPoint(x: 274, y: 807),
                          control1: CGPoint(x: 180, y: 765),
                          control2: CGPoint(x: 222, y: 807))
            deck.addLine(to: CGPoint(x: 758, y: 807))
            deck.addCurve(to: CGPoint(x: 850, y: 715),
                          control1: CGPoint(x: 809, y: 807),
                          control2: CGPoint(x: 850, y: 766))
            deck.addCurve(to: CGPoint(x: 769, y: 624),
                          control1: CGPoint(x: 850, y: 668),
                          control2: CGPoint(x: 816, y: 630))
            deck.addLine(to: CGPoint(x: 278, y: 607))
            deck.closeSubpath()
            context.fill(deck, with: .color(.white))

            var belt = Path()
            belt.move(to: CGPoint(x: 282, y: 652))
            belt.addLine(to: CGPoint(x: 748, y: 669))
            context.stroke(belt,
                           with: .color(.white.opacity(0.45)),
                           style: StrokeStyle(lineWidth: 12, lineCap: .round))
        }
        .frame(width: size, height: size)
        .widgetAccentable()
    }
}
