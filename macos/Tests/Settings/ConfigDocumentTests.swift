import Testing
@testable import Ghostty

@Suite
struct ConfigDocumentTests {
    // MARK: Parsing

    @Test func parsesEntriesUsingGhosttyRules() {
        let doc = ConfigDocument(contents: """
            # A comment
              font-size   =   14
            font-family = "Fira Code"
            background=#282c34
            keybind = ctrl+a=new_tab
            not an entry
            """)

        #expect(doc.value(for: "font-size") == "14")
        #expect(doc.value(for: "font-family") == "Fira Code")
        #expect(doc.value(for: "background") == "#282c34")
        #expect(doc.value(for: "keybind") == "ctrl+a=new_tab")
        #expect(doc.value(for: "missing") == nil)
    }

    @Test func lastValueWins() {
        let doc = ConfigDocument(contents: "font-size = 12\nfont-size = 16\n")
        #expect(doc.value(for: "font-size") == "16")
        #expect(doc.values(for: "font-size") == ["12", "16"])
    }

    @Test func roundTripsUntouchedContent() {
        let contents = "# header\n\nfont-size=13\n  theme = Dracula  \n# trailing"
        #expect(ConfigDocument(contents: contents).contents == contents)
        #expect(ConfigDocument(contents: contents + "\n").contents == contents + "\n")
        #expect(ConfigDocument(contents: "").contents == "")
    }

    // MARK: Editing

    @Test func setUpdatesLastEntryInPlace() {
        var doc = ConfigDocument(contents: "# size\nfont-size = 12\ntheme = Dracula\n")
        doc.set("font-size", to: "15")
        #expect(doc.contents == "# size\nfont-size = 15\ntheme = Dracula\n")
    }

    @Test func setAppendsMissingKey() {
        var doc = ConfigDocument(contents: "term=xterm-256color")
        doc.set("font-size", to: "15")
        #expect(doc.contents == "term=xterm-256color\nfont-size = 15\n")

        var empty = ConfigDocument(contents: "")
        empty.set("theme", to: "Dracula")
        #expect(empty.contents == "theme = Dracula\n")
    }

    @Test func removeDeletesAllEntries() {
        var doc = ConfigDocument(contents: "font-size = 12\ntheme = x\nfont-size = 16\n")
        doc.remove("font-size")
        #expect(doc.contents == "theme = x\n")
    }

    @Test func quotesValuesThatNeedIt() {
        var doc = ConfigDocument()
        doc.set("a", to: " padded ")
        doc.set("b", to: "\"quoted\"")
        doc.set("c", to: "plain value")
        #expect(doc.contents == "a = \" padded \"\nb = \"\"quoted\"\"\nc = plain value\n")

        let reparsed = ConfigDocument(contents: doc.contents)
        #expect(reparsed.value(for: "a") == " padded ")
        #expect(reparsed.value(for: "b") == "\"quoted\"")
        #expect(reparsed.value(for: "c") == "plain value")
    }

    @Test func aliasesAreTreatedAsTheCanonicalKey() {
        var doc = ConfigDocument(contents: "scrollback-limit = 1000\n")
        #expect(doc.value(for: "scrollback-limit-bytes") == "1000")

        doc.set("scrollback-limit-bytes", to: "2000")
        #expect(doc.contents == "scrollback-limit-bytes = 2000\n")
    }

    @Test func setValuesReplacesRepeatableKey() {
        var doc = ConfigDocument(contents: "font-family = A\ntheme = x\nfont-family = B\n")
        doc.setValues("font-family", ["C", "D"])
        #expect(doc.contents == "font-family = C\nfont-family = D\ntheme = x\n")
    }

    @Test func removeValuesMatchingPredicate() {
        var doc = ConfigDocument(contents: "font-feature = -calt\nfont-feature = ss01\nfont-feature = -liga\n")
        doc.removeValues(for: "font-feature") { $0.hasPrefix("-") }
        #expect(doc.values(for: "font-feature") == ["ss01"])
    }

    // MARK: Palette

    @Test func paletteOverrides() {
        var doc = ConfigDocument(contents: "palette = 0=#000000\npalette = 1 = #ff0000\nfont-size = 12\n")
        #expect(doc.paletteValue(at: 1) == "#ff0000")
        #expect(doc.paletteValue(at: 2) == nil)

        doc.setPalette(1, to: "#00ff00")
        doc.setPalette(4, to: "#0000ff")
        #expect(doc.contents == "palette = 0=#000000\npalette = 1=#00ff00\npalette = 4=#0000ff\nfont-size = 12\n")

        doc.setPalette(0, to: nil)
        #expect(doc.paletteValue(at: 0) == nil)
        #expect(doc.values(for: "palette") == ["1=#00ff00", "4=#0000ff"])
    }

