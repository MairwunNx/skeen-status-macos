import Foundation
import Testing
@testable import SkeenStatus

@Suite("Chart metrics")
struct MetricsTests {

    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let running = SkeenState.running(SkeenProcess(pid: 1, memoryMB: 60))

    private func runtime(down: Int64, up: Int64) -> SingBoxRuntime {
        SingBoxRuntime(version: "1", mode: "rule", modes: [], groups: [], connections: 5, downloadTotal: down, uploadTotal: up, memoryBytes: nil)
    }

    @Test func speedComesFromTwoReadings() {
        let first = makeSample(at: start, state: running, runtime: runtime(down: 1_000, up: 100), previous: nil)
        #expect(first.sample.downloadRate == nil)
        #expect(first.sample.connections == 5)
        #expect(first.sample.memoryMB == 60)

        let second = makeSample(at: start.addingTimeInterval(2), state: running, runtime: runtime(down: 5_000, up: 300), previous: first.totals)
        #expect(second.sample.downloadRate == 2_000)
        #expect(second.sample.uploadRate == 100)
    }

    @Test func aCounterResetHasNoSpeed() {
        let previous = TrafficTotals(date: start, download: 9_000, upload: 9_000)
        let next = makeSample(at: start.addingTimeInterval(2), state: running, runtime: runtime(down: 10, up: 10), previous: previous)
        #expect(next.sample.downloadRate == nil)
    }

    @Test func stoppedSamplesCarryNoTraffic() {
        let result = makeSample(at: start, state: .stopped, runtime: runtime(down: 1, up: 1), previous: nil)
        #expect(result.sample.phase == .stopped)
        #expect(result.sample.connections == nil)
        #expect(result.totals == nil)
    }

    @Test func historyKeepsTheLastHourRawAndBucketsTheRest() {
        let now = start.addingTimeInterval(2 * 86_400)
        let samples = stride(from: 2 * 86_400.0, through: 0, by: -30).map {
            MetricSample(date: now.addingTimeInterval(-$0), phase: .running, connections: 10)
        }
        let compacted = compact(samples, now: now)
        let recent = compacted.filter { $0.date >= now.addingTimeInterval(-3_600) }
        #expect(recent.count == 121)
        let day = compacted.filter { $0.date < now.addingTimeInterval(-3_600) && $0.date >= now.addingTimeInterval(-86_400) }
        #expect(day.allSatisfy { $0.weight == 2 || $0.weight == 1 })
        #expect(compacted.count < samples.count / 2)
        #expect(compacted.reduce(0) { $0 + $1.weight } == samples.count)
    }

    @Test func bucketsKeepTheWorstPhaseAndAverageByWeight() {
        let merged = bucketed([
            MetricSample(date: start, phase: .running, connections: 10, downloadRate: 100, weight: 3),
            MetricSample(date: start.addingTimeInterval(10), phase: .stopped, connections: nil, weight: 1),
            MetricSample(date: start.addingTimeInterval(20), phase: .running, connections: 20, downloadRate: 500, weight: 1),
        ], width: 60)
        #expect(merged.count == 1)
        #expect(merged[0].phase == .stopped)
        #expect(merged[0].connections == 13)
        #expect(merged[0].downloadRate == 200)
        #expect(merged[0].weight == 5)
    }

    @Test func downsamplingCapsThePointCount() {
        let samples = (0..<5_000).map { MetricSample(date: start.addingTimeInterval(Double($0) * 2), phase: .running) }
        #expect(downsampled(samples, maxPoints: 360).count <= 361)
        #expect(downsampled(Array(samples.prefix(100)), maxPoints: 360).count == 100)
    }

    @Test func availabilityWeighsBuckets() {
        let samples = [
            MetricSample(date: start, phase: .running, weight: 9),
            MetricSample(date: start.addingTimeInterval(60), phase: .stopped, weight: 1),
        ]
        #expect(availability(samples) == 0.9)
        #expect(availability([]) == nil)
    }

    @Test func rateText() {
        #expect(rateString(nil) == "—")
        #expect(rateString(1_536) == "1.5 КБ/с")
    }
}
