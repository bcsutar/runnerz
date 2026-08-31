import Foundation
import HealthKit

final class WorkoutManager: NSObject, ObservableObject {
    enum SaveResult: Identifiable {
        case success
        case failure(String)

        var id: String {
            switch self {
            case .success: return "success"
            case .failure: return "failure"
            }
        }
    }

    struct WorkoutReview {
        let averageHeartRate: Int
        let elapsedText: String
        let distanceMeters: Double
        let caloriesKcal: Double
    }

    @Published private(set) var heartRate = 0
    @Published private(set) var isRunning = false
    @Published private(set) var isPaused = false
    @Published private(set) var elapsedText = "00:00"
    @Published private(set) var review: WorkoutReview?
    @Published private(set) var isSaving = false
    @Published private(set) var saveError: String?
    @Published private(set) var saveResult: SaveResult?
    @Published private(set) var startError: String?

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var timer: Timer?
    private var startedAt: Date?
    private var lastMetricDate = Date()

    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else {
            await MainActor.run { self.startError = "Health data is unavailable on this watch." }
            return false
        }
        let workoutType = HKObjectType.workoutType()
        let share: Set<HKSampleType> = [workoutType, .quantityType(forIdentifier: .distanceWalkingRunning)!, .quantityType(forIdentifier: .activeEnergyBurned)!]
        let read: Set<HKObjectType> = [
            workoutType,
            .quantityType(forIdentifier: .heartRate)!,
            .quantityType(forIdentifier: .distanceWalkingRunning)!,
            .quantityType(forIdentifier: .activeEnergyBurned)!
        ]
        do {
            try await healthStore.requestAuthorization(toShare: share, read: read)
            guard healthStore.authorizationStatus(for: workoutType) == .sharingAuthorized else {
                await MainActor.run {
                    self.startError = "Allow Runnerz to write workouts in Health, then try again."
                }
                return false
            }
            return true
        } catch {
            await MainActor.run { self.startError = error.localizedDescription }
            return false
        }
    }

    func clearStartError() {
        startError = nil
    }

    func start() {
        guard !isRunning else { return }
        review = nil
        saveError = nil
        heartRate = 0
        elapsedText = "00:00"
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .running
        configuration.locationType = .indoor
        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            session.delegate = self
            builder.delegate = self
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
            self.session = session
            self.builder = builder
            startedAt = Date()
            lastMetricDate = startedAt!
            isRunning = true
            session.startActivity(with: startedAt!)
            builder.beginCollection(withStart: startedAt!) { [weak self] _, error in
                guard let error else { return }
                DispatchQueue.main.async {
                    self?.failStart(with: error)
                }
            }
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.updateElapsed() }
        } catch {
            failStart(with: error)
        }
    }

    func togglePause() {
        guard let session, isRunning else { return }
        if isPaused { session.resume() } else { session.pause() }
    }

    func pauseForConnectionLoss() {
        guard let session, isRunning, !isPaused else { return }
        session.pause()
        isPaused = true
    }

    func stop(distanceMeters: Double, caloriesKcal: Double) {
        guard let session, let builder, isRunning else { return }
        let endDate = Date()
        addFinalMetrics(to: builder,
                        distanceMeters: distanceMeters,
                        caloriesKcal: caloriesKcal,
                        endDate: endDate) { [weak self] error in
            guard let self else { return }
            if let error {
                DispatchQueue.main.async { self.failStart(with: error) }
                return
            }

            session.end()
            builder.endCollection(withEnd: endDate) { [weak self] _, error in
                guard error == nil else { return }
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isRunning = false
                    self.isPaused = false
                    self.timer?.invalidate()
                    self.timer = nil
                    let averageHeartRate = builder.statistics(for: HKObjectType.quantityType(forIdentifier: .heartRate)!)?
                        .averageQuantity()?
                        .doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                    self.review = WorkoutReview(averageHeartRate: Int((averageHeartRate ?? 0).rounded()),
                                                elapsedText: self.elapsedText,
                                                distanceMeters: distanceMeters,
                                                caloriesKcal: caloriesKcal)
                }
            }
        }
    }

    func saveReviewedWorkout() {
        guard let builder, let review, !isSaving else { return }
        isSaving = true
        saveError = nil
        builder.finishWorkout { [weak self] savedWorkout, error in
            guard let self else { return }

            if let error {
                DispatchQueue.main.async {
                    self.completeSave(.failure(error.localizedDescription))
                }
                return
            }

            guard let savedWorkout else {
                DispatchQueue.main.async {
                    self.completeSave(.failure("HealthKit did not return the saved workout."))
                }
                return
            }

            let distance = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!
            let energy = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
            let savedDistance = savedWorkout.statistics(for: distance)?.sumQuantity()?.doubleValue(for: .meter()) ?? 0
            let savedCalories = savedWorkout.statistics(for: energy)?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
            if savedDistance + 0.01 < review.distanceMeters || savedCalories + 0.01 < review.caloriesKcal {
                DispatchQueue.main.async {
                    self.completeSave(.failure("HealthKit saved the workout without all treadmill totals."))
                }
            } else {
                DispatchQueue.main.async { self.completeSave(.success) }
            }
        }
    }

    func dismissSaveResult() {
        let result = saveResult
        saveResult = nil
        if case .success = result {
            resetAfterReview()
        }
    }

    func discardReviewedWorkout() {
        resetAfterReview()
    }

    func recordMetrics(speedKph: Double, distanceMeters: Double, caloriesKcal: Double) {
        guard isRunning, !isPaused, let builder else { return }
        let now = Date()
        guard now.timeIntervalSince(lastMetricDate) > 0.2 else { return }
        let start = lastMetricDate

        if let speedType = HKQuantityType.quantityType(forIdentifier: .runningSpeed) {
            let speed = HKQuantity(unit: HKUnit.meter().unitDivided(by: .second()), doubleValue: max(0, speedKph / 3.6))
            builder.add([HKQuantitySample(type: speedType, quantity: speed, start: start, end: now)]) { _, _ in }
        }

        lastMetricDate = now
    }

    private func updateElapsed() {
        guard let startedAt else { return }
        let seconds = max(0, Int(Date().timeIntervalSince(startedAt)))
        elapsedText = String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func addFinalMetrics(to builder: HKLiveWorkoutBuilder,
                                 distanceMeters: Double,
                                 caloriesKcal: Double,
                                 endDate: Date,
                                 completion: @escaping (Error?) -> Void) {
        var samples: [HKSample] = []

        if distanceMeters > 0, let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) {
            let distance = HKQuantity(unit: .meter(), doubleValue: distanceMeters)
            samples.append(HKQuantitySample(type: distanceType,
                                            quantity: distance,
                                            start: startedAt ?? endDate,
                                            end: endDate))
        }

        if caloriesKcal > 0, let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            let energy = HKQuantity(unit: .kilocalorie(), doubleValue: caloriesKcal)
            samples.append(HKQuantitySample(type: energyType,
                                            quantity: energy,
                                            start: startedAt ?? endDate,
                                            end: endDate))
        }

        guard !samples.isEmpty else {
            completion(nil)
            return
        }

        builder.add(samples) { success, error in
            if let error {
                completion(error)
            } else if success {
                completion(nil)
            } else {
                completion(NSError(domain: "Runnerz.HealthKit", code: 1,
                                   userInfo: [NSLocalizedDescriptionKey: "HealthKit rejected the treadmill totals."]))
            }
        }
    }

    private func completeSave(_ result: SaveResult) {
        isSaving = false
        if case .failure(let message) = result {
            saveError = message
        }
        saveResult = result
    }

    private func resetAfterReview() {
        session = nil
        builder = nil
        startedAt = nil
        review = nil
        saveError = nil
        heartRate = 0
        elapsedText = "00:00"
    }

    private func failStart(with error: Error) {
        session?.end()
        session = nil
        builder = nil
        timer?.invalidate()
        timer = nil
        isRunning = false
        isPaused = false
        startError = error.localizedDescription
    }
}

extension WorkoutManager: HKWorkoutSessionDelegate {
    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                        from fromState: HKWorkoutSessionState, date: Date) {
        DispatchQueue.main.async { self.isPaused = toState == .paused }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        DispatchQueue.main.async { self.failStart(with: error) }
    }
}

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf types: Set<HKSampleType>) {
        guard let type = HKObjectType.quantityType(forIdentifier: .heartRate), types.contains(type),
              let sample = workoutBuilder.statistics(for: type)?.mostRecentQuantity() else { return }
        let value = sample.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        DispatchQueue.main.async { self.heartRate = Int(value.rounded()) }
    }
}
