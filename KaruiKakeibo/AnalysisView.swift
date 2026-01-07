import SwiftUI
import Charts

// MARK: - Monthly Aggregate Model
struct MonthlyAmount: Identifiable {
    let id = UUID()
    let month: Date
    let total: Double
}

// Series data model for multi-line chart
struct MonthlySeriesPoint: Identifiable {
    let id = UUID()
    let month: Date
    let value: Double
    let series: String // "支出" / "収入" / "合計"
}

// Track x positions of month anchors inside the horizontal ScrollView viewport
private struct MonthMidXPreferenceKey: PreferenceKey {
    static var defaultValue: [Date: CGFloat] = [:]
    static func reduce(value: inout [Date: CGFloat], nextValue: () -> [Date: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

// MARK: - Analysis View
struct AnalysisView: View {
    @EnvironmentObject var viewModel: ExpenseViewModel
    @State private var windowStartMonth: Date = {
        let cal = Calendar.current
        let now = Date()
        let startOfThisMonth = cal.date(from: cal.dateComponents([.year, .month], from: now))!
        // デフォルトは「直近12ヶ月」
        return cal.date(byAdding: .month, value: -11, to: startOfThisMonth) ?? startOfThisMonth
    }()
    @State private var windowLength: Int = 12
    @State private var zoomScale: CGFloat = 0.75
    @State private var zoomRecenterTick: Int = 0
    @State private var lastLiveRecenterTs: TimeInterval = 0
    @State private var visibleCenterMonth: Date? = nil
    @State private var zoomFocusMonth: Date? = nil
    @State private var scrollViewportWidth: CGFloat = 0

    private let zoomMin: CGFloat = 0.25
    private let zoomMax: CGFloat = 3.0
    private let zoomStep: CGFloat = 0.25

    @State private var hasAutoScrolledToEnd: Bool = false
    
    @State private var selectedMonth: Date? = nil

    private var seriesData: [MonthlySeriesPoint] {
        buildSeries(startMonth: windowStartMonth, monthsCount: windowLength)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerControls
                    chartSection
                    navigationLinksSection
                }
                .padding()
            }
            .navigationTitle("分析")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Header Controls
private extension AnalysisView {
    var headerControls: some View {
        // ヘッダーは不要になったため空にします
        EmptyView()
    }
}

// MARK: - Chart Section
private extension AnalysisView {
    var chartSection: some View {
        GroupBox {
            if seriesData.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("データがありません")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("取引を追加すると、月間推移が表示されます")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                // 横スクロール + ピンチズーム対応（Y軸と凡例は左に固定）
                let yDomain = yDomainForSeries(seriesData)
                let selectedValues = selectedMonth.map(valuesForMonth)
                let labelAtBottom: Bool = {
                    guard let sv = selectedValues else { return false }
                    let anchorY = max(sv.expense, sv.income, sv.total)
                    let range = yDomain.upperBound - yDomain.lowerBound
                    guard range > 0 else { return false }
                    // 上端付近に来たら下側に出す（はみ出し防止）
                    return anchorY >= (yDomain.upperBound - range * 0.18)
                }()
                let labelAtTop: Bool = {
                    guard let sv = selectedValues else { return false }
                    let anchorY = max(sv.expense, sv.income, sv.total)
                    let range = yDomain.upperBound - yDomain.lowerBound
                    guard range > 0 else { return false }
                    // 下端付近に来たら上側へ寄せる（はみ出し防止）
                    return anchorY <= (yDomain.lowerBound + range * 0.18)
                }()
                let labelYOffset: CGFloat = labelAtBottom ? 12 : (labelAtTop ? -12 : 0)
                // --- Inserted code for latest month detection and label side ---
                let currentMonthStart = startOfMonth(Date())
                let lastVisibleMonth: Date? = seriesData
                    .map { startOfMonth($0.month) }
                    .filter { $0 <= currentMonthStart }
                    .max()
                let labelOnLeft: Bool = {
                    guard let sm = selectedMonth, let lvm = lastVisibleMonth else { return false }
                    return startOfMonth(sm) == lvm
                }()

                VStack(alignment: .leading, spacing: 10) {
                    // 凡例は上に出して、軸とプロットの上端を揃える
                    fixedLegend

                    HStack(alignment: .top, spacing: 8) {
                        // 左: 固定のY軸
                        Chart {
                            // 目盛り計算のためのダミーマーク（表示しない）
                            RuleMark(y: .value("min", yDomain.lowerBound)).opacity(0)
                            RuleMark(y: .value("max", yDomain.upperBound)).opacity(0)

                            // 右側チャートの選択ラベル分の余白を一致させる（見えない注釈）
                            if let sv = selectedValues {
                                let anchorY = max(sv.expense, sv.income, sv.total)
                                PointMark(
                                    x: .value("x", 0),
                                    y: .value("金額", anchorY)
                                )
                                .opacity(0)
                                .annotation(position: .trailing, alignment: .leading) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(formatMonthLabel(selectedMonth ?? Date()))
                                            .font(.caption2)
                                        valueTag(title: "支出", amount: sv.expense)
                                        valueTag(title: "収入", amount: sv.income)
                                        valueTag(title: "合計", amount: sv.total)
                                    }
                                    .opacity(0)
                                    .offset(x: 8, y: labelYOffset)
                                }
                            }
                        }
                        .chartXScale(domain: 0...1)
                        .chartYScale(domain: yDomain)
                        .chartYAxis { AxisMarks(position: .leading) }
                        // 右側のX軸と同じ高さ分の余白を確保する（表示はしない）
                        .chartXAxis {
                            AxisMarks(values: .automatic) { _ in
                                AxisGridLine().foregroundStyle(.clear)
                                AxisTick().foregroundStyle(.clear)
                                AxisValueLabel().foregroundStyle(.clear)
                            }
                        }
                        .frame(width: 72, height: 260)
                        .allowsHitTesting(false)

                        // 右: スクロールするプロット本体
                        ScrollViewReader { proxy in
                            let cal = Calendar.current
                            let monthsCount = max(1, windowLength)
                            let baseMonthWidth: CGFloat = 60
                            let trailingPadding: CGFloat = 100 // 末尾が見切れないための余白
                            let monthAnchors: [Date] = (0..<monthsCount).compactMap { offset in
                                cal.date(byAdding: .month, value: offset, to: startOfMonth(windowStartMonth))
                            }
                            let fallbackMonth: Date = {
                                if let sm = selectedMonth { return startOfMonth(sm) }
                                if !monthAnchors.isEmpty { return monthAnchors[monthAnchors.count / 2] }
                                return startOfMonth(Date())
                            }()

                            ScrollView(.horizontal, showsIndicators: true) {
                                // データ点数に応じて横幅を確保（1ヶ月あたりの幅はズームで可変）
                                let contentWidth = max(UIScreen.main.bounds.width - 32 - 72 - 8, CGFloat(monthsCount) * baseMonthWidth * zoomScale + trailingPadding)

                                VStack(alignment: .leading, spacing: 0) {
                                    Chart {
                                        ForEach(seriesData) { point in
                                            LineMark(
                                                x: .value("月", point.month, unit: .month),
                                                y: .value("金額", point.value),
                                                series: .value("系列", point.series)
                                            )
                                            .interpolationMethod(.linear)
                                            .foregroundStyle(by: .value("系列", point.series))

                                            PointMark(
                                                x: .value("月", point.month, unit: .month),
                                                y: .value("金額", point.value)
                                            )
                                            .symbolSize(24)
                                            .foregroundStyle(by: .value("系列", point.series))
                                            .opacity({ () -> Double in
                                                if let lastRealMonth = seriesData.map({ $0.month }).max() {
                                                    return point.month > lastRealMonth ? 0.0 : 1.0
                                                }
                                                return 1.0
                                            }())
                                        }

                                        if let selectedMonth {
                                            let v = valuesForMonth(selectedMonth)
                                            let anchorY = max(v.expense, v.income, v.total)

                                            // 選択月のガイド（薄い縦線）
                                            RuleMark(x: .value("選択月", selectedMonth, unit: .month))
                                                .foregroundStyle(.secondary.opacity(0.6))
                                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))

                                            // 選択月の各点を強調（ラベルは1列のスタックで出す）
                                            PointMark(
                                                x: .value("月", selectedMonth, unit: .month),
                                                y: .value("金額", v.expense)
                                            )
                                            .symbolSize(80)
                                            .foregroundStyle(.red)

                                            PointMark(
                                                x: .value("月", selectedMonth, unit: .month),
                                                y: .value("金額", v.income)
                                            )
                                            .symbolSize(80)
                                            .foregroundStyle(.green)

                                            PointMark(
                                                x: .value("月", selectedMonth, unit: .month),
                                                y: .value("金額", v.total)
                                            )
                                            .symbolSize(80)
                                            .foregroundStyle(.blue)

                                            // ラベルは同じx座標に1列で表示（重なりなし）
                                            PointMark(
                                                x: .value("月", selectedMonth, unit: .month),
                                                y: .value("金額", anchorY)
                                            )
                                            .opacity(0) // アンカー用（表示しない）
                                            .annotation(position: labelOnLeft ? .leading : .trailing, alignment: labelOnLeft ? .trailing : .leading) {
                                                VStack(alignment: .leading, spacing: 6) {
                                                    Text(formatMonthLabel(selectedMonth))
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)

                                                    valueTag(title: "支出", amount: v.expense)
                                                    valueTag(title: "収入", amount: v.income)
                                                    valueTag(title: "合計", amount: v.total)
                                                }
                                                .offset(x: labelOnLeft ? -8 : 8, y: labelYOffset)
                                            }
                                        }
                                    }
                                    .chartYScale(domain: yDomain)
                                    .chartForegroundStyleScale([
                                        "支出": .red,
                                        "収入": .green,
                                        "合計": .blue
                                    ])
                                    .chartLegend(.hidden)
                                    .chartYAxis(.hidden)
                                    .chartXScale(domain: xDomainForWindow(start: windowStartMonth, monthsCount: windowLength))
                                    .chartXAxis {
                                        AxisMarks(values: .stride(by: .month)) { _ in
                                            AxisGridLine()
                                            AxisTick()
                                            AxisValueLabel(format: .dateTime.month(.abbreviated))
                                        }
                                    }
                                    .chartOverlay { proxy in
                                        GeometryReader { geo in
                                            Rectangle().fill(Color.clear).contentShape(Rectangle())
                                                .gesture(
                                                    SpatialTapGesture()
                                                        .onEnded { value in
                                                            let plotFrame = geo[proxy.plotAreaFrame]
                                                            let xInPlot = value.location.x - plotFrame.origin.x
                                                            guard xInPlot >= 0, xInPlot <= plotFrame.size.width else { return }

                                                            if let date: Date = proxy.value(atX: xInPlot) {
                                                                let month = startOfMonth(date)
                                                                // ウィンドウ外をタップした場合は無視
                                                                let domain = xDomainForWindow(start: windowStartMonth, monthsCount: windowLength)
                                                                if month >= domain.lowerBound && month <= domain.upperBound {
                                                                    withAnimation(.easeInOut(duration: 0.25)) {
                                                                        selectedMonth = month
                                                                    }
                                                                }
                                                            }
                                                        }
                                                )
                                        }
                                    }
                                    .animation(.easeInOut(duration: 0.25), value: selectedMonth)
                                    .frame(width: contentWidth, height: 260)
                                    .id("chartContent")

                                    // ズーム後に「中央」を基準に寄せるためのアンカー（表示しない）
                                    HStack(spacing: 0) {
                                        ForEach(monthAnchors, id: \.self) { m in
                                            Color.clear
                                                .frame(width: baseMonthWidth * zoomScale, height: 1)
                                                .background(
                                                    GeometryReader { g in
                                                        Color.clear.preference(
                                                            key: MonthMidXPreferenceKey.self,
                                                            value: [m: g.frame(in: .named("ChartScroll")).midX]
                                                        )
                                                    }
                                                )
                                                .id(m)
                                        }
                                        Color.clear
                                            .frame(width: trailingPadding, height: 1)
                                    }
                                    .frame(width: contentWidth, height: 1, alignment: .leading)
                                    .allowsHitTesting(false)
                                }
                                .padding(.trailing, 16)
                                .gesture(
                                    MagnificationGesture()
                                        .onChanged { value in
                                            // ズーム倍率をクランプ
                                            let clamped = min(max(zoomMin, value), zoomMax)
                                            zoomScale = clamped

                                            // ピンチ中も中央（表示範囲の中心月）を維持する
                                            let now = Date().timeIntervalSinceReferenceDate
                                            if now - lastLiveRecenterTs >= 0.03 { // 約30fps相当で間引き
                                                lastLiveRecenterTs = now
                                                // ピンチ開始時点の「見えている中心月」を固定して使う
                                                if zoomFocusMonth == nil {
                                                    zoomFocusMonth = visibleCenterMonth ?? selectedMonth.map(startOfMonth) ?? fallbackMonth
                                                }
                                                let target = zoomFocusMonth ?? visibleCenterMonth ?? selectedMonth.map(startOfMonth) ?? fallbackMonth
                                                DispatchQueue.main.async {
                                                    withAnimation(nil) {
                                                        proxy.scrollTo(target, anchor: .center)
                                                    }
                                                }
                                            }
                                        }
                                        .onEnded { _ in
                                            // ズーム後に中央（表示範囲の中心）へ寄せる
                                            zoomRecenterTick += 1
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                                zoomFocusMonth = nil
                                            }
                                        }
                                )
                            }
                            .coordinateSpace(name: "ChartScroll")
                            .background(
                                GeometryReader { geo in
                                    Color.clear
                                        .onAppear { scrollViewportWidth = geo.size.width }
                                        .onChange(of: geo.size.width) { newWidth in
                                            scrollViewportWidth = newWidth
                                        }
                                }
                            )
                            .onPreferenceChange(MonthMidXPreferenceKey.self) { positions in
                                guard scrollViewportWidth > 0 else { return }
                                let centerX = scrollViewportWidth / 2
                                if let best = positions.min(by: { abs($0.value - centerX) < abs($1.value - centerX) })?.key {
                                    visibleCenterMonth = best
                                }
                            }
                            .onAppear {
                                // 初回表示時に末尾へスクロールして最新データが見えるようにする
                                if !hasAutoScrolledToEnd {
                                    hasAutoScrolledToEnd = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        withAnimation(.easeInOut(duration: 0.25)) {
                                            proxy.scrollTo("chartContent", anchor: .trailing)
                                        }
                                    }
                                }
                            }
                            .onChange(of: zoomRecenterTick) { _ in
                                // レイアウト更新後に、中央へ寄せる
                                DispatchQueue.main.async {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        let target = zoomFocusMonth ?? visibleCenterMonth ?? selectedMonth.map(startOfMonth) ?? fallbackMonth
                                        proxy.scrollTo(target, anchor: .center)
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                            zoomFocusMonth = nil
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } label: {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                Text("月間推移")
                    .font(.headline)

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            zoomFocusMonth = visibleCenterMonth ?? selectedMonth.map(startOfMonth) ?? windowCenterMonth(start: windowStartMonth, monthsCount: windowLength)
                            zoomScale = max(zoomMin, zoomScale - zoomStep)
                            zoomRecenterTick += 1
                        }
                    } label: {
                        Image(systemName: "minus")
                            .font(.subheadline)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(zoomScale <= zoomMin)
                    .accessibilityLabel("縮小")

                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            zoomFocusMonth = visibleCenterMonth ?? selectedMonth.map(startOfMonth) ?? windowCenterMonth(start: windowStartMonth, monthsCount: windowLength)
                            zoomScale = min(zoomMax, zoomScale + zoomStep)
                            zoomRecenterTick += 1
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.subheadline)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(zoomScale >= zoomMax)
                    .accessibilityLabel("拡大")
                }
            }
        }
    }
}

