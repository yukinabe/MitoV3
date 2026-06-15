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

// MARK: - Localization (in-app language switch)

enum AppLanguage: String, CaseIterable, Identifiable {
    case en, ja
    var id: String { rawValue }
    var displayName: String { self == .en ? "English" : "日本語" }
}

/// In-app language selection (independent of the system language). Persists to
/// UserDefaults so the nonisolated `L()` lookup can read it from anywhere.
@MainActor
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()
    nonisolated static let defaultsKey = "app.language"

    @Published var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: Self.defaultsKey) }
    }

    private init() {
        if let raw = UserDefaults.standard.string(forKey: Self.defaultsKey),
           let lang = AppLanguage(rawValue: raw) {
            language = lang
        } else {
            // First run: follow the device's preferred language for Japanese.
            let pref = Locale.preferredLanguages.first ?? "en"
            let lang: AppLanguage = pref.hasPrefix("ja") ? .ja : .en
            language = lang
            UserDefaults.standard.set(lang.rawValue, forKey: Self.defaultsKey)
        }
    }
}

/// Localized string for the current app language, keyed by the English source.
/// Returns the English text when no translation exists (graceful fallback), so
/// untranslated strings simply stay in English. Nonisolated so it's callable
/// from anywhere (views re-render via `.id(language)` at the root on change).
func L(_ en: String) -> String {
    guard (UserDefaults.standard.string(forKey: LocalizationManager.defaultsKey) ?? "en") == "ja"
    else { return en }
    return JATranslations.map[en] ?? en
}

