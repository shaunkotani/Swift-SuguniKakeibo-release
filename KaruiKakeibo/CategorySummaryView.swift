//
//  CategorySummaryView.swift
//  Suguni-Kakeibo-2
//
//  Created by 大谷駿介 on 2025/07/29.
//

import SwiftUI
import Charts


// MARK: - Swift Charts版カテゴリチャートビュー（既存機能保持）
struct CategoryChartView: View {
    let categoryTotals: [(category: String, categoryId: Int, total: Double)]
    let totalAmount: Double
    let selectedMonth: Date
    let viewModel: ExpenseViewModel
    
    private var monthFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter
    }
    
    private var chartData: [ChartDataItem] {
        // 安全策: 合計が0以下のときはグラフを描かない
        if totalAmount <= 0 { return [] }
        
        let items: [ChartDataItem] = categoryTotals
            .filter { $0.total > 0 }
            .compactMap { item in
                // パーセンテージを安全に計算（NaN/∞を防ぐ）
                let raw = (item.total / totalAmount) * 100
                let percentage = raw.isFinite ? raw : 0
                return ChartDataItem(
                    category: item.category,
                    categoryId: item.categoryId,
                    value: item.total,
                    percentage: percentage,
                    color: colorFromString(viewModel.categoryColor(for: item.categoryId))
                )
            }
            .filter { $0.value > 0 && $0.percentage.isFinite }
        
        return items
    }
    
    private func colorFromString(_ colorString: String) -> Color {
        switch colorString {
        case "green": return .green
        case "blue": return .blue
        case "purple": return .purple
        case "orange": return .orange
        case "red": return .red
        case "yellow": return .yellow
        case "pink": return .pink
        default: return .gray
        }
    }
    
    private var formattedTotalAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return "¥" + (formatter.string(from: NSNumber(value: totalAmount)) ?? "0")
    }
    
    var body: some View {
        VStack(spacing: 10) {
            // チャートセクション
            VStack(spacing: 8) {
                ZStack {
                    // Swift Charts版の円グラフ
                    if #available(iOS 16.0, *) {
                        if !chartData.isEmpty {
                            Chart(chartData, id: \.categoryId) { item in
                                SectorMark(
                                    angle: .value("金額", item.value),
                                    innerRadius: .ratio(0.4), // ドーナツ型にして中央にテキスト表示
                                    angularInset: 2.0 // セクター間に隙間
                                )
                                .foregroundStyle(item.color)
                                .cornerRadius(2.0)
                                .opacity(0.85)
                            }
                            .frame(width: 200, height: 200)
                        } else {
                            // データがない場合は空のプレースホルダー
                            EmptyView()
                                .frame(width: 200, height: 200)
                        }
                    } else {
                        // iOS 15以下用のフォールバック（既存のPieChartView）
                        if !chartData.isEmpty {
                            PieChartView(data: chartData)
                                .frame(width: 200, height: 200)
                        } else {
                            EmptyView()
                                .frame(width: 200, height: 200)
                        }
                    }
                    
                    // 中央の合計金額表示（既存と同じデザイン）
                    VStack(spacing: 4) {
                        Text("合計")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(formattedTotalAmount)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                            .minimumScaleFactor(0.8)
                            .lineLimit(1)
                    }
                    .padding()
                    .background(
                        Circle()
                            .fill(Color(UIColor.systemBackground))
                            .frame(width: 80, height: 80)
                    )
                }
            }
            
            // 統計情報（既存と全く同じ）
            HStack(spacing: 0) {
                // カテゴリ数
                VStack(spacing: 4) {
                    Text("カテゴリ数")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(chartData.count)")
                        .font(.body)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                }
                .frame(maxWidth: .infinity)
                
                // 区切り線
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 1, height: 30)
                
                // 最大支出カテゴリ
                VStack(spacing: 4) {
                    Text("最大支出")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let maxCategory = chartData.first {
                        Text(maxCategory.category)
                            .font(.body)
                            .fontWeight(.bold)
                            .foregroundColor(maxCategory.color)
                    } else {
                        Text("-")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                .frame(maxWidth: .infinity)
                
                // 区切り線
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 1, height: 30)
                
                // 平均支出
                VStack(spacing: 4) {
                    Text("平均支出")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("¥\(chartData.isEmpty ? 0 : totalAmount / Double(chartData.count), specifier: "%.0f")")
                        .font(.body)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                }
                .frame(maxWidth: .infinity)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.blue.opacity(0.1))
                    .stroke(Color.blue.opacity(0.3), lineWidth: 1)
            )
            Spacer().frame(height: 16)
        }
        .padding()
    }
}

