import SwiftUI
import CoreText

@main
struct MitoV3App: App {
    init() {
        FontRegistrar.registerFonts()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

private enum FontRegistrar {
    static func registerFonts() {
        ["PixelifySans", "Silkscreen-Regular", "Silkscreen-Bold"].forEach { name in
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else {
                return
            }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