/// Localized format string + args (e.g. `Lf("%@ cards", n)`).
func Lf(_ enFormat: String, _ args: CVarArg...) -> String {
    let fmt = (UserDefaults.standard.string(forKey: LocalizationManager.defaultsKey) ?? "en") == "ja"
        ? (JATranslations.map[enFormat] ?? enFormat)
        : enFormat
    return String(format: fmt, arguments: args)
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

// MARK: - Japanese translations
//
// Keyed by the exact English source string. Coverage (intentionally scoped):
// settings, navigation, onboarding, the tutorial + campaign story dialogue, and
// character/deck names. Deep gameplay screens fall back to English for now and
// can be added here incrementally — no other wiring needed.
enum JATranslations {
    static let map: [String: String] = [
        // — Navigation
        "Shop": "ショップ", "Team": "チーム", "Home": "ホーム",
        "Battle": "バトル", "Cards": "カード",

        // — Settings
        "SETTINGS": "設定",
        "ACCOUNT": "アカウント",
        "LOGIN": "ログイン",
        "MANAGE": "管理",
        "SIGN IN": "サインイン",
        "Sign in to sync decks and progress.": "デッキと進行状況を同期するにはサインインしてください。",
        "SOUND": "サウンド",
        "Menu and battle effects.": "メニューとバトルの効果音。",
        "MUSIC": "ミュージック",
        "Background music.": "バックグラウンドミュージック。",
        "ANIMATION": "アニメーション",
        "Idle character movement.": "キャラクターの待機モーション。",
        "FOCUS LOCK": "集中ロック",
        "STAY-IN-APP LOCK": "アプリ内ロック",
        "Leaving Mito during a timed session voids the run.": "計測セッション中にMitoを離れると、その記録は無効になります。",
        "BLOCK APPS": "アプリをブロック",
        "Shield distracting apps with Screen Time during focus. Needs permission.": "集中中にスクリーンタイムで気が散るアプリを遮断します。許可が必要です。",
        "CHOOSE BLOCKED APPS": "ブロックするアプリを選ぶ",
        "PICK": "選択",
        "ON": "オン",
        "OFF": "オフ",
        "LANGUAGE": "言語",
        "App display language.": "アプリの表示言語。",

        // — Onboarding
        "WHAT ARE YOU STUDYING?": "何を勉強していますか？",
        "We'll tune your starter content.": "最初の学習内容を調整します。",
        "Biology": "生物", "Languages": "語学", "Test Prep": "試験対策",
        "Med / Nursing": "医療・看護", "History": "歴史", "Other": "その他",
        "ADD YOUR FIRST DECK": "最初のデッキを追加",
        "Pick a starter deck to study right away.": "すぐに学習できるスターターデッキを選ぼう。",
        "CARDS": "枚",
        "SKIP FOR NOW": "今はスキップ",
        "YOU'RE ALL SET": "準備完了！",
        "Start a focus session to earn ATP, then review your cards in battle.": "集中セッションでATPを稼いで、バトルでカードを復習しよう。",
        "START STUDYING": "学習をはじめる",

        // — Character names
        "Mito": "ミト", "Chloro": "クロロ", "Astro": "アストロ",
        "Dendri": "デンドリ", "Neuro": "ニューロ", "B Cell": "Bセル",
        "Mutagem": "ミュータジェム", "Spikevyrus": "スパイクウイルス",
        "Cytocrawler": "サイトクローラー",

        // — Roles
        "Support": "サポート", "DPS": "アタッカー", "Tank": "タンク",
        "LORE": "プロフィール",

        // — Character lore
        "A bean-shaped mitochondria helper with bright cristae. Turns focus into ATP and keeps the party steady when long study sessions get rough.":
            "明るいクリステを持つ、豆の形をしたミトコンドリアの相棒。集中力をATPに変え、長い勉強でも仲間を支え続ける。",
        "A chloroplast DPS who captures light and stores it as clean burst damage. Quick, bright, and built for photosynthesis-themed pressure.":
            "光を集めて高火力に変える葉緑体のアタッカー。素早く、まぶしく、光合成で一気に押し込む。",
        "A star-shaped astrocyte support who stabilizes the neural field. Astro's attacks feel like glial network signals instead of raw force.":
            "神経のフィールドを安定させる、星形のアストロサイトのサポート。攻撃は力任せではなく、グリア網のシグナルのよう。",
        "A branching dendritic-cell scout who keeps the team alert and turns small wins into streaks.":
            "枝分かれした樹状細胞の斥候。仲間の警戒を保ち、小さな勝ちを連勝につなげる。",
        "A sturdy neuron buffer with branching signals. Soaks pressure while fragile allies line up the next answer.":
            "枝分かれするシグナルを持つ、頑丈なニューロンの壁役。打たれ強く、もろい仲間が次の一手を構える間を守る。",
        "A careful immune support who turns repeated exposure into stronger responses. Antibody-themed moves make B Cell feel defensive without extra combat math.":
            "繰り返しの経験を、より強い応答に変える慎重な免疫サポート。抗体テーマの技で、難しい計算なしに守りを固める。",
        "A mutated gem-spore that drifts through endless review. Capturing one binds its restless energy to your team.":
            "エンドレス復習を漂う、変異した結晶胞子。捕まえれば、その荒ぶる力が仲間に加わる。",
        "A spike-shelled virus boss from the campaign depths. Stubborn, sturdy, and surprisingly loyal once captured.":
            "キャンペーン深部に潜む、トゲの殻を持つウイルスのボス。頑固で頑丈、でも捕まえると意外と忠実。",
        "A fast cytoplasmic crawler that skitters between waves. Rare, twitchy, and a brutal attacker.":
            "ウェーブの合間をすばやく這う細胞質クローラー。レアでせわしなく、攻撃は容赦ない。",

        // — Tutorial (session 1)
        "oh, you're here. good, 'cause we've got a situation.":
            "お、来たね。ちょうどよかった。ちょっと事件が起きててさ。",
        "see that? a Mutagem. it eats the stuff you forget. right now it's just you and me against it.":
            "あれ見える？ミュータジェムだよ。キミが忘れたことをエサにするんだ。今あれに立ち向かえるのは、キミとボクだけ。",
        "here's the deal. answer a flashcard right and we hit it. your brain is the weapon. kinda poetic, right?":
            "やることはシンプル。カードに正解すれば、あいつに一撃。キミの頭脳が武器ってわけ。ちょっと詩的でしょ。",
        "let's get you into a real fight. follow me.":
            "さっそく本番の戦いといこう。ついといで。",
        "i loaded you up with some %@ cards. let's put 'em to work.":
            "%@のカードをいくつか用意しといたよ。さっそく使っていこう。",
        "okay. one card, one hit. let's see what you've got.":
            "よし。カード一枚で一撃。キミの実力、見せてもらおうか。",
        "let's go! that's the whole loop. answer, hit, repeat. you've basically got it.":
            "いいね！これが基本の流れ。答えて、攻撃、くり返し。もうほぼマスターだよ。",
        "battles train your memory. and studying earns ATP to level the team up.":
            "バトルは記憶のトレーニング。そして勉強でATPを稼げば、チームを強化できる。",
        "one more thing. we don't have to fight solo forever.":
            "もうひとつ。ずっと一人で戦う必要はないんだ。",
        "clear a Campaign stage and its boss joins the team. first up is Chloro, a chloroplast who hits HARD.":
            "キャンペーンのステージをクリアすると、そのボスが仲間になる。まずはクロロ、一撃の重い葉緑体だ。",
        "head to Battle → Campaign when you're ready to recruit them. you got this. 🫡":
            "準備ができたら バトル → キャンペーン へ。仲間にしに行こう。キミならできる。🫡",

        // — Trust / study companion
        "STUDY WITH": "いっしょに勉強",
        "TRUST": "信頼",
        "BOND": "絆",
        "Already trusted. studying deepens your bond with %@.": "もう信頼ばっちり。勉強すると%@との絆がもっと深まるよ。",
        "Study to earn %@'s trust · %ld min to full.": "勉強して%@の信頼を得よう · 満タンまであと%ld分。",
        "Earn full Trust to use them in battle.": "バトルで使うには信頼を満タンにしよう。",
        "Study with them to build Trust.": "いっしょに勉強して信頼を育てよう。",
        "LOCKED": "ロック中",

        // — Recruit / capture popups (campaign flow)
        "%@ JOINED YOUR TEAM!": "%@がチームに加わった！",
        "✦ ADD TO ROSTER": "✦ 仲間にする",
        "A WILD %@ APPEARED!": "野生の%@があらわれた！",
        "LET GO": "にがす",
        "✦ CAPTURE": "✦ 捕まえる",

        // — Seed deck names
        "Biology 220": "生物学220",
        "Physics formulas": "物理の公式",
        "Japanese vocab": "日本語の単語",
        "Organic mechanisms": "有機反応機構",

        // — Tutorial spotlight captions
        "head over to Battle ⚔": "バトルへ向かおう ⚔",
        "start with Endless Review, no pressure": "まずはエンドレス復習から。気楽にね",
        "pick a deck, tap any one": "デッキを選ぼう。どれでもタップ",
        "now hit Start (it's free)": "スタートを押そう（無料だよ）",
        "try to recall it… then reveal the answer": "思い出してみて…それから答えを表示",
        "rate how well you knew it, be honest": "どれくらい覚えてたか評価しよう。正直に",
        "now hit it, pick a move": "さあ攻撃。技を選ぼう",
        "back to your meadow": "草原に戻ろう",
        "this is your real focus time. every session earns ATP": "ここが本当の集中タイム。セッションごとにATPが手に入る",

        // — Forced campaign tutorial (stage 1 → 2)
        "open the Campaign map": "キャンペーンマップを開こう",
        "tap Stage 1": "ステージ1をタップ",
        "tap Stage 2": "ステージ2をタップ",
        "pick a deck to fight with": "戦うデッキを選ぼう",
        "start the fight": "戦いを始めよう",
        "defeat the boss to free Chloro!": "ボスを倒してクロロを助けよう！",
        "nice! head back when you're done": "いいね！終わったら戻ろう",
        "beat it down, then CAPTURE it!": "削りきって、捕まえよう！",
        "all done! head back when you're ready": "完了！準備ができたら戻ろう",
        "Chloro's with us now. one more: Stage 2 teaches you to capture a wild one.":
            "クロロが仲間になった。もうひとつ、ステージ2では野生のやつの捕まえ方を教えるよ。",
        "that's the whole loop: study, battle, recruit, capture. go get 'em. 🫡":
            "これで全部の流れだ。勉強、バトル、仲間集め、そして捕獲。あとは思いきり楽しもう。🫡",

        // — Campaign story (stages 1–3)
        "there. a chloroplast. or it was one. the Fading's got it. see how the light's gone grey?":
            "ほら、葉緑体だ。いや、元はね。“フェイディング”にやられてる。光がくすんでるの、分かる？",
        "it won't hear words anymore, only remembering. recall it clean and we'll pull it back to itself.":
            "もう言葉は届かない。届くのは“思い出すこと”だけ。しっかり思い出して、あいつを正気に引き戻そう。",
        "spoke too soon. that spiky thing's a Spikevyrus scout. the Fading isn't just happening. something's spreading it.":
            "言うのが早かった。あのトゲトゲはスパイクウイルスの斥候。フェイディングはただ起きてるんじゃない。誰かが広めてる。",
        "so we're not curing a sickness. we're fighting whatever WANTS us sick. cool. love that.":
            "つまり病気を治してるんじゃなくて、こっちを病気にしたい“何か”と戦ってるわけね。最高。大好き。",
        "wear it down and you can bind it to the team. even a scout knows where it crawled from. let's catch one.":
            "削りきれば仲間にできる。斥候だって、自分がどこから来たかは知ってる。一匹捕まえよう。",
        "feel that static? that's a neuron. Neuro. its signals are scrambled. the Fading hits memory hardest here.":
            "このノイズ、感じる？ニューロンだ。ニューロ。信号がぐちゃぐちゃになってる。フェイディングは記憶を一番強く狂わせるんだ。",
        "it's twitching like it forgot how to think.":
            "考え方を忘れたみたいにビクついてる。",
        "because it did. same as you were. recall it sharp and we'll straighten its wires out.":
            "実際そうなんだ。昔のキミと同じ。鋭く思い出して、こいつの配線を直してやろう。",
        "…oh. OH. the light. it's back. how long was i out?":
            "…あれ。あっ。光が、戻ってる。私、どれくらい気を失ってた？",
        "long enough. welcome back, Chloro.":
            "けっこう長いよ。おかえり、クロロ。",
        "i had the weirdest dream where i was a feral lamp. …we don't talk about it. let's move.":
            "野生の電気スタンドになる超変な夢を見たわ。…この話はナシ。さ、行こ。",
        "that's the idea. every one we take is one less spreading the Fading.":
            "その調子。一匹捕まえるごとに、フェイディングを広めるやつが一匹減る。",
        "and a little extra muscle never hurts. onward, bean.":
            "それに、戦力は多いに越したことないしね。行くよ、豆っち。",
        "…signal restored. systems nominal. who pulled me back?":
            "…信号、回復。システム正常。引き戻したのは誰だ？",
        "team effort. you're one of us now, if you want in.":
            "みんなのおかげさ。キミはもう仲間だ。その気があるなら。",
        "i hold the line. nothing gets past me twice.":
            "前線は俺が守る。二度は誰も通さない。",
        "oh good, a wall with opinions. this'll be fun.":
            "やった、意見を言う壁だ。これは楽しくなりそう。",
        "play nice, you two. that's three of us now. the team's coming together. let's go free the rest.":
            "二人とも仲良くね。これで三人。チームが形になってきた。さあ、残りも助けに行こう。",
    ]
}
