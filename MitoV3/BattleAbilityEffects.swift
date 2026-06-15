//  BattleAbilityEffects.swift
//  Ability/animation effect views, extracted from BattleView.swift (behavior-preserving).

import SwiftUI

struct BattleAbilityEffectView: View {
    let ability: BattleAbility
    let scale: CGFloat
    let opacity: Double
    let rotation: Double

    var body: some View {
        ZStack {
            if Self.spriteSheetAnimationKeys.contains(ability.animationKey) {
                SpriteSheetAbilityEffect(asset: ability.animationKey, frameCount: 8, frameSize: CGSize(width: 200, height: 128))
            } else {
                switch ability.animationKey {
            case "beam":
                BeamEffect(color: ability.color)
            case "bloom":
                BloomEffect(color: ability.color)
            case "network", "network-burst":
                NetworkEffect(color: ability.color, intense: ability.kind == .ultimate)
            case "mark":
                MarkEffect(color: ability.color)
            case "rally":
                RallyEffect(color: ability.color)
            case "shield":
                ShieldEffect(color: ability.color)
            case "storm":
                StormEffect(color: ability.color)
            case "burst":
                BurstEffect(color: ability.color, intense: true)
            case "pulse":
                PulseEffect(color: ability.color)
            default:
                BurstEffect(color: ability.color, intense: ability.kind == .ultimate)
                }
            }
        }
        .scaleEffect(scale)
        .rotationEffect(.degrees(rotation))
        .opacity(opacity)
        .blendMode(.plusLighter)
    }

    private static let spriteSheetAnimationKeys: Set<String> = [
        "mito-cristae-surge",
        "mito-powerhouse-burst",
        "cloro-sugar-rush",
        "cloro-photosynthesis-bloom",
        "astro-synapse-buffer",
        "astro-glial-network",
        "dendri-present-antigen",
        "dendri-immune-rally",
        "neuro-myelin-guard",
        "neuro-synaptic-overload",
        "bcell-affinity-shield",
        "bcell-memory-response",
        "prion-misfold-flick",
        "prion-chain-conformation",
        "prion-cascade",
        "t4-tail-pierce",
        "t4-genome-injection",
        "t4-lytic-burst"
    ]
}

struct SpriteSheetAbilityEffect: View {
    let asset: String
    let frameCount: Int
    let frameSize: CGSize
    @State private var frameIndex = 0

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width / frameSize.width, proxy.size.height / frameSize.height)
            Image(asset)
                .resizable()
                .interpolation(.none)
                .frame(width: frameSize.width * CGFloat(frameCount) * scale, height: frameSize.height * scale, alignment: .leading)
                .offset(x: -CGFloat(frameIndex) * frameSize.width * scale)
                .frame(width: frameSize.width * scale, height: frameSize.height * scale, alignment: .leading)
                .clipped()
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .onAppear {
            frameIndex = 0
            for index in 1..<frameCount {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.065) {
                    frameIndex = index
                }
            }
        }
    }
}

struct PulseEffect: View {
    let color: Color

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .stroke(color.opacity(0.95 - Double(index) * 0.2), lineWidth: CGFloat(7 - index * 2))
                    .frame(width: CGFloat(64 + index * 34), height: CGFloat(64 + index * 34))
            }
            Circle()
                .fill(Color(hex: "FFF1A8").opacity(0.42))
                .frame(width: 34, height: 34)
        }
    }
}

struct BeamEffect: View {
    let color: Color

    var body: some View {
        ZStack {
            Capsule()
                .fill(color.opacity(0.82))
                .frame(width: 178, height: 18)
                .rotationEffect(.degrees(-10))
            Capsule()
                .fill(Color.white.opacity(0.74))
                .frame(width: 138, height: 7)
                .rotationEffect(.degrees(-10))
            PixelSpark(color: color)
                .offset(x: 78, y: -16)
        }
    }
}

struct BloomEffect: View {
    let color: Color

    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { index in
                Capsule()
                    .fill(index.isMultiple(of: 2) ? color.opacity(0.82) : Color(hex: "FFF1A8").opacity(0.76))
                    .frame(width: 24, height: 78)
                    .offset(y: -50)
                    .rotationEffect(.degrees(Double(index) * 45))
            }
            Circle()
                .fill(Color.white.opacity(0.52))
                .frame(width: 46, height: 46)
        }
    }
}

struct NetworkEffect: View {
    let color: Color
    let intense: Bool

