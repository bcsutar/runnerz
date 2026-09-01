import SwiftUI
import HealthKit

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
                                workout.review == nil
                                    ? selectedSport.accent.opacity(0.55)
                                    : Color(red: 0, green: 0.9, blue: 0.2, opacity: 0.55),
                                workout.review == nil
                                    ? selectedSport.accent.opacity(0.2)
                                    : Color(red: 0, green: 0.7, blue: 0.1, opacity: 0.2),
                                workout.review == nil
                                    ? selectedSport.accent.opacity(0)
                                    : Color(red: 0, green: 0.7, blue: 0.1, opacity: 0),
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
        .task(id: permissionsReady) {
            guard permissionsReady else { return }
            while !Task.isCancelled {
                workout.recordMetrics(speedKph: treadmill.speedKph,
                                      distanceMeters: treadmill.distanceMeters,
                                      caloriesKcal: treadmill.caloriesKcal)
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func preparePermissions() async {
        workout.clearStartError()
        let healthReady = await workout.requestAuthorization()
        let bluetoothReady = await treadmill.requestAuthorization()
        if bluetoothReady { treadmill.startScanning() }
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
                ContentUnavailableView {
                    Label("No treadmills found", systemImage: "antenna.radiowaves.left.and.right.slash")
                } description: {
                    Text("Keep your treadmill awake, then scan again.")
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
        }
        .navigationTitle("Treadmills")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    treadmill.startScanning()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Scan again")
            }
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
    @State private var countdownIsAutomatic = false
    @State private var autoStartSince: Date?
    @State private var lowSpeedSince: Date?
    @State private var autoPauseTriggered = false
    @State private var workoutHasMoved = false

    private let autoStartThreshold = 0.5
    private let autoPauseThreshold = 0.3

    var body: some View {
        ZStack {
            VStack(spacing: 8) {
                if let review = workout.review {
                    WorkoutReviewView(workout: workout, review: review)
                } else if workout.isRunning {
                    Spacer()

                    VStack(spacing: 16) {
                        RunningMetricsView(treadmill: treadmill, workout: workout)

                        HStack {
                            Button {
                                let willPause = workout.togglePause()
                                treadmill.pauseTreadmill(paused: willPause)
                            } label: {
                                Image(systemName: workout.isPaused ? "play.fill" : "pause.fill")
                                    .foregroundStyle(.yellow)
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.glass(.regular.tint(.yellow).interactive()))
                            .buttonBorderShape(.circle)
                            .tint(.yellow)
                            .accessibilityLabel(workout.isPaused ? "Resume" : "Pause")
                            .disabled(!treadmill.isConnected)

                            Button(role: .destructive) {
                                showingStopConfirmation = true
                            } label: {
                                Image(systemName: "xmark")
                                    .foregroundStyle(Color.runnerzRed)
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.glass(.regular.tint(Color.runnerzRed).interactive()))
                            .buttonBorderShape(.circle)
                            .tint(Color.runnerzRed)
                            .accessibilityLabel("Stop")
                            .confirmationDialog("Stop this workout?", isPresented: $showingStopConfirmation) {
                                Button("Stop Workout", role: .destructive) {
                                    treadmill.stopTreadmill()
                                    workout.stop(distanceMeters: treadmill.distanceMeters,
                                                 caloriesKcal: treadmill.caloriesKcal)
                                }
                                Button("Cancel", role: .cancel) {}
                            }
                        }
                    }

                    Spacer()
                } else {
                    VStack(spacing: 8) {
                        TabView(selection: $selectedSport) {
                            SportPageView(sport: .running, treadmill: treadmill)
                                .tag(SportType.running)

                            SportPageView(sport: .walking, treadmill: treadmill)
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
                CountdownOverlay(value: countdown)
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
            checkAutomaticBehavior()
        }
        .onChange(of: workout.isRunning) { _, isRunning in
            if !isRunning {
                autoStartSince = nil
                lowSpeedSince = nil
                autoPauseTriggered = false
                workoutHasMoved = false
            } else if treadmill.speedKph > autoStartThreshold {
                workoutHasMoved = true
            }
        }
        .task {
            while !Task.isCancelled {
                checkAutomaticBehavior()
                try? await Task.sleep(for: .seconds(1))
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

    private func beginStartCountdown(automatic: Bool = false) {
        guard countdown == nil, !workout.isRunning, workout.review == nil, treadmill.isConnected else { return }
        countdownIsAutomatic = automatic
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

            workout.start(activityType: selectedSport.activityType)
            if !countdownIsAutomatic { treadmill.startTreadmill() }
            countdown = nil
            countdownIsAutomatic = false
            countdownTask = nil
        }
    }

    private func cancelStartCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        countdown = nil
        countdownIsAutomatic = false
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
                    beginStartCountdown(automatic: true)
                    autoStartSince = nil
                }
            } else {
                autoStartSince = nil
                if countdownIsAutomatic { cancelStartCountdown() }
            }
        } else {
            autoStartSince = nil
            if countdownIsAutomatic { cancelStartCountdown() }
        }

        if autoPauseEnabled && workout.isRunning && !workout.isPaused && workoutHasMoved {
            if speed < autoPauseThreshold {
                if lowSpeedSince == nil { lowSpeedSince = now }
                if now.timeIntervalSince(lowSpeedSince!) >= 3 && !autoPauseTriggered {
                    autoPauseTriggered = true
                    if workout.pauseForConnectionLoss() {
                        treadmill.pauseTreadmill(paused: true)
                        showingStopConfirmation = true
                    }
                }
            } else {
                lowSpeedSince = nil
            }
        } else {
            lowSpeedSince = nil
        }

        if autoPauseTriggered && autoContinueEnabled && workout.isPaused && speed > autoStartThreshold {
            showingStopConfirmation = false
            autoPauseTriggered = false
            let willPause = workout.togglePause()
            treadmill.pauseTreadmill(paused: willPause)
        }
    }
}

private struct SportPageView: View {
    let sport: SportType
    @ObservedObject var treadmill: FTMSTreadmillManager

    var body: some View {
        VStack(spacing: 8) {
            Spacer()

            VStack(spacing: 5) {
                Image(systemName: sport.icon)
                    .font(.system(size: 39.2, weight: .medium))
                    .foregroundStyle(sport.accent)

                Text(treadmill.isConnected ? "Ready" : "Connect treadmill")
                    .font(.caption.weight(.semibold))
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CountdownOverlay: View {
    let value: Int

    var body: some View {
        VStack(spacing: 6) {
            Text("GET READY")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.system(size: 52, weight: .black, design: .rounded))
                .contentTransition(.numericText())
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
            Section {
                Toggle("Auto Start", isOn: $autoStartEnabled)
                Toggle("Auto Pause", isOn: $autoPauseEnabled)
                Toggle("Auto Continue", isOn: $autoContinueEnabled)
                    .disabled(!autoPauseEnabled)
            } footer: {
                Text("Auto Start begins a workout when the connected treadmill is moving. Auto Pause pauses the workout after the treadmill stops and asks whether to stop it. Auto Continue resumes an automatic pause when movement returns.")
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
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)

                WorkoutMetricRow(icon: "clock.fill",
                                 title: "TIME",
                                 value: review.elapsedText,
                                 color: .green)
                WorkoutMetricRow(icon: "figure.run",
                                 title: "DISTANCE",
                                 value: "\(String(format: "%.1f", review.distanceMeters / 1000)) km",
                                 color: .green)
                WorkoutMetricRow(icon: "flame.fill",
                                 title: "CALORIES",
                                 value: review.caloriesKcal > 0 ? "\(String(format: "%.0f", review.caloriesKcal)) kcal" : "-- kcal",
                                 color: .orange)
                WorkoutMetricRow(icon: "heart.fill",
                                 title: "AVG HEART RATE",
                                 value: review.averageHeartRate > 0 ? "\(review.averageHeartRate) BPM" : "-- BPM",
                                 color: Color.runnerzRed)

                VStack(spacing: 8) {
                    Button {
                        showingSaveConfirmation = true
                    } label: {
                        if workout.isSaving {
                            ProgressView()
                                .accessibilityLabel("Saving workout")
                        } else {
                            Text("Save Workout")
                        }
                    }
                    .buttonStyle(.glass(.regular.tint(.green).interactive()))
                    .tint(.green)
                    .disabled(workout.isSaving)

                    Button("Trash Workout", role: .destructive) {
                        showingTrashConfirmation = true
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
            Button("Save Workout") {
                workout.saveReviewedWorkout()
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Trash this workout?", isPresented: $showingTrashConfirmation) {
            Button("Trash Workout", role: .destructive) {
                workout.discardReviewedWorkout()
            }
            Button("Cancel", role: .cancel) {}
        }
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
        VStack(spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(Color.runnerzRed)
                Text(workout.heartRate > 0 ? "\(workout.heartRate) BPM" : "-- BPM")
            }
            .font(.headline.monospacedDigit())
            Text("\(String(format: "%.1f", treadmill.speedKph)) km/h  •  \(workout.elapsedText)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}
