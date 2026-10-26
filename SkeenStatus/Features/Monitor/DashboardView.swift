import Charts
import ComposableArchitecture
import SwiftUI

/// The overview: key numbers on glass tiles and charts of the last minutes.
/// Everything here is read only; it shows what sing-box does, not switches.
struct DashboardView<Accessory: View>: View {
    let store: StoreOf<MonitorFeature>
    @ViewBuilder var accessory: Accessory

    @State private var speedHover: Date?
    @State private var connectionsHover: Date?
    @State private var memoryHover: Date?
    @State private var availabilityHover: Date?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            GlassEffectContainer(spacing: 12) {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(tiles) { tile in
                        StatTile(tile: tile)
                    }
                }
            }
            if let error = store.snapshot.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard(cornerRadius: 12)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                speedChart
                connectionsChart
                memoryChart
                availabilityChart
            }
        }
        .task { await store.send(.dashboardTask).finish() }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            StatusDot(color: statusColor(for: store.snapshot.state), size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("skeen \(store.snapshot.state.title)")
                    .font(.title.weight(.semibold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Период", selection: Binding(
                get: { store.chartRange },
                set: { store.send(.setChartRange($0)) }
            )) {
                ForEach(ChartRange.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .fixedSize()
            accessory
        }
    }

    private var subtitle: String {
        var parts = ["Роутер \(store.config.gateway)"]
        if let lastCheck = store.snapshot.lastCheck {
            parts.append("проверено в \(timeString(lastCheck))")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Tiles

    private var tiles: [Tile] {
        let process = store.snapshot.state.process
        let runtime = store.snapshot.state.phase == .running ? store.singBox.runtime : nil
        let latest = store.history.last
        let route = runtime?.groups.first(where: \.isSelectable) ?? runtime?.groups.first

        return [
            Tile(id: "pid", title: "Процесс", value: process?.pid.map { "PID \($0)" } ?? "—", detail: process?.uptime.map { "работает \($0)" } ?? store.snapshot.state.title),
            Tile(id: "memory", title: "Память", value: process?.memoryMB.map { "\($0) МБ" } ?? "—", detail: runtime?.memoryBytes.map { "куча Go \(byteString($0))" } ?? "по данным skeen"),
            Tile(id: "connections", title: "Соединения", value: runtime.map { "\($0.connections)" } ?? "—", detail: "открыто сейчас"),
            Tile(id: "route", title: "Выход", value: route?.now ?? "—", detail: runtime.map { (route.map { "\($0.name) · " } ?? "") + modeTitle($0.mode).lowercased() } ?? "нет Clash API"),
            Tile(id: "down", title: "Приём", value: rateString(latest?.downloadRate), detail: runtime.map { "всего \(byteString($0.downloadTotal))" } ?? "—"),
            Tile(id: "up", title: "Отдача", value: rateString(latest?.uploadRate), detail: runtime.map { "всего \(byteString($0.uploadTotal))" } ?? "—"),
            Tile(id: "singbox", title: "sing-box", value: runtime.map { $0.version.replacingOccurrences(of: "sing-box ", with: "") } ?? store.snapshot.version?.singBox ?? "—", detail: store.snapshot.version?.skeen.map { "SKeen \($0)" } ?? "версия skeen неизвестна"),
            Tile(id: "uptime", title: "Доступность", value: availabilityText, detail: "за \(store.chartRange == .all ? "всё время" : store.chartRange.title)"),
        ]
    }

    private var availabilityText: String {
        guard let share = availability(rangeSamples) else { return "—" }
        return String(format: share > 0.999 || share < 0.001 ? "%.0f%%" : "%.1f%%", share * 100)
    }

    // MARK: Charts

    /// Samples in the chosen range, before thinning.
    private var rangeSamples: [MetricSample] {
        guard let last = store.history.last?.date else { return [] }
        guard let seconds = store.chartRange.seconds else { return store.history }
        let start = last.addingTimeInterval(-seconds)
        return store.history.filter { $0.date >= start }
    }

    /// What the charts draw: at most about 360 points, however long the range.
    private var visibleSamples: [MetricSample] {
        downsampled(rangeSamples, maxPoints: 360)
    }

    private var xDomain: ClosedRange<Date> {
        let end = store.history.last?.date ?? Date()
        guard let seconds = store.chartRange.seconds else {
            let start = store.history.first?.date ?? end.addingTimeInterval(-60)
            return start...max(end, start.addingTimeInterval(60))
        }
        return end.addingTimeInterval(-seconds)...end
    }

    /// The sample under the pointer, nearest to the hovered time.
    private func sample(near date: Date?) -> MetricSample? {
        guard let date else { return nil }
        return visibleSamples.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    private var speedChart: some View {
        let hovered = sample(near: speedHover)
        return ChartCard(title: "Скорость", detail: "Приём и отдача в секунду", legend: [("Приём", .blue), ("Отдача", .orange)]) {
            Chart {
                ForEach(visibleSamples) { sample in
                    if let rate = sample.downloadRate {
                        AreaMark(x: .value("Время", sample.date), y: .value("Скорость", rate), series: .value("Поток", "Приём"))
                            .foregroundStyle(LinearGradient(colors: [.blue.opacity(0.35), .blue.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("Время", sample.date), y: .value("Скорость", rate), series: .value("Поток", "Приём"))
                            .foregroundStyle(.blue)
                            .interpolationMethod(.monotone)
                    }
                    if let rate = sample.uploadRate {
                        LineMark(x: .value("Время", sample.date), y: .value("Скорость", rate), series: .value("Поток", "Отдача"))
                            .foregroundStyle(.orange)
                            .interpolationMethod(.monotone)
                    }
                }
                if let hovered {
                    hoverRule(hovered, lines: [
                        ("Приём", rateString(hovered.downloadRate), .blue),
                        ("Отдача", rateString(hovered.uploadRate), .orange),
                    ])
                    if let rate = hovered.downloadRate {
                        PointMark(x: .value("Время", hovered.date), y: .value("Скорость", rate)).foregroundStyle(.blue)
                    }
                }
            }
            .chartXScale(domain: xDomain)
            .chartXSelection(value: $speedHover)
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let rate = value.as(Double.self) { Text(rateString(rate)) }
                    }
                }
            }
            .chartLegend(.hidden)
        }
    }

    private var connectionsChart: some View {
        let hovered = sample(near: connectionsHover)
        return ChartCard(title: "Соединения", detail: "Открытые соединения через sing-box", legend: []) {
            Chart {
                ForEach(visibleSamples) { sample in
                    if let connections = sample.connections {
                        AreaMark(x: .value("Время", sample.date), y: .value("Соединения", connections))
                            .foregroundStyle(LinearGradient(colors: [.green.opacity(0.3), .green.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("Время", sample.date), y: .value("Соединения", connections))
                            .foregroundStyle(.green)
                            .interpolationMethod(.monotone)
                    }
                }
                if let hovered {
                    hoverRule(hovered, lines: [("Соединения", hovered.connections.map(String.init) ?? "—", .green)])
                    if let connections = hovered.connections {
                        PointMark(x: .value("Время", hovered.date), y: .value("Соединения", connections)).foregroundStyle(.green)
                    }
                }
            }
            .chartXScale(domain: xDomain)
            .chartXSelection(value: $connectionsHover)
        }
    }

    private var memoryChart: some View {
        let hovered = sample(near: memoryHover)
        return ChartCard(title: "Память sing-box", detail: "Резидентная память процесса по данным skeen", legend: []) {
            Chart {
                ForEach(visibleSamples) { sample in
                    if let memory = sample.memoryMB {
                        LineMark(x: .value("Время", sample.date), y: .value("МБ", memory))
                            .foregroundStyle(.purple)
                            .interpolationMethod(.stepEnd)
                    }
                }
                if let hovered {
                    hoverRule(hovered, lines: [("Память", hovered.memoryMB.map { "\($0) МБ" } ?? "—", .purple)])
                    if let memory = hovered.memoryMB {
                        PointMark(x: .value("Время", hovered.date), y: .value("МБ", memory)).foregroundStyle(.purple)
                    }
                }
            }
            .chartXScale(domain: xDomain)
            .chartXSelection(value: $memoryHover)
            .chartYScale(domain: .automatic(includesZero: false))
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let memory = value.as(Int.self) { Text("\(memory) МБ") }
                    }
                }
            }
        }
    }

    private var availabilityChart: some View {
        let hovered = sample(near: availabilityHover)
        return ChartCard(
            title: "Доступность",
            detail: "Когда sing-box работал",
            legend: [("работает", .green), ("остановлен", .red), ("нет связи", .yellow)]
        ) {
            Chart {
                ForEach(spans) { span in
                    RectangleMark(
                        xStart: .value("С", span.start),
                        xEnd: .value("По", span.end),
                        yStart: .value("Низ", 0),
                        yEnd: .value("Верх", 1)
                    )
                    .foregroundStyle(phaseColor(span.phase))
                    .opacity(hovered == nil || hovered?.date == span.start ? 1 : 0.55)
                }
                if let hovered {
                    hoverRule(hovered, lines: [("Состояние", phaseTitle(hovered.phase), phaseColor(hovered.phase))])
                }
            }
            .chartXScale(domain: xDomain)
            .chartXSelection(value: $availabilityHover)
            .chartYAxis(.hidden)
            .chartYScale(domain: 0...1)
        }
    }

    /// Each sample stretched to the next one, so the strip has no gaps.
    private var spans: [PhaseSpan] {
        let samples = visibleSamples
        return samples.indices.map { index in
            let start = samples[index].date
            let end = index + 1 < samples.count ? samples[index + 1].date : start.addingTimeInterval(15)
            // A second of overlap hides hairline seams between neighbors.
            return PhaseSpan(start: start, end: min(end, start.addingTimeInterval(3_600)).addingTimeInterval(1), phase: samples[index].phase)
        }
    }

    /// A vertical line at the hovered sample with a glass tooltip above it.
    private func hoverRule(_ sample: MetricSample, lines: [(String, String, Color)]) -> some ChartContent {
        RuleMark(x: .value("Время", sample.date))
            .foregroundStyle(.secondary.opacity(0.5))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                ChartTooltip(time: timeString(sample.date), lines: lines)
            }
    }

    private func phaseColor(_ phase: StatePhase) -> Color {
        switch phase {
        case .running: return .green
        case .stopped: return .red
        case .unreachable: return .yellow
        case .unknown: return .gray
        }
    }

    private func phaseTitle(_ phase: StatePhase) -> String {
        switch phase {
        case .running: return "работает"
        case .stopped: return "остановлен"
        case .unreachable: return "нет связи"
        case .unknown: return "неизвестно"
        }
    }
}

