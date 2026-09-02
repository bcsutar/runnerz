import SwiftUI
import HealthKit
import WatchKit

private extension Color {
    static let runnerzRed = Color(red: 0.96, green: 0.04, blue: 0.09)
}

private enum SportType: Hashable {
    case running
    case walking

    var icon: String {
        switch self {
        case .running: return "figure.run.treadmill"
        case .walking: return "figure.walk"
        }
    }

    var accent: Color {
        switch self {
        case .running: return .runnerzRed
        case .walking: return .orange
        }
    }

    var glowColors: [Color] {
        switch self {
        case .running:
            return [
                Color(red: 0.96, green: 0.04, blue: 0.09, opacity: 0.55),
                Color(red: 0.75, green: 0.02, blue: 0.05, opacity: 0.2),
                Color(red: 0.75, green: 0.02, blue: 0.05, opacity: 0),
            ]
        case .walking:
            return [
                Color(red: 1, green: 0.45, blue: 0, opacity: 0.55),
                Color(red: 0.82, green: 0.25, blue: 0, opacity: 0.2),
                Color(red: 0.82, green: 0.25, blue: 0, opacity: 0),
            ]
        }
    }

    var activityType: HKWorkoutActivityType {
        switch self {
        case .running: return .running
        case .walking: return .walking
        }
    }

    var startLabel: String {
        switch self {
        case .running: return "Start run"
        case .walking: return "Start walk"
        }
    }

    var name: String {
        switch self {
        case .running: return "Running"
        case .walking: return "Walking"
        }
    }

    var displayName: String {
        switch self {
        case .running: return "Run"
        case .walking: return "Walking"
        }
    }
}

@main
struct RunnerzApp: App {
    @StateObject private var treadmill = FTMSTreadmillManager()
    @StateObject private var workout = WorkoutManager()

    var body: some Scene {
        WindowGroup {
            ContentView(treadmill: treadmill, workout: workout)
        }
    }
}

struct ContentView: View {
    @ObservedObject var treadmill: FTMSTreadmillManager
    @ObservedObject var workout: WorkoutManager
    @State private var showingTreadmills = false
    @State private var showingSettings = false
    @State private var selectedSport: SportType = .running
    @State private var permissionsReady = false
    @AppStorage("autoStartEnabled") private var autoStartEnabled = false

    var body: some View {
        NavigationStack {
            WatchHomeView(treadmill: treadmill,
                          workout: workout,
                          selectedSport: $selectedSport)
                .containerBackground(for: .navigation) {
                    ZStack {
                        Color.black

                        RadialGradient(
                            colors: [
                                glowColors[0], glowColors[1], glowColors[2]
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 145
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 100)
                        .compositingGroup()
                        .blur(radius: 16)
                        .offset(y: 96)
                        .animation(.easeInOut(duration: 0.4), value: selectedSport)
                    }
            }
            .toolbar {
                if !showingTreadmills && !workout.isRunning && workout.review == nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showingTreadmills = true
                        } label: {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                        }
                        .accessibilityLabel("Treadmills")
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingSettings = true
                        } label: {
                            Image(systemName: "gearshape.fill")
                        }
                        .accessibilityLabel("Settings")
                    }
                }
            }
            .toolbar(.hidden, for: .bottomBar)
            .toolbarBackground(.hidden, for: .bottomBar)
            .navigationDestination(isPresented: $showingTreadmills) {
                TreadmillListView(treadmill: treadmill)
            }
            .navigationDestination(isPresented: $showingSettings) {
                SettingsView()
            }
        }
        .task {
            await preparePermissions()
        }
        .task(id: permissionsReady && workout.isRunning) {
            guard permissionsReady && workout.isRunning else { return }
            while !Task.isCancelled && workout.isRunning {
                workout.recordMetrics(speedKph: treadmill.speedKph,
                                      distanceMeters: treadmill.distanceMeters,
                                      inclinePercent: treadmill.inclinePercent)
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .onChange(of: autoStartEnabled) { _, enabled in
            if enabled {
                treadmill.startScanning()
            } else if !workout.isRunning {
                treadmill.stopScanning()
            }
        }
    }

    private var glowColors: [Color] {
        if workout.review == nil { return selectedSport.glowColors }
        return [
            Color(red: 0, green: 0.9, blue: 0.2, opacity: 0.55),
            Color(red: 0, green: 0.7, blue: 0.1, opacity: 0.2),
            Color(red: 0, green: 0.7, blue: 0.1, opacity: 0),
        ]
    }

    private func preparePermissions() async {
        workout.clearStartError()
        let healthReady = await workout.requestAuthorization()
        let bluetoothReady = await treadmill.requestAuthorization()
        if bluetoothReady && autoStartEnabled { treadmill.startScanning() }
        await MainActor.run {
            permissionsReady = healthReady && bluetoothReady
        }
    }

}

