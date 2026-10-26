import Foundation

/// One point on the overview charts. Old points stand for a whole bucket of
/// readings, and `weight` says how many.
struct MetricSample: Codable, Equatable, Identifiable, Sendable {
    var date: Date
    var phase: StatePhase
    /// Resident memory of sing-box from `skeen status`.
    var memoryMB: Int?
    var connections: Int?
    /// Bytes per second since the previous reading.
    var downloadRate: Double?
    var uploadRate: Double?
    var weight: Int = 1

    var id: Date { date }
}

/// sing-box's traffic counters at one moment, to turn totals into speed.
struct TrafficTotals: Equatable, Sendable {
    var date: Date
    var download: Int64
    var upload: Int64
}

/// How far back the charts look.
enum ChartRange: String, CaseIterable, Identifiable, Sendable {
    case fiveMinutes
    case fifteenMinutes
    case hour
    case day
    case all

    var id: String { rawValue }

    /// nil means everything on record.
    var seconds: TimeInterval? {
        switch self {
        case .fiveMinutes: return 300
        case .fifteenMinutes: return 900
        case .hour: return 3_600
        case .day: return 86_400
        case .all: return nil
        }
    }

    var title: String {
        switch self {
        case .fiveMinutes: return "5 мин"
        case .fifteenMinutes: return "15 мин"
        case .hour: return "1 ч"
        case .day: return "24 ч"
        case .all: return "Всё время"
        }
    }
}

/// Builds the next sample. Speed needs two readings of the counters; a
/// counter that went down means sing-box restarted, so that step has no speed.
func makeSample(
    at date: Date,
    state: SkeenState,
    runtime: SingBoxRuntime?,
    previous: TrafficTotals?
) -> (sample: MetricSample, totals: TrafficTotals?) {
    var sample = MetricSample(date: date, phase: state.phase, memoryMB: state.process?.memoryMB)
    guard let runtime, state.phase == .running else { return (sample, nil) }

    sample.connections = runtime.connections
    let totals = TrafficTotals(date: date, download: runtime.downloadTotal, upload: runtime.uploadTotal)
    if let previous {
        let seconds = date.timeIntervalSince(previous.date)
        let down = totals.download - previous.download
        let up = totals.upload - previous.upload
        if seconds >= 0.5, down >= 0, up >= 0 {
            sample.downloadRate = Double(down) / seconds
            sample.uploadRate = Double(up) / seconds
        }
    }
    return (sample, totals)
}

/// Appends a sample and keeps the history small: the last hour as is, the
/// last day by the minute, older readings by the quarter hour, a year at most.
func appending(_ sample: MetricSample, to history: [MetricSample]) -> [MetricSample] {
    compact(history.filter { $0.date < sample.date } + [sample], now: sample.date)
}

func compact(_ history: [MetricSample], now: Date) -> [MetricSample] {
    let hourAgo = now.addingTimeInterval(-3_600)
    let dayAgo = now.addingTimeInterval(-86_400)
    let yearAgo = now.addingTimeInterval(-365 * 86_400)

    let old = history.filter { $0.date >= yearAgo && $0.date < dayAgo }
    let day = history.filter { $0.date >= dayAgo && $0.date < hourAgo }
    let recent = history.filter { $0.date >= hourAgo }
    return bucketed(old, width: 900) + bucketed(day, width: 60) + recent
}

/// Thins samples to about `maxPoints` buckets of equal width, for drawing.
func downsampled(_ samples: [MetricSample], maxPoints: Int) -> [MetricSample] {
    guard samples.count > maxPoints, let first = samples.first?.date, let last = samples.last?.date else { return samples }
    let width = max(1, last.timeIntervalSince(first) / Double(maxPoints))
    return bucketed(samples, width: width)
}

/// Merges samples that fall into the same `width`-second bucket. Numbers
/// average by weight; the phase keeps the worst moment, so a short outage
/// never vanishes from the availability strip.
func bucketed(_ samples: [MetricSample], width: TimeInterval) -> [MetricSample] {
    var groups: [(key: Double, items: [MetricSample])] = []
    for sample in samples {
        let key = (sample.date.timeIntervalSince1970 / width).rounded(.down) * width
        if groups.last?.key == key {
            groups[groups.count - 1].items.append(sample)
        } else {
            groups.append((key, [sample]))
        }
    }
    return groups.map { group in
        guard group.items.count > 1 else { return group.items[0] }
        let items = group.items
        return MetricSample(
            date: Date(timeIntervalSince1970: group.key),
            phase: items.map(\.phase).max(by: { severity($0) < severity($1) }) ?? .unknown,
            memoryMB: weightedAverage(items, { $0.memoryMB.map(Double.init) }).map { Int($0.rounded()) },
            connections: weightedAverage(items, { $0.connections.map(Double.init) }).map { Int($0.rounded()) },
            downloadRate: weightedAverage(items, \.downloadRate),
            uploadRate: weightedAverage(items, \.uploadRate),
            weight: items.reduce(0) { $0 + $1.weight }
        )
    }
}

/// Share of readings that found sing-box running, from 0 to 1.
func availability(_ samples: [MetricSample]) -> Double? {
    let total = samples.reduce(0) { $0 + $1.weight }
    guard total > 0 else { return nil }
    let up = samples.filter { $0.phase == .running }.reduce(0) { $0 + $1.weight }
    return Double(up) / Double(total)
}

private func severity(_ phase: StatePhase) -> Int {
    switch phase {
    case .unknown: return 0
    case .running: return 1
    case .unreachable: return 2
    case .stopped: return 3
    }
}

private func weightedAverage(_ samples: [MetricSample], _ value: (MetricSample) -> Double?) -> Double? {
    var sum = 0.0
    var weight = 0
    for sample in samples {
        guard let v = value(sample) else { continue }
        sum += v * Double(sample.weight)
        weight += sample.weight
    }
    return weight > 0 ? sum / Double(weight) : nil
}

/// `1.2 МБ/с`, or `—` when the speed is unknown.
func rateString(_ bytesPerSecond: Double?) -> String {
    guard let bytesPerSecond else { return "—" }
    return byteString(Int64(bytesPerSecond.rounded())) + "/с"
}
