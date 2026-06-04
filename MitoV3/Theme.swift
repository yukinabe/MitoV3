import SwiftUI

struct DottedDarkBackground: View {
    var body: some View {
        Color(hex: "20150D")
            .overlay {
                GeometryReader { proxy in
                    Path { path in
                        let step: CGFloat = 8
                        for x in stride(from: CGFloat(0), through: proxy.size.width, by: step) {
                            for y in stride(from: CGFloat(0), through: proxy.size.height, by: step) {
                                path.addEllipse(in: CGRect(x: x, y: y, width: 1.2, height: 1.2))
                            }
                        }
                    }
                    .fill(Color(hex: "3A2A18").opacity(0.55))
                }
            }
            .ignoresSafeArea()
    }
}

struct WoodBackground: View {
    var body: some View {
        ZStack {
            Color(hex: "1D130A").ignoresSafeArea()
            VStack(spacing: 0) {
                ForEach(0..<18, id: \.self) { index in
                    Rectangle()
                        .fill(index % 2 == 0 ? Color(hex: "241508") : Color(hex: "1A0F06"))
                        .frame(height: 28)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Color.black.opacity(0.22)).frame(height: 1)
                        }
                }
                Spacer(minLength: 0)
            }
            .opacity(0.72)
            .ignoresSafeArea()
        }
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct ProgressBar: View {
    let progress: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color(hex: "B89868"))
                Rectangle()
                    .fill(color)
                    .frame(width: proxy.size.width * progress)
            }
            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
        }
        .frame(height: 8)
    }
}

struct FeatureButton: View {
    let title: String
    let badge: String?
    let detail: String
    let tint: Color
    var height: CGFloat = 84

    var body: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(Color.black.opacity(0.22))
                .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
                .frame(width: 52, height: 52)
                .overlay(Text(title == "ENDLESS REVIEW" ? "B" : "X").pixelText(size: 18, color: .white))
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .pixelText(size: 15, color: .white)
                if let badge {
                    Text(badge)
                        .pixelText(size: 7, color: Color(hex: "18100A"))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color(hex: "F7C943"))
                        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 1.5))
                }
                Text(detail)
                    .font(.custom(MitoFont.regular, size: 13))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(2)
            }
            Spacer()
            Text(">")
                .pixelText(size: 18, color: .white)
        }
        .padding(12)
        .frame(height: height)
        .background(tint)
        .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 4))
    }
}

struct HPBar: View {
    let value: Int
    let max: Int
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color(hex: "2A1A14"))
                Rectangle()
                    .fill(tint)
                    .frame(width: proxy.size.width * CGFloat(value) / CGFloat(max))
                HStack(spacing: 19) {
                    ForEach(0..<8, id: \.self) { _ in
                        Rectangle()
                            .fill(Color.black.opacity(0.18))
                            .frame(width: 1)
                    }
                }
            }
            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
        }
        .frame(height: 14)
    }
}

struct ParchmentBox<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(14)
            .background(Color(hex: "EAD4A4"))
            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
    }
}

struct PixelButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .pixelText(size: 13, color: Color(hex: "F4E6C0"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(hex: "4A8A3C"))
                .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
        }
        .buttonStyle(.plain)
    }
}

struct BackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("<")
                .pixelText(size: 15, color: Color(hex: "F4E6C0"))
                .frame(width: 34, height: 34)
                .background(Color(hex: "6B4324"))
                .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}

struct ScreenTitle: View {
    let title: String
    let subtitle: String

    init(_ title: String, subtitle: String) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .pixelText(size: 16, color: Color(hex: "F4E6C0"))
            Text(subtitle)
                .font(.custom(MitoFont.regular, size: 13))
                .foregroundStyle(Color(hex: "F4E6C0").opacity(0.84))
        }
    }
}

struct SectionLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .pixelText(size: 9, color: Color(hex: "FFD24D"))
    }
}

struct SmallTag: View {
    let title: String
    let active: Bool

    init(_ title: String, active: Bool) {
        self.title = title
        self.active = active
    }

    var body: some View {
        Text(title)
            .pixelText(size: 7, color: active ? .white : Color(hex: "4A2F1C"))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(active ? Color(hex: "6B9C4A") : Color(hex: "D8B884"))
            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 1.5))
    }
}

struct StatPill: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .pixelText(size: 8, color: Color(hex: "3A2A18"))
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color(hex: "F4E6C0"))
            .overlay(Rectangle().stroke(Color(hex: "B89868"), lineWidth: 1))
    }
}

struct CornerBrackets: Shape {
    func path(in rect: CGRect) -> Path {
        let len = min(rect.width, rect.height) * 0.22
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + len))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + len, y: rect.minY))
        path.move(to: CGPoint(x: rect.maxX - len, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + len))
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY - len))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + len, y: rect.maxY))
        path.move(to: CGPoint(x: rect.maxX - len, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - len))
        return path
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

extension Image {
    func screenBackground() -> some View {
        self.resizable()
            .interpolation(.none)
            .scaledToFill()
            .ignoresSafeArea()
    }
}

enum MitoFont {
    static let regular = "PixelifySans-Regular"
    static let bold = "PixelifySans-Regular"
    static let micro = "Silkscreen-Bold"
}

extension Text {
    func pixelText(size: CGFloat, color: Color) -> some View {
        self.font(.custom(MitoFont.bold, size: size * 1.16).weight(.bold))
            .foregroundStyle(color)
            .textCase(.uppercase)
            .lineLimit(2)
            .minimumScaleFactor(0.65)
    }
}

extension View {
    func authInputStyle() -> some View {
        self.font(.custom(MitoFont.regular, size: 18))
            .foregroundStyle(Color(hex: "3A2A18"))
            .padding(10)
            .background(Color(hex: "F4E6C0"))
            .overlay(Rectangle().stroke(Color(hex: "18100A"), lineWidth: 3))
    }
}

extension Color {
    static let mitoWoodDarkest = Color(hex: "1D130A")

    init(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&value)
        let r: UInt64
        let g: UInt64
        let b: UInt64
        switch clean.count {
        case 3:
            r = (value >> 8) * 17
            g = ((value >> 4) & 0xF) * 17
            b = (value & 0xF) * 17
        default:
            r = value >> 16
            g = (value >> 8) & 0xFF
            b = value & 0xFF
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: 1)
    }
}
