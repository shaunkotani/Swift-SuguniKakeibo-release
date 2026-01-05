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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button(action: { shiftWindow(by: -1) }) {
                    Image(systemName: "chevron.left")
                        .font(.title3)
                        .frame(width: 36, height: 36)
                        .contentShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())

                Text(windowRangeLabel)
                    .font(.headline)
                    .frame(maxWidth: .infinity)

                Button(action: { shiftWindow(by: 1) }) {
                    Image(systemName: "chevron.right")
                        .font(.title3)
                        .frame(width: 36, height: 36)
                        .contentShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
            }
            .accessibilityElement(children: .contain)
        }
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
                .frame(minHeight: 260)
                .gesture(
                    DragGesture(minimumDistance: 10)
                        .onEnded { value in
                            let t = value.translation.width
                            let pt = value.predictedEndTranslation.width
                            if t < -40 || pt < -80 {
                                shiftWindow(by: 1, animated: true) // 左スワイプで先へ
                            } else if t > 40 || pt > 80 {
                                shiftWindow(by: -1, animated: true) // 右スワイプで前へ
                            }
                        }
                )
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
            // 未来の月はプロットしない
            if m > currentMonthStart { continue }
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
        let current = startOfMonth(Date())
        let clampedEnd = min(endMonthStart, current)
        return start...clampedEnd
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

    func shiftWindow(by months: Int, animated: Bool = true) {
        if let newStart = Calendar.current.date(byAdding: .month, value: months, to: windowStartMonth) {
            if animated {
                withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.85, blendDuration: 0.2)) {
                    windowStartMonth = newStart
                }
            } else {
                windowStartMonth = newStart
            }
        }
    }

    var windowRangeLabel: String {
        let cal = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy年M月"
        let startLabel = formatter.string(from: startOfMonth(windowStartMonth))
        let endMonthStart = cal.date(byAdding: .month, value: max(0, windowLength - 1), to: startOfMonth(windowStartMonth)) ?? windowStartMonth
        let endLabel = formatter.string(from: endMonthStart)
        return "\(startLabel) 〜 \(endLabel)"
    }
}

#Preview {
    AnalysisView()
        .environmentObject(ExpenseViewModel())
}