    var body: some View {
        ZStack {
            Path { path in
                path.move(to: CGPoint(x: 36, y: 104))
                path.addLine(to: CGPoint(x: 88, y: 48))
                path.addLine(to: CGPoint(x: 136, y: 82))
                path.addLine(to: CGPoint(x: 174, y: 34))
                path.move(to: CGPoint(x: 88, y: 48))
                path.addLine(to: CGPoint(x: 112, y: 150))
                path.addLine(to: CGPoint(x: 164, y: 118))
                path.move(to: CGPoint(x: 36, y: 104))
                path.addLine(to: CGPoint(x: 112, y: 150))
            }
            .stroke(color.opacity(0.86), style: StrokeStyle(lineWidth: intense ? 7 : 5, lineCap: .square, lineJoin: .round))
            .frame(width: 210, height: 180)

            ForEach(0..<6, id: \.self) { index in
                Circle()
                    .fill(index.isMultiple(of: 2) ? Color.white.opacity(0.78) : color.opacity(0.9))
                    .frame(width: intense ? 18 : 13, height: intense ? 18 : 13)
                    .position(networkPoint(index))
            }
        }
        .frame(width: 210, height: 180)
    }

    private func networkPoint(_ index: Int) -> CGPoint {
        let points = [
            CGPoint(x: 36, y: 104), CGPoint(x: 88, y: 48), CGPoint(x: 136, y: 82),
            CGPoint(x: 174, y: 34), CGPoint(x: 112, y: 150), CGPoint(x: 164, y: 118)
        ]
        return points[index % points.count]
    }
}

struct MarkEffect: View {
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(color, lineWidth: 7)
                .frame(width: 106, height: 106)
            Rectangle()
                .fill(color)
                .frame(width: 140, height: 8)
            Rectangle()
                .fill(color)
                .frame(width: 8, height: 140)
            Circle()
                .fill(Color.white.opacity(0.7))
                .frame(width: 20, height: 20)
        }
    }
}

struct RallyEffect: View {
    let color: Color

    var body: some View {
        ZStack {
            ForEach(0..<10, id: \.self) { index in
                Rectangle()
                    .fill(index.isMultiple(of: 2) ? color : Color(hex: "FFF1A8"))
                    .frame(width: 10, height: 46)
                    .offset(y: -72)
                    .rotationEffect(.degrees(Double(index) * 36))
            }
            MarkEffect(color: color)
                .scaleEffect(0.72)
        }
    }
}

struct ShieldEffect: View {
    let color: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28)
                .stroke(color.opacity(0.9), lineWidth: 9)
                .frame(width: 134, height: 154)
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color.white.opacity(0.6), lineWidth: 4)
                .frame(width: 96, height: 116)
            PixelSpark(color: color)
                .offset(x: 58, y: -52)
        }
    }
}

struct StormEffect: View {
    let color: Color

    var body: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { index in
                LightningBolt()
                    .fill(index.isMultiple(of: 2) ? color : Color.white.opacity(0.82))
                    .frame(width: 38, height: 112)
                    .offset(x: CGFloat(index - 2) * 34, y: CGFloat(index % 2) * 18)
                    .rotationEffect(.degrees(Double(index * 8 - 12)))
            }
        }
    }
}

struct BurstEffect: View {
    let color: Color
    let intense: Bool

    var body: some View {
        ZStack {
            ForEach(0..<(intense ? 14 : 9), id: \.self) { index in
                Rectangle()
                    .fill(index.isMultiple(of: 2) ? color : Color(hex: "FFF1A8"))
                    .frame(width: intense ? 12 : 9, height: intense ? 92 : 62)
                    .offset(y: intense ? -82 : -58)
                    .rotationEffect(.degrees(Double(index) * (intense ? 25.7 : 40)))
            }
            Circle()
                .fill(color.opacity(0.58))
                .frame(width: intense ? 98 : 64, height: intense ? 98 : 64)
            Circle()
                .fill(Color.white.opacity(0.72))
                .frame(width: intense ? 44 : 28, height: intense ? 44 : 28)
        }
    }
}

struct PixelSpark: View {
    let color: Color

    var body: some View {
        ZStack {
            Rectangle()
                .fill(color)
                .frame(width: 28, height: 8)
            Rectangle()
                .fill(color)
                .frame(width: 8, height: 28)
            Rectangle()
                .fill(Color.white.opacity(0.75))
                .frame(width: 8, height: 8)
        }
    }
}

struct LightningBolt: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX + rect.width * 0.18, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX - rect.width * 0.16, y: rect.midY * 0.92))
        path.addLine(to: CGPoint(x: rect.midX + rect.width * 0.12, y: rect.midY * 0.92))
        path.addLine(to: CGPoint(x: rect.midX - rect.width * 0.22, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX - rect.width * 0.02, y: rect.midY * 1.12))
        path.addLine(to: CGPoint(x: rect.midX - rect.width * 0.28, y: rect.midY * 1.12))
        path.closeSubpath()
        return path
    }
}