    // MARK: Keybinds

    @Test func parsesKeybinds() throws {
        let simple = try #require(Keybind("super+shift+t=new_tab"))
        #expect(simple.trigger == "super+shift+t")
        #expect(simple.action == "new_tab")
        #expect(simple.flags.isEmpty)

        let flagged = try #require(Keybind("global:unconsumed:ctrl+grave_accent=toggle_quick_terminal"))
        #expect(flagged.flags == ["global", "unconsumed"])
        #expect(flagged.trigger == "ctrl+grave_accent")
        #expect(flagged.configValue == "global:unconsumed:ctrl+grave_accent=toggle_quick_terminal")

        let equal = try #require(Keybind("ctrl+==ignore"))
        #expect(equal.trigger == "ctrl+=")
        #expect(equal.action == "ignore")

        let textAction = try #require(Keybind("ctrl+a=text:a=b"))
        #expect(textAction.trigger == "ctrl+a")
        #expect(textAction.action == "text:a=b")

        #expect(Keybind("clear") == nil)
    }

    @Test func formatsTriggersForDisplay() {
        #expect(GhosttyTrigger.displayString("super+shift+t") == "⇧⌘T")
        #expect(GhosttyTrigger.displayString("ctrl+a>n") == "⌃A N")
        #expect(GhosttyTrigger.displayString("alt+arrow_left") == "⌥←")
        #expect(GhosttyTrigger.displayString("ctrl+=") == "⌃=")
    }

    // MARK: Themes

    @Test func parsesThemeSelection() throws {
        let single = try #require(ThemeLibrary.Selection("Dracula"))
        #expect(!single.isPair)
        #expect(single.configValue == "Dracula")

        let pair = try #require(ThemeLibrary.Selection("light:Catppuccin Latte,dark:Catppuccin Mocha"))
        #expect(pair.isPair)
        #expect(pair.light == "Catppuccin Latte")
        #expect(pair.dark == "Catppuccin Mocha")
        #expect(pair.configValue == "light:Catppuccin Latte,dark:Catppuccin Mocha")

        #expect(ThemeLibrary.Selection("") == nil)
    }

    @Test func parsesThemeColors() {
        let colors = ThemeColors(themeFile: """
            palette = 1=#ff0000
            background = #101010
            foreground = #eeeeee
            cursor-color = #ffcc00
            """)
        #expect(colors.background == "#101010")
        #expect(colors.foreground == "#eeeeee")
        #expect(colors.cursor == "#ffcc00")
        #expect(colors.palette[1] == "#ff0000")
        #expect(colors.palette[2] == ThemeColors.ghosttyDefault.palette[2])
        #expect(colors.isDark)
    }

    // MARK: Integration with the core

    /// Edits made by the settings model must load correctly in Ghostty.
    @Test func editsLoadInGhostty() throws {
        var doc = ConfigDocument(contents: "# my config\nfont-size = 12\n")
        doc.set("font-size", to: "15.5")
        doc.set("background", to: "#123456")
        doc.set("cursor-style-blink", to: "false")
        doc.set("shell-integration-features", to: "no-cursor,sudo,title,no-ssh-env,no-ssh-terminfo,path")
        doc.setPalette(3, to: "#abcdef")
        doc.set("window-padding-balance", to: "equal")

        let config = try TemporaryConfig(doc.contents)
        #expect(config.errors.isEmpty)
        #expect(config.settingsFloat("font-size") == 15.5)
        #expect(config.settingsColor("background") == "#123456")
        #expect(config.settingsBool("cursor-style-blink") == false)
        #expect(config.settingsPalette?[3] == "#abcdef")
        #expect(config.settingsString("window-padding-balance") == "equal")

        // cursor=bit0, sudo=bit1, title=bit2, ssh-env=bit3, ssh-terminfo=bit4, path=bit5
        #expect(config.settingsBits("shell-integration-features") == 0b100110)
    }

    @Test func unsetOptionalValuesReadAsNil() throws {
        let config = try TemporaryConfig("")
        #expect(config.settingsBool("cursor-style-blink") == nil)
        #expect(config.settingsString("macos-option-as-alt") == nil)
        #expect(config.settingsString("window-save-state") == "default")
        #expect(config.settingsDouble("background-opacity") == 1)
    }
}