private extension AnalysisView {
    var fixedLegend: some View {
        HStack(alignment: .center, spacing: 14) {
            legendRow(color: .red, title: "支出")
            legendRow(color: .green, title: "収入")
            legendRow(color: .blue, title: "合計")
            Spacer(minLength: 0)
        }
        .font(.caption)
    }
}

// MARK: - Navigation to other analysis sections
private extension AnalysisView {
    var navigationLinksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("詳細分析")
                .font(.headline)

            NavigationLink {
                CategorySummaryView(
                    selectedTab: .constant(AppTab.analysis.rawValue),
                    shouldFocusAmount: .constant(false)
                )
                .environmentObject(viewModel)
            } label: {
                HStack {
                    Image(systemName: "chart.pie.fill")
                        .foregroundStyle(.blue)
                    Text("カテゴリ別集計")
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.blue.opacity(0.08)))
            }

            NavigationLink {
                ExpensesView()
                    .environmentObject(viewModel)
            } label: {
                HStack {
                    Image(systemName: "list.bullet.rectangle.fill")
                        .foregroundStyle(.green)
                    Text("全ての支出履歴")
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.green.opacity(0.08)))
            }
        }
    }
}

// MARK: - Data helpers
private extension AnalysisView {
    // ウィンドウ内の3系列データ（支出・収入・合計=収入-支出）を組み立て
    func buildSeries(startMonth: Date, monthsCount: Int) -> [MonthlySeriesPoint] {
        let cal = Calendar.current
        // 12ヶ月分の月初日を作成
        let monthStarts: [Date] = (0..<monthsCount).compactMap { offset in
            cal.date(byAdding: .month, value: offset, to: startOfMonth(startMonth))
        }

        let currentMonthStart = startOfMonth(Date())

        // バケツ: index -> (expense, income)
        var expenseBuckets = Array(repeating: 0.0, count: monthsCount)
        var incomeBuckets = Array(repeating: 0.0, count: monthsCount)

        for e in viewModel.expenses {
            let d = startOfMonth(e.date)
            // 未来のデータは無視
            if d > currentMonthStart { continue }
            // 月初を基準にインデックスを計算
            if let idx = monthsBetween(from: startOfMonth(startMonth), to: d), idx >= 0, idx < monthsCount {
                if e.type == .expense {
                    expenseBuckets[idx] += e.amount
                } else {
                    incomeBuckets[idx] += e.amount
                }
            }
        }

        var points: [MonthlySeriesPoint] = []
        for (i, m) in monthStarts.enumerated() {
            let exp = expenseBuckets[i]
            let inc = incomeBuckets[i]
            let total = inc - exp // 合計 = 収入 - 支出
            points.append(MonthlySeriesPoint(month: m, value: exp, series: "支出"))
            points.append(MonthlySeriesPoint(month: m, value: inc, series: "収入"))
            points.append(MonthlySeriesPoint(month: m, value: total, series: "合計"))
        }
        return points
    }