// MARK: - iOS 15以下用のフォールバック（既存のPieChartView）
@available(iOS, deprecated: 16.0, message: "iOS 16以降ではSwift Chartsを使用してください")
struct PieChartView: View {
    let data: [ChartDataItem]
    
    var body: some View {
        ZStack {
            ForEach(Array(data.enumerated()), id: \.element.id) { index, item in
                PieSlice(
                    startAngle: .degrees(startAngle(for: index)),
                    endAngle: .degrees(endAngle(for: index)),
                    color: item.color
                )
            }
        }
    }
    
    private func startAngle(for index: Int) -> Double {
        let totalPercentage = data.prefix(index).reduce(0) { $0 + $1.percentage }
        return totalPercentage * 3.6 - 90 // -90度でトップから開始
    }
    
    private func endAngle(for index: Int) -> Double {
        let totalPercentage = data.prefix(index + 1).reduce(0) { $0 + $1.percentage }
        return totalPercentage * 3.6 - 90
    }
}

// MARK: - iOS 15以下用のパイスライスビュー（既存のまま）
@available(iOS, deprecated: 16.0, message: "iOS 16以降ではSwift Chartsを使用してください")
struct PieSlice: View {
    let startAngle: Angle
    let endAngle: Angle
    let color: Color
    
    var body: some View {
        Path { path in
            let center = CGPoint(x: 100, y: 100)
            let radius: CGFloat = 90
            
            path.move(to: center)
            path.addArc(
                center: center,
                radius: radius,
                startAngle: startAngle,
                endAngle: endAngle,
                clockwise: false
            )
            path.closeSubpath()
        }
        .fill(color)
        .overlay(
            Path { path in
                let center = CGPoint(x: 100, y: 100)
                let radius: CGFloat = 90
                
                path.move(to: center)
                path.addArc(
                    center: center,
                    radius: radius,
                    startAngle: startAngle,
                    endAngle: endAngle,
                    clockwise: false
                )
                path.closeSubpath()
            }
                .stroke(Color.white, lineWidth: 2)
        )
    }
}

// MARK: - チャートデータモデル（既存と同じ）
struct ChartDataItem: Identifiable {
    let id = UUID()
    let category: String
    let categoryId: Int
    let value: Double
    let percentage: Double
    let color: Color
}


