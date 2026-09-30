import SwiftUI
import SwiftData
import WidgetKit

@main
struct GastosApp: App {
    let container: ModelContainer = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uiTesting") {
            return try! Store.inMemory()
        }
        if ProcessInfo.processInfo.arguments.contains("-sampleData") {
            let container = try! Store.inMemory()
            SampleData.insert(into: container.mainContext)
            AppGroup.defaults.set(true, forKey: SettingsKey.hasOnboarded)
            return container
        }
        #endif
        do {
            return try Store.container()
        } catch {
            fatalError("Could not open the gastos store: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentGate()
        }
        .modelContainer(container)
        .defaultAppStorage(AppGroup.defaults)
    }
}

/// Decides between onboarding and the app, and keeps the app lock in front when needed.
struct ContentGate: View {
    @AppStorage(SettingsKey.hasOnboarded) private var hasOnboarded = false
    @AppStorage(SettingsKey.appLock) private var appLockOn = false
    @State private var locked = AppGroup.defaults.bool(forKey: SettingsKey.appLock)
    @State private var authenticating = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context

    var body: some View {
        ZStack {
            if hasOnboarded {
                RootView()
            } else {
                OnboardingView()
            }
            // Also covers the app switcher snapshot while inactive.
            if appLockOn && (locked || scenePhase != .active) {
                LockView(showsButton: locked, unlock: unlock)
                    .transition(.opacity)
            }
        }
        .tint(.brand)
        .task {
            Seed.categoriesIfNeeded(in: context)
            RecurringPoster.postDue(in: context)
            if !ProcessInfo.processInfo.arguments.contains("-uiTesting") {
                SyncService.shared.start(container: context.container)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                if appLockOn { locked = true }
                try? context.save()
                WidgetCenter.shared.reloadAllTimelines()
                // iOS suspends the app about a second after backgrounding; ask for time to finish the upload.
                let task = UIApplication.shared.beginBackgroundTask(withName: "sync")
                Task {
                    await SyncService.shared.sync()
                    UIApplication.shared.endBackgroundTask(task)
                }
            case .active:
                RecurringPoster.postDue(in: context)
                SyncCleanup.run(in: context)
                Task { await SyncService.shared.sync() }
                if locked { unlock() }
            default:
                break
            }
        }
        .onChange(of: appLockOn) { _, on in if !on { locked = false } }
    }

    private func unlock() {
        guard !authenticating else { return }
        authenticating = true
        Task {
            if await AppLock.authenticate() {
                withAnimation { locked = false }
            }
            authenticating = false
        }
    }
}

struct LockView: View {
    var showsButton: Bool
    var unlock: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            LogoSphere(size: 140)
            Text("gastos is locked").font(.title3.weight(.semibold)).foregroundStyle(Color.ink)
            Spacer()
            if showsButton {
                Button("Unlock", action: unlock)
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, 40)
                    .padding(.bottom, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.canvas.ignoresSafeArea())
    }
}