struct TreadmillListView: View {
    @ObservedObject var treadmill: FTMSTreadmillManager

    var body: some View {
        List {
            if treadmill.treadmills.isEmpty {
                if treadmill.isScanning {
                    ProgressView("Looking for treadmills")
                        .frame(maxWidth: .infinity)
                } else {
                    ContentUnavailableView {
                        Label("No treadmills found", systemImage: "antenna.radiowaves.left.and.right.slash")
                    } description: {
                        Text("Turn your treadmill off and back on, keep it awake, then scan again.")
                    } actions: {
                        Button("Scan Again") {
                            treadmill.startScanning()
                        }
                    }
                }
            } else {
                ForEach(treadmill.treadmills) { device in
                    Button {
                        treadmill.connect(to: device)
                    } label: {
                        HStack {
                            Image(systemName: "figure.run.treadmill")
                                .foregroundStyle(Color.runnerzRed)
                            Text(device.name)
                            Spacer()
                            if treadmill.connectionText == "Connected" {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }
            }

#if targetEnvironment(simulator)
            Section("Simulator treadmill") {
                Text("Use these controls to test automatic start, pause, and continue.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text("Speed: \(String(format: "%.1f", treadmill.speedKph)) km/h")
                    .font(.caption.monospacedDigit())

                Button("Walk · 3 km/h") {
                    treadmill.setSimulatorSpeed(3)
                }
                Button("Run · 8 km/h") {
                    treadmill.setSimulatorSpeed(8)
                }
                Button("Stop treadmill") {
                    treadmill.setSimulatorSpeed(0)
                }
            }
#endif
        }
        .navigationTitle("Treadmills")
        .onAppear {
            treadmill.startScanning()
        }
        .onDisappear {
            treadmill.stopScanning()
        }
    }
}

private struct WatchHomeView: View {
    @ObservedObject var treadmill: FTMSTreadmillManager
    @ObservedObject var workout: WorkoutManager
    @Binding var selectedSport: SportType
    @AppStorage("autoStartEnabled") private var autoStartEnabled = false
    @AppStorage("autoPauseEnabled") private var autoPauseEnabled = false
    @AppStorage("autoContinueEnabled") private var autoContinueEnabled = false
    @State private var showingStopConfirmation = false
    @State private var showingConnectionLoss = false
    @State private var countdown: Int?
    @State private var countdownTask: Task<Void, Never>?
    @State private var activeWorkoutPage = 0
    @State private var autoStartSince: Date?
    @State private var lowSpeedSince: Date?
    @State private var autoPauseTriggered = false
    @State private var workoutHasMoved = false

    private let autoStartThreshold = 0.5
    private let autoPauseThreshold = 0.3

    private var shouldMonitorAutomation: Bool {
        treadmill.isConnected && (autoStartEnabled || (workout.isRunning && autoPauseEnabled))
    }

    var body: some View {
        ZStack {
            VStack(spacing: 8) {
                if let review = workout.review {
                    WorkoutReviewView(workout: workout, review: review)
                } else if workout.isRunning {
                    TabView(selection: $activeWorkoutPage) {
                        RunningMetricsView(treadmill: treadmill, workout: workout)
                            .tag(0)

                        ActiveWorkoutControlsView(treadmill: treadmill,
                                                  workout: workout,
                                                  showingStopConfirmation: $showingStopConfirmation)
                            .tag(1)
                    }
                    .tabViewStyle(.verticalPage)
                    .scenePadding(.horizontal)
                } else {
                    VStack(spacing: 8) {
                        TabView(selection: $selectedSport) {
                            SportPageView(sport: .running)
                                .tag(SportType.running)

                            SportPageView(sport: .walking)
                                .tag(SportType.walking)
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        .allowsHitTesting(countdown == nil)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        Button { beginStartCountdown() } label: {
                            Image(systemName: "play.fill")
                                .foregroundStyle(.primary)
                                .font(.title2)
                                .frame(width: 56, height: 56)
                        }
                        .buttonStyle(.glass(.regular.interactive()))
                        .buttonBorderShape(.circle)
                        .frame(width: 56, height: 56)
                        .accessibilityLabel(selectedSport.startLabel)
                        .disabled(!treadmill.isConnected || countdown != nil)
                        .offset(y: 10)
                    }
                }
            }

            if let countdown {
                CountdownOverlay(value: countdown, onCancel: cancelStartCountdown)
            }

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scenePadding(.horizontal)
        .onChange(of: treadmill.isConnected) { _, isConnected in
            guard !isConnected else { return }
            cancelStartCountdown()
            guard workout.isRunning else { return }
            if workout.pauseForConnectionLoss() {
                treadmill.pauseTreadmill(paused: true)
            }
            showingConnectionLoss = true
        }
        .onChange(of: treadmill.speedKph) { _, _ in
            guard shouldMonitorAutomation else { return }
            checkAutomaticBehavior()
        }
        .onChange(of: workout.isRunning) { _, isRunning in
            if isRunning {
                activeWorkoutPage = 0
                if treadmill.speedKph > autoStartThreshold {
                    workoutHasMoved = true
                }
            } else {
                autoStartSince = nil
                lowSpeedSince = nil
                autoPauseTriggered = false
                workoutHasMoved = false
            }
        }
        .task(id: shouldMonitorAutomation) {
            guard shouldMonitorAutomation else { return }
            while !Task.isCancelled && shouldMonitorAutomation {
                checkAutomaticBehavior()
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
            }
        }
        .onDisappear {
            cancelStartCountdown()
        }
        .alert("Treadmill Disconnected", isPresented: $showingConnectionLoss) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The workout is paused. Reconnect the treadmill before resuming.")
        }
        .alert("Unable to Start Workout", isPresented: Binding(
            get: { workout.startError != nil },
            set: { isPresented in
                if !isPresented { workout.clearStartError() }
            }
        )) {
            Button("OK", role: .cancel) {
                workout.clearStartError()
            }
        } message: {
            Text(workout.startError ?? "Please try again.")
        }
    }

    private func beginStartCountdown() {
        guard countdown == nil, !workout.isRunning, workout.review == nil, treadmill.isConnected else { return }
        countdownTask?.cancel()
        countdownTask = Task { @MainActor in
            for value in stride(from: 3, through: 1, by: -1) {
                guard !Task.isCancelled else {
                    countdown = nil
                    return
                }
                withAnimation(.easeInOut(duration: 0.2)) {
                    countdown = value
                }
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    countdown = nil
                    return
                }
            }

            guard !Task.isCancelled, treadmill.isConnected else {
                countdown = nil
                return
            }

#if targetEnvironment(simulator)
            treadmill.resetSimulatorTotals()
#endif
            workout.start(activityType: selectedSport.activityType)
            treadmill.startTreadmill()
            countdown = nil
            countdownTask = nil
        }
    }

    private func startAutomatically() {
        guard !workout.isRunning else { return }
#if targetEnvironment(simulator)
        treadmill.resetSimulatorTotals()
#endif
        workout.start(activityType: selectedSport.activityType)
        WKInterfaceDevice.current().play(.start)
    }

    private func cancelStartCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        countdown = nil
    }

    private func checkAutomaticBehavior() {
        let now = Date()
        let speed = treadmill.speedKph

        if workout.isRunning && speed > autoStartThreshold {
            workoutHasMoved = true
        }

        if autoStartEnabled && !workout.isRunning && workout.review == nil && treadmill.isConnected {
            if speed > autoStartThreshold {
                if autoStartSince == nil { autoStartSince = now }
                if now.timeIntervalSince(autoStartSince!) >= 1 {
                    startAutomatically()
                    autoStartSince = nil
                }
            } else {
                autoStartSince = nil
            }
        } else {
            autoStartSince = nil
        }

        if autoPauseEnabled && workout.isRunning && !workout.isPaused && workoutHasMoved {
            if speed < autoPauseThreshold {
                if lowSpeedSince == nil { lowSpeedSince = now }
                if now.timeIntervalSince(lowSpeedSince!) >= 3 && !autoPauseTriggered {
                    autoPauseTriggered = true
                    if workout.pauseForConnectionLoss() {
                        treadmill.pauseTreadmill(paused: true)
                        WKInterfaceDevice.current().play(.stop)
                    }
                }
            } else {
                lowSpeedSince = nil
            }
        } else {
            lowSpeedSince = nil
        }

        if autoPauseTriggered && autoContinueEnabled && workout.isPaused && speed > autoStartThreshold {
            autoPauseTriggered = false
            let willPause = workout.togglePause()
            treadmill.pauseTreadmill(paused: willPause)
            WKInterfaceDevice.current().play(.start)
        }
    }
}

private struct ActiveWorkoutControlsView: View {
    @ObservedObject var treadmill: FTMSTreadmillManager
    @ObservedObject var workout: WorkoutManager
    @Binding var showingStopConfirmation: Bool

    var body: some View {
        VStack(spacing: 10) {
            Spacer()

            Button {
                let willPause = workout.togglePause()
                treadmill.pauseTreadmill(paused: willPause)
            } label: {
                Label(workout.isPaused ? "Resume" : "Pause",
                      systemImage: workout.isPaused ? "play.fill" : "pause.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass(.regular.tint(.yellow).interactive()))
            .tint(.yellow)
            .accessibilityLabel(workout.isPaused ? "Resume" : "Pause")
            .disabled(!treadmill.isConnected)

            Button {
                showingStopConfirmation = true
            } label: {
                Label("Finish", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass(.regular.tint(.green).interactive()))
            .tint(.green)
            .accessibilityLabel("Finish workout")
            .confirmationDialog("Are you sure you want to finish this workout?", isPresented: $showingStopConfirmation) {
                Button("Finish Workout") {
                    treadmill.stopTreadmill()
                    workout.stop(distanceMeters: treadmill.distanceMeters,
                                 inclinePercent: treadmill.inclinePercent)
                }
                Button("Cancel", role: .cancel) {}
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SportPageView: View {
    let sport: SportType

    var body: some View {
        VStack(spacing: 8) {
            Spacer()

            VStack(spacing: 5) {
                Image(systemName: sport.icon)
                    .font(.system(size: 39.2, weight: .medium))
                    .foregroundStyle(sport.accent)

                Text(sport.displayName)
                    .font(.caption.weight(.semibold))
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CountdownOverlay: View {
    let value: Int
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Text("GET READY")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.system(size: 52, weight: .black, design: .rounded))
                .contentTransition(.numericText())
            Button("Cancel", action: onCancel)
                .buttonStyle(.glass(.regular.interactive()))
                .buttonBorderShape(.capsule)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .transition(.scale.combined(with: .opacity))
    }
}

private struct SettingsView: View {
    @AppStorage("autoStartEnabled") private var autoStartEnabled = false
    @AppStorage("autoPauseEnabled") private var autoPauseEnabled = false
    @AppStorage("autoContinueEnabled") private var autoContinueEnabled = false

    var body: some View {
        List {
            Section("Automatic Start") {
                Toggle("Auto Start", isOn: $autoStartEnabled)
                Text("Auto Start begins the selected sport when the treadmill is moving. Swipe on the home screen before starting to choose Running or Walking.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Automatic Pause") {
                Toggle("Auto Pause", isOn: $autoPauseEnabled)
                Toggle("Auto Continue", isOn: $autoContinueEnabled)
                    .disabled(!autoPauseEnabled)
                Text("Auto Pause pauses with haptic feedback when movement stops. Auto Continue resumes with haptic feedback when movement returns.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
    }
}

private struct WorkoutReviewView: View {
    @ObservedObject var workout: WorkoutManager
    let review: WorkoutManager.WorkoutReview
    @State private var showingSaveConfirmation = false
    @State private var showingTrashConfirmation = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                WorkoutMetricRow(icon: "clock.fill",
                                 title: "TIME",
                                 value: review.elapsedText,
                                 color: .green)
                WorkoutMetricRow(icon: "figure.run",
                                 title: "DISTANCE",
                                 value: "\(String(format: "%.1f", review.distanceMeters / 1000)) km",
                                 color: .green)
                WorkoutMetricRow(icon: "speedometer",
                                 title: "AVG PACE",
                                 value: averagePaceText,
                                 color: .green)
                WorkoutMetricRow(icon: "flame.fill",
                                 title: "CALORIES",
                                 value: review.caloriesKcal > 0 ? "\(String(format: "%.0f", review.caloriesKcal)) kcal" : "-- kcal",
                                 color: .orange)
                WorkoutMetricRow(icon: "heart.fill",
                                 title: "AVG HEART RATE",
                                 value: review.averageHeartRate > 0 ? "\(review.averageHeartRate) BPM" : "-- BPM",
                                 color: Color.runnerzRed)
                WorkoutMetricRow(icon: "arrow.up.heart.fill",
                                 title: "MAX HEART RATE",
                                 value: review.maxHeartRate > 0 ? "\(review.maxHeartRate) BPM" : "-- BPM",
                                 color: Color.runnerzRed)

                VStack(spacing: 8) {
                    Button {
                        showingSaveConfirmation = true
                    } label: {
                        if workout.isSaving {
                            ProgressView()
                                .accessibilityLabel("Saving workout")
                        } else {
                            Label("Save", systemImage: "checkmark")
                        }
                    }
                    .buttonStyle(.glass(.regular.tint(.green).interactive()))
                    .tint(.green)
                    .disabled(workout.isSaving)

                    Button(role: .destructive) {
                        showingTrashConfirmation = true
                    } label: {
                        Label("Trash", systemImage: "trash")
                    }
                    .disabled(workout.isSaving)
                }

                if let saveError = workout.saveError {
                    Text(saveError)
                        .font(.caption2)
                        .foregroundStyle(Color.runnerzRed)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .safeAreaPadding(.vertical, 8)
        .navigationTitle("Workout Complete")
        .toolbarTitleDisplayMode(.inline)
        .alert(item: Binding(
            get: { workout.saveResult },
            set: { result in
                if result == nil { workout.dismissSaveResult() }
            }
        )) { result in
            switch result {
            case .success:
                return Alert(
                    title: Text("Workout Saved"),
                    message: Text("Saved to Apple Health."),
                    dismissButton: .default(Text("Done"))
                )
            case .failure(let message):
                return Alert(
                    title: Text("Save Failed"),
                    message: Text(message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
        .confirmationDialog("Save this workout to Health?", isPresented: $showingSaveConfirmation) {
            Button("Save") {
                workout.saveReviewedWorkout()
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Trash this workout?", isPresented: $showingTrashConfirmation) {
            Button("Trash", role: .destructive) {
                workout.discardReviewedWorkout()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var averagePaceText: String {
        let components = review.elapsedText.split(separator: ":")
        guard components.count == 2,
              let minutes = Int(components[0]),
              let seconds = Int(components[1]),
              review.distanceMeters > 0 else {
            return "--'--\""
        }

        let distanceKilometers = review.distanceMeters / 1000
        let secondsPerKilometer = Double(minutes * 60 + seconds) / distanceKilometers
        guard secondsPerKilometer.isFinite else { return "--'--\"" }
        let roundedSeconds = Int(secondsPerKilometer.rounded())
        return String(format: "%d'%02d\"", roundedSeconds / 60, roundedSeconds % 60)
    }
}

private struct WorkoutMetricRow: View {
    let icon: String
    let title: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title3.monospacedDigit().weight(.semibold))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct RunningMetricsView: View {
    @ObservedObject var treadmill: FTMSTreadmillManager
    @ObservedObject var workout: WorkoutManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(Color.runnerzRed)
                Text(workout.heartRate > 0 ? "\(workout.heartRate) BPM" : "-- BPM")
            }
            .font(.headline.monospacedDigit())

            ActiveMetric(title: "TIME", value: workout.elapsedText, prominent: true)
            ActiveMetric(title: "PACE", value: currentPaceText)
            ActiveMetric(title: "DISTANCE",
                         value: "\(String(format: "%.1f", treadmill.distanceMeters / 1000)) km")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var currentPaceText: String {
        guard treadmill.speedKph > 0 else { return "--'--\"" }
        let secondsPerKilometer = 3600 / treadmill.speedKph
        let roundedSeconds = Int(secondsPerKilometer.rounded())
        return String(format: "%d'%02d\"", roundedSeconds / 60, roundedSeconds % 60)
    }
}

private struct ActiveMetric: View {
    let title: String
    let value: String
    var prominent = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(value)
                .font((prominent ? Font.title : Font.title3).monospacedDigit().weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}