/// New definition of MonthSelectorView to fix the error "Cannot find 'MonthSelectorView' in scope"
struct MonthSelectorView: View {
    @Binding var selectedMonth: Date
    private let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter
    }()
    
    var body: some View {
        HStack {
            Button(action: {
                withAnimation {
                    selectedMonth = Calendar.current.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
                }
            }) {
                Image(systemName: "chevron.left")
                    .font(.title2)
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            Spacer()
            Text(monthFormatter.string(from: selectedMonth))
                .font(.title2)
                .fontWeight(.semibold)
            Spacer()
            Button(action: {
                withAnimation {
                    selectedMonth = Calendar.current.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth
                }
            }) {
                Image(systemName: "chevron.right")
                    .font(.title2)
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
        }
        .padding(.vertical, 8)
    }
}

// --- スワイプで月を切り替えるページング対応 ---

//  月リスト (前後2年分)
private let months: [Date] = {
    let calendar = Calendar.current
    let today = Date()
    let startMonth = calendar.date(byAdding: .month, value: -24, to: today) ?? today
    return (0..<49).compactMap { calendar.date(byAdding: .month, value: $0, to: startMonth) }
}()

// MARK: - PreferenceKey to track scroll offset
private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// --- ここから CollapsibleSummaryHeader の修正版 ---
struct CollapsibleSummaryHeader: View {
    @Binding var selectedMonthIndex: Int
    let maxIndex: Int

    let month: Date
    let chartTotals: [(category: String, categoryId: Int, total: Double)]
    let totalAmount: Double
    let viewModel: ExpenseViewModel
    let baseHeight: CGFloat
    let minHeight: CGFloat
    let scrollOffset: CGFloat
    let monthFormatter: DateFormatter
    let hideThreshold: CGFloat = 100

    private var canGoPrev: Bool { selectedMonthIndex > 0 }
    private var canGoNext: Bool { selectedMonthIndex < maxIndex }
    
    var body: some View {
        VStack(spacing: 0) {
            // タイトルはNavigationBarへ移動
            Spacer().frame(height: 40)
            // 年月表示（ボタンはチャート左右へ）
            Text(monthFormatter.string(from: month))
                .font(.title2)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 4)
                .padding(.bottom, 8)

            // チャートは中央、前月/次月ボタンは左右に配置
            ZStack {
                CategoryChartView(
                    categoryTotals: chartTotals,
                    totalAmount: totalAmount,
                    selectedMonth: month,
                    viewModel: viewModel
                )

                HStack {
                    Button(action: {
                        guard canGoPrev else { return }
                        withAnimation(.easeInOut(duration: 0.25)) {
                            selectedMonthIndex -= 1
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.headline)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                            .background(
                                Circle()
                                    .fill(.ultraThinMaterial)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canGoPrev)
                    .accessibilityLabel("前の月")

                    Spacer()

                    Button(action: {
                        guard canGoNext else { return }
                        withAnimation(.easeInOut(duration: 0.25)) {
                            selectedMonthIndex += 1
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }) {
                        Image(systemName: "chevron.right")
                            .font(.headline)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                            .background(
                                Circle()
                                    .fill(.ultraThinMaterial)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canGoNext)
                    .accessibilityLabel("次の月")
                }
                .padding(.horizontal, 12)
            }
        }
        .frame(height: max(minHeight, baseHeight - scrollOffset))
        .animation(.easeInOut(duration: 0.18), value: scrollOffset)
    }
}
// --- 修正ここまで ---

struct CategorySummaryView: View {
    @EnvironmentObject var viewModel: ExpenseViewModel
    @Environment(\.dismiss) private var dismiss

    @Binding var selectedTab: Int
    @Binding var shouldFocusAmount: Bool
    
    @State private var selectedMonthIndex: Int = 24 // 現在月
    @State private var isRefreshing = false
    @State private var scrollOffset: CGFloat = 0
    @State private var animateScrollReset: Bool = false
    private let scrollToTopAnchor = "scrollToTopAnchor"
    @State private var scrollProxyRef: ScrollViewProxy? = nil
    
    private let baseHeaderHeight: CGFloat = 370
    private let minHeaderHeight: CGFloat = 160
    
    private var monthFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                let month = months[selectedMonthIndex]
                // 月ごとのカテゴリ集計と合計金額を事前取得
                let categoryTotalsForMonth = getCategoryTotals(for: month)
                let totalAmountForMonth = getTotalAmount(for: month)

                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        Color.clear.frame(height: 0).id(scrollToTopAnchor)
                        VStack(spacing: 0) {
                            // GeometryReaderでScrollViewのoffsetをPreferenceに書き込むための透明ビュー
                            GeometryReader { geo -> Color in
                                let offset = geo.frame(in: .named("scroll")).minY
                                DispatchQueue.main.async {
                                    // offsetはスクロールアップで負になるため0以上に補正して渡す
                                    self.scrollOffset = max(0, -offset)
                                }
                                return Color.clear
                            }
                            .frame(height: 0)

                            // コンテンツ本体
                            VStack(spacing: 0) {
                                // 空のSpacerを入れてヘッダー分のスペースを確保
                                Spacer().frame(height: baseHeaderHeight)

                                if !categoryTotalsForMonth.isEmpty && totalAmountForMonth > 0 {
                                    LazyVStack(spacing: 0) {
                                        ForEach(categoryTotalsForMonth, id: \.categoryId) { item in
                                            NavigationLink(destination: CategoryDetailView(
                                                categoryName: item.category,
                                                categoryId: item.categoryId,
                                                selectedMonth: month
                                            )) {
                                                CategoryRowView(
                                                    category: item.category,
                                                    categoryId: item.categoryId,
                                                    total: item.total,
                                                    percentage: totalAmountForMonth > 0 ? (item.total / totalAmountForMonth) * 100 : 0
                                                )
                                                .environmentObject(viewModel)
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 8)
                                            if item.categoryId != categoryTotalsForMonth.last?.categoryId {
                                                Divider()
                                                    .padding(.horizontal, 16)
                                            }
                                        }
                                    }
                                    .background(Color(UIColor.systemBackground))
                                    .cornerRadius(12)
                                    .padding(.horizontal)
                                } else {
                                    EmptyStateView(
                                        selectedMonth: month,
                                        monthFormatter: monthFormatter,
                                        onAddExpense: {
                                            navigateToInputTab()
                                        }
                                    )
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                                Spacer()
                            }
                        }
                    }
                    .coordinateSpace(name: "scroll")
                    .onAppear {
                        self.scrollProxyRef = proxy
                    }
                }
                // ZStackでヘッダーを重ねて表示
                .overlay(
                    CollapsibleSummaryHeader(
                        selectedMonthIndex: $selectedMonthIndex,
                        maxIndex: months.count - 1,
                        month: month,
                        chartTotals: categoryTotalsForMonth,
                        totalAmount: totalAmountForMonth,
                        viewModel: viewModel,
                        baseHeight: baseHeaderHeight,
                        minHeight: minHeaderHeight,
                        scrollOffset: scrollOffset,
                        monthFormatter: monthFormatter
                    )
                    .frame(maxWidth: .infinity)
                    // Absorb taps on the header so they don’t pass through to the rows behind
                    .contentShape(Rectangle())
                    .background(Color.black.opacity(0.001))
                    .onTapGesture { }
                    .background {
                        if #available(iOS 26.0, *) {
                            Color.clear
                                .glassEffect(
                                    .regular.tint(.blue.opacity(0.2)).interactive(),
                                    in: .rect(cornerRadius: 24)
                                )
                        } else {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                colors: [Color.white.opacity(0.10), Color.white.opacity(0.04)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                )
                        }
                    }
                    .clipped(),
                    alignment: .top
                )
            }
            .overlay(alignment: .leading) {
                EdgeBackSwipeArea {
                    dismiss()
                }
            }
        }
        .onAppear {
            // 選択中月の集計計算
            // (必要に応じて更新等を行う)
        }
        .onChange(of: viewModel.expenses) { _, _ in
            // 状態変化時の再描画等
        }
        .onChange(of: selectedMonthIndex) { _, _ in
            // 月ページ変更時の追加処理
            // スクロールオフセットをリセット
            scrollOffset = 0
            // ScrollViewReader経由でスクロール位置をトップに戻す
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NotificationCenter.default.post(name: .init("ScrollViewCategorySummaryToTop"), object: nil)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ScrollViewCategorySummaryToTop"))) { _ in
            if let scrollProxy = scrollProxyRef {
                withAnimation(.easeInOut(duration: 0.3)) {
                    scrollProxy.scrollTo(scrollToTopAnchor, anchor: .top)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    let currentIndex = currentMonthIndex()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()

                    if selectedMonthIndex == currentIndex {
                        // 同じ月にいる場合でもトップに戻したい
                        scrollOffset = 0
                        NotificationCenter.default.post(name: .init("ScrollViewCategorySummaryToTop"), object: nil)
                    } else {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            selectedMonthIndex = currentIndex
                        }
                    }
                }) {
                    Text("今月")
                }
            }
        }
        .navigationTitle("月別カテゴリ集計")
        .navigationBarTitleDisplayMode(.automatic)
    }
    
    // 今月のindexを返す（months配列から当月を探す）
    private func currentMonthIndex() -> Int {
        let calendar = Calendar.current
        let today = Date()
        // months は月単位の配列なので、月単位で一致するindexを探す
        if let idx = months.firstIndex(where: { calendar.isDate($0, equalTo: today, toGranularity: .month) }) {
            return idx
        }
        // 見つからない場合は従来の「現在月=24」をフォールバック
        return min(24, months.count - 1)
    }

    // --- 月ごとのカテゴリ集計取得関数 ---
    private func getCategoryTotals(for month: Date) -> [(category: String, categoryId: Int, total: Double)] {
        let calendar = Calendar.current
        let targetMonth = calendar.component(.month, from: month)
        let targetYear = calendar.component(.year, from: month)
        let filteredExpenses = viewModel.expenses.filter { expense in
            let monthVal = calendar.component(.month, from: expense.date)
            let yearVal = calendar.component(.year, from: expense.date)
            return monthVal == targetMonth && yearVal == targetYear
        }
        let expensesByCategory = Dictionary(grouping: filteredExpenses) { $0.categoryId }
        return viewModel.categories.compactMap { category in
            let expenses = expensesByCategory[category.id] ?? []
            let total = expenses.reduce(0) { $0 + $1.amount }
            return (category: category.name, categoryId: category.id, total: total)
        }.sorted { $0.total > $1.total }
    }
    private func getTotalAmount(for month: Date) -> Double {
        getCategoryTotals(for: month).reduce(0) { $0 + $1.total }
    }
    
    private func refreshData() async {
        isRefreshing = true
        
        // データを更新
        viewModel.refreshAllData()
        
        // 少し待ってからフラグを解除（UXのため）
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
        
        isRefreshing = false
    }
    
    // 入力タブに遷移する関数
    private func navigateToInputTab() {
        selectedTab = 2
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            shouldFocusAmount = true
        }
        
        // ハプティックフィードバック
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        
        print("📊 カテゴリサマリービューから入力画面へ遷移")
    }
    
    // 左端スワイプで戻る（TabViewのページングが戻るジェスチャを奪う対策）
    private struct EdgeBackSwipeArea: View {
        var onBack: () -> Void

        // 戻るジェスチャの感覚に寄せる
        private let edgeWidth: CGFloat = 24
        private let triggerDistance: CGFloat = 80

        var body: some View {
            Color.clear
                .frame(width: edgeWidth)
                .contentShape(Rectangle())
                .highPriorityGesture(
                    DragGesture(minimumDistance: 10)
                        .onEnded { value in
                            // 左端領域内で開始し、右方向に一定距離ドラッグしたら戻る
                            guard value.startLocation.x <= edgeWidth else { return }
                            guard value.translation.width >= triggerDistance else { return }
                            onBack()
                        }
                )
        }
    }
}