    func xDomainForWindow(start: Date, monthsCount: Int) -> ClosedRange<Date> {
        let cal = Calendar.current
        let start = startOfMonth(start)
        let endMonthStart = cal.date(byAdding: .month, value: monthsCount, to: start) ?? start
        return start...endMonthStart
    }

    func startOfMonth(_ date: Date) -> Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: date)
        return cal.date(from: comps) ?? date
    }

    func windowCenterMonth(start: Date, monthsCount: Int) -> Date {
        let cal = Calendar.current
        let idx = max(0, monthsCount / 2)
        return cal.date(byAdding: .month, value: idx, to: startOfMonth(start)) ?? startOfMonth(start)
    }

    func monthsBetween(from: Date, to: Date) -> Int? {
        let cal = Calendar.current
        let comps = cal.dateComponents([.month], from: startOfMonth(from), to: startOfMonth(to))
        return comps.month
    }

    func valuesForMonth(_ month: Date) -> (expense: Double, income: Double, total: Double) {
        let target = startOfMonth(month)
        var exp = 0.0
        var inc = 0.0
        var total = 0.0

        for p in seriesData {
            if startOfMonth(p.month) != target { continue }
            switch p.series {
            case "支出": exp = p.value
            case "収入": inc = p.value
            case "合計": total = p.value
            default: break
            }
        }
        return (exp, inc, total)
    }

    func formatMonthLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.locale = Locale.current
        f.dateFormat = "yyyy/MM"
        return f.string(from: date)
    }

    func formatAmountJPY(_ value: Double) -> String {
        value.formatted(.currency(code: "JPY"))
    }

    @ViewBuilder
    func valueTag(title: String, amount: Double) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(formatAmountJPY(amount))
                .font(.caption)
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.background)
                .shadow(radius: 2)
        )
    }

    func yDomainForSeries(_ points: [MonthlySeriesPoint]) -> ClosedRange<Double> {
        guard let minV = points.map({ $0.value }).min(), let maxV = points.map({ $0.value }).max() else {
            return 0...1
        }
        if minV == maxV {
            let pad = max(1.0, abs(minV) * 0.1)
            return (minV - pad)...(maxV + pad)
        }
        let range = maxV - minV
        let pad = max(range * 0.12, 1.0)
        return (minV - pad)...(maxV + pad)
    }

    @ViewBuilder
    func legendRow(color: Color, title: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    AnalysisView()
        .environmentObject(ExpenseViewModel())
}
