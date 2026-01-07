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
    @State private var zoomScale: CGFloat = 1.0
    @State private var hasAutoScrolledToEnd: Bool = false

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
                // 横スクロール + ピンチズーム対応
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: true) {
                        // データ点数に応じて横幅を確保（1ヶ月あたりの幅はズームで可変）
                        let monthsCount = max(1, windowLength)
                        let baseMonthWidth: CGFloat = 60
                        let trailingPadding: CGFloat = 32 // 末尾が見切れないための余白
                        let contentWidth = max(UIScreen.main.bounds.width - 32, CGFloat(monthsCount) * baseMonthWidth * zoomScale + trailingPadding)

                        VStack(alignment: .leading) {
                            Chart(seriesData) { point in
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
                            .chartForegroundStyleScale([
                                "支出": .red,
                                "収入": .green,
                                "合計": .blue
                            ])
                            .chartLegend(position: .automatic, alignment: .leading)
                            .chartYAxis { AxisMarks(position: .leading) }
                            .chartXScale(domain: xDomainForWindow(start: windowStartMonth, monthsCount: windowLength))
                            .chartXAxis {
                                AxisMarks(values: .stride(by: .month)) { _ in
                                    AxisGridLine()
                                    AxisTick()
                                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                                }
                            }
                            .frame(width: contentWidth, height: 260)
                            .id("chartContent")
                        }
                        .padding(.trailing, 16)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    // ズーム倍率を1.0〜3.0にクランプ
                                    let clamped = min(max(1.0, value), 3.0)
                                    zoomScale = clamped
                                }
                                .onEnded { _ in
                                    // ズーム後に末尾へ自動スクロール
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        proxy.scrollTo("chartContent", anchor: .trailing)
                                    }
                                }
                        )
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
                }
            }
        } label: {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                Text("月間推移（直近ウィンドウ）")
                    .font(.headline)
                Spacer()
            }
        }
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
                    Text("支出の履歴")
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
        let endMonthStart = cal.date(byAdding: .month, value: monthsCount - 1, to: start) ?? start
        return start...endMonthStart
    }

    func startOfMonth(_ date: Date) -> Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: date)
        return cal.date(from: comps) ?? date
    }

    func monthsBetween(from: Date, to: Date) -> Int? {
        let cal = Calendar.current
        let comps = cal.dateComponents([.month], from: startOfMonth(from), to: startOfMonth(to))
        return comps.month
    }
}

#Preview {
    AnalysisView()
        .environmentObject(ExpenseViewModel())
}