// 空状態表示用のビュー
struct EmptyStateView: View {
    let selectedMonth: Date
    let monthFormatter: DateFormatter
    let onAddExpense: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            // アイコンとアニメーション
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.1))
                    .frame(width: 120, height: 120)
                
                Image(systemName: "chart.pie")
                    .font(.system(size: 50))
                    .foregroundColor(.gray.opacity(0.6))
            }
            
            VStack(spacing: 12) {
                Text("\(monthFormatter.string(from: selectedMonth))の")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                Text("カテゴリ別支出がありません")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                
                Text("「入力」タブから支出を追加")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
    
            
            Text("または下にスワイプして更新")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

struct TotalAmountHeaderView: View {
    let totalAmount: Double
    let selectedMonth: Date
    let hasExpenses: Bool
    let categoryTotals: [(category: String, categoryId: Int, total: Double)]
    
    private var monthFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter
    }
    
    var body: some View {
        VStack(spacing: 8) {
            Text("\(monthFormatter.string(from: selectedMonth))の合計支出")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack {
                Text("¥\(totalAmount, specifier: "%.0f")")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(hasExpenses ? .primary : .secondary)
                    .animation(.easeInOut(duration: 0.3), value: totalAmount)
                
                if hasExpenses {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.title2)
                        .foregroundColor(.green)
                        .opacity(0.7)
                }
            }
            
            // 追加情報
            if hasExpenses {
                let categoryCount = categoryTotals.filter { $0.total > 0 }.count
                Text("\(categoryCount)カテゴリで支出")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(hasExpenses ? Color.blue.opacity(0.1) : Color.gray.opacity(0.05))
                .stroke(hasExpenses ? Color.blue.opacity(0.3) : Color.gray.opacity(0.2), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.3), value: hasExpenses)
    }
}