private struct PhaseSpan: Identifiable {
    let start: Date
    let end: Date
    let phase: StatePhase
    var id: Date { start }
}

private struct ChartTooltip: View {
    let time: String
    let lines: [(String, String, Color)]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(time)
                .font(.caption2)
                .foregroundStyle(.secondary)
            ForEach(lines, id: \.0) { line in
                HStack(spacing: 6) {
                    Circle().fill(line.2).frame(width: 7, height: 7)
                    Text(line.0).font(.caption).foregroundStyle(.secondary)
                    Text(line.1).font(.caption.weight(.semibold).monospacedDigit())
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .glassCard(cornerRadius: 10)
    }
}

private struct Tile: Identifiable {
    let id: String
    let title: String
    let value: String
    let detail: String
}

private struct StatTile: View {
    let tile: Tile

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(tile.title)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(tile.value)
                .font(.system(.title, design: .rounded).weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Text(tile.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassCard(cornerRadius: 16)
    }
}

private struct ChartCard<Content: View>: View {
    let title: String
    let detail: String
    let legend: [(String, Color)]
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                HStack(spacing: 12) {
                    ForEach(legend, id: \.0) { item in
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 2).fill(item.1).frame(width: 9, height: 9)
                            Text(item.0).font(.caption).foregroundStyle(.secondary)
                        }
                        .fixedSize()
                    }
                }
            }
            content
                .frame(height: 190)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 18)
    }
}
