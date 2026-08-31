import SwiftUI

private extension Color {
    static let runnerzRed = Color(red: 0.96, green: 0.04, blue: 0.09)
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

    var body: some View {
        NavigationStack {
            WatchHomeView(treadmill: treadmill, workout: workout)
                .containerBackground(for: .navigation) {
                    ZStack {
                        Color.black

                        RadialGradient(
                            colors: [
                                workout.review == nil
                                    ? Color.runnerzRed.opacity(0.55)
                                    : Color(red: 0, green: 0.9, blue: 0.2, opacity: 0.55),
                                workout.review == nil
                                    ? Color.runnerzRed.opacity(0.2)
                                    : Color(red: 0, green: 0.7, blue: 0.1, opacity: 0.2),
                                .clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 145
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 100)
                        .blur(radius: 16)
                        .offset(y: 96)
                    }
            }
            .toolbar {
                if !showingTreadmills && !workout.isRunning && workout.review == nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingTreadmills = true
                        } label: {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                        }
                        .accessibilityLabel("Treadmills")
                    }
                }
            }
            .toolbar(.hidden, for: .bottomBar)
            .toolbarBackground(.hidden, for: .bottomBar)
            .navigationDestination(isPresented: $showingTreadmills) {
                TreadmillListView(treadmill: treadmill)
            }
        }
        .task {
            treadmill.startScanning()
            while !Task.isCancelled {
                workout.recordMetrics(speedKph: treadmill.speedKph,
                                      distanceMeters: treadmill.distanceMeters,
                                      caloriesKcal: treadmill.caloriesKcal)
                try? await Task.sleep(for: .seconds(1))
            }
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
    @State private var showingStopConfirmation = false
    @State private var showingConnectionLoss = false

    var body: some View {
        VStack(spacing: 8) {
            if let review = workout.review {
                WorkoutReviewView(workout: workout, review: review)
            } else if workout.isRunning {
                Spacer()

                VStack(spacing: 16) {
                    RunningMetricsView(treadmill: treadmill, workout: workout)

                    HStack {
                        Button {
                            workout.togglePause()
                            treadmill.pauseTreadmill(paused: workout.isPaused)
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
                Spacer()

                VStack(spacing: 5) {
                    Image(systemName: "figure.run.treadmill")
                        .font(.system(size: 49, weight: .medium))
                        .foregroundStyle(Color.runnerzRed)

                    Text(treadmill.isConnected ? "Ready" : "Connect treadmill")
                        .font(.caption.weight(.semibold))
                }

                Spacer()

                Button {
                    Task {
                        workout.clearStartError()
                        guard await workout.requestAuthorization() else { return }
                        await MainActor.run {
                            guard treadmill.isConnected else {
                                showingConnectionLoss = true
                                return
                            }
                            workout.start()
                            treadmill.startTreadmill()
                        }
                    }
                } label: {
                    Image(systemName: "play.fill")
                        .foregroundStyle(Color.runnerzRed)
                        .font(.title2)
                        .frame(width: 56, height: 56)
                }
                .buttonStyle(.glass(.regular.tint(Color.runnerzRed).interactive()))
                .buttonBorderShape(.circle)
                .frame(width: 56, height: 56)
                .tint(Color.runnerzRed)
                .accessibilityLabel("Start run")
                .disabled(!treadmill.isConnected)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scenePadding(.horizontal)
        .onChange(of: treadmill.isConnected) { _, isConnected in
            guard !isConnected, workout.isRunning else { return }
            workout.pauseForConnectionLoss()
            showingConnectionLoss = true
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
