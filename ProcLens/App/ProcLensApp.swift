import SwiftUI
import AppKit

enum AppTheme: String, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

@main
struct ProcLensApp: App {
    @State private var processManager = ProcessManager()
    @State private var systemMonitor = SystemMonitor()
    @AppStorage("appTheme") private var theme: String = AppTheme.system.rawValue

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(processManager)
                .environment(systemMonitor)
                .onAppear {
                    applyTheme()
                    UserDefaults.standard.set(5000, forKey: "NSInitialToolTipDelay")
                }
                .onChange(of: theme) { _, _ in applyTheme() }
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandMenu("Theme") {
                ForEach(AppTheme.allCases, id: \.self) { t in
                    Button(t.rawValue) { theme = t.rawValue }
                }
            }
        }

        Settings {
            SettingsView(theme: $theme)
                .environment(processManager)
        }
    }

    private func applyTheme() {
        NSApp.appearance = (AppTheme(rawValue: theme) ?? .system).appearance
    }
}

struct SettingsView: View {
    @Environment(ProcessManager.self) private var processManager
    @Binding var theme: String

    var body: some View {
        Form {
            Picker("Refresh Interval", selection: Bindable(processManager).refreshInterval) {
                Text("1 second").tag(1.0 as TimeInterval)
                Text("2 seconds").tag(2.0 as TimeInterval)
                Text("5 seconds").tag(5.0 as TimeInterval)
                Text("10 seconds").tag(10.0 as TimeInterval)
            }

            Picker("Theme", selection: $theme) {
                ForEach(AppTheme.allCases, id: \.self) { t in
                    Text(t.rawValue).tag(t.rawValue)
                }
            }
        }
        .padding()
        .frame(width: 350, height: 150)
    }
}