struct CategoryRowView: View {
    let category: String
    let categoryId: Int
    let total: Double
    let percentage: Double
    @EnvironmentObject var viewModel: ExpenseViewModel
    
    // 動的にアイコンを取得
    private var categoryIcon: String {
        return viewModel.categoryIcon(for: categoryId)
    }
    
    // 動的に色を取得
    private var categoryColor: Color {
        let colorString = viewModel.categoryColor(for: categoryId)
        return colorFromString(colorString)
    }
    
    private func colorFromString(_ colorString: String) -> Color {
        switch colorString {
        case "green": return .green
        case "blue": return .blue
        case "purple": return .purple
        case "orange": return .orange
        case "red": return .red
        case "yellow": return .yellow
        case "pink": return .pink
        default: return .gray
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // カテゴリアイコン
            VStack {
                Image(systemName: categoryIcon)
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(width: 45, height: 45)
                    .background(categoryColor)
                    .clipShape(Circle())
                    .shadow(color: categoryColor.opacity(0.3), radius: 2, x: 0, y: 1)
            }
            
            // カテゴリ情報
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(category)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Text("¥\(total, specifier: "%.0f")")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                }
                
                HStack {
                    Text("\(percentage, specifier: "%.1f")%")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(categoryColor)
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        Text("詳細")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                // プログレスバー
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 4)
                            .cornerRadius(2)
                        
                        Rectangle()
                            .fill(categoryColor)
                            .frame(
                                width: max(0, min(geometry.size.width * (percentage / 100), geometry.size.width)),
                                height: 4
                            )
                            .cornerRadius(2)
                            .animation(.easeInOut(duration: 0.5), value: percentage)
                    }
                }
                .frame(height: 4)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

