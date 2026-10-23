import SwiftUI

@main
struct FocusLiftApp: App {
    @State private var store: AppStore
    @State private var music: MusicPlayer
    @State private var blocker: AppBlocker
    @State private var engine: WorkoutEngine

    init() {
        let store = AppStore()
        let music = MusicPlayer()
        let blocker = AppBlocker()
        let engine = WorkoutEngine(store: store, music: music, blocker: blocker, audio: AudioController(), speaker: Speaker())
        _store = State(initialValue: store)
        _music = State(initialValue: music)
        _blocker = State(initialValue: blocker)
        _engine = State(initialValue: engine)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(music)
                .environment(blocker)
                .environment(engine)
                .preferredColorScheme(.dark)
                .dismissesKeyboardOnTap()
        }
    }
}

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(MusicPlayer.self) private var music
    @Environment(WorkoutEngine.self) private var engine
    @Environment(\.scenePhase) private var scenePhase
    @State private var showWorkout = false
    @State private var summary: Workout?

    var body: some View {
        TabView {
            RoutinesView(showWorkout: $showWorkout)
                .tabItem { Label("Train", systemImage: "dumbbell") }
            HistoryView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .fullScreenCover(isPresented: $showWorkout) {
            ActiveWorkoutView { finished in
                // Let the full-screen cover finish dismissing before presenting the summary.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { summary = finished }
            }
            .environment(store)
            .environment(music)
            .environment(engine)
        }
        .sheet(item: $summary) { workout in
            NavigationStack {
                WorkoutSummaryView(workout: workout, isSheet: true)
            }
            .environment(store)
        }
        .onAppear {
            if store.activeWorkout != nil { showWorkout = true }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { store.save() }
        }
    }
}
