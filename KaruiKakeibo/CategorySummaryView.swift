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
        VStack(spacing: 16) {
            // チャートセクション
            VStack(spacing: 12) {
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
                            .id(monthFormatter.string(from: selectedMonth))
                            .frame(width: 200, height: 200)
                            .transaction { transaction in
                                transaction.disablesAnimations = true
                            }
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
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.gray.opacity(0.05))
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
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


struct CategorySummaryView: View {
    @EnvironmentObject var viewModel: ExpenseViewModel
    @Binding var selectedTab: Int
    @Binding var shouldFocusAmount: Bool
    @State private var categoryTotals: [(category: String, categoryId: Int, total: Double)] = []
    @State private var selectedMonth = Date()
    @State private var isRefreshing = false
    
    private var totalAmount: Double {
        categoryTotals.reduce(0) { $0 + $1.total }
    }
    
    private var hasAnyExpenses: Bool {
        !categoryTotals.isEmpty && categoryTotals.contains { $0.total > 0 }
    }
    
    private var monthFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter
    }
    
    // MARK: - 分割: ヘッダ背景のビュー（型を単純化）
    @ViewBuilder
    private func headerBackground() -> some View {
        if #available(iOS 26.0, *) {
            Color.clear
        } else {
            Rectangle().fill(.ultraThinMaterial)
        }
    }
    
    // MARK: - 分割: セクション本体（チャート/リスト or 空状態）
    @ViewBuilder
    private func contentSection() -> some View {
        if hasAnyExpenses && totalAmount > 0 {
            CategoryChartView(
                categoryTotals: categoryTotals,
                totalAmount: totalAmount,
                selectedMonth: selectedMonth,
                viewModel: viewModel
            )
            .padding(.horizontal)
            .padding(.bottom, 16)

            LazyVStack(spacing: 0) {
                ForEach(categoryTotals, id: \.categoryId) { item in
                    NavigationLink(destination: CategoryDetailView(
                        categoryName: item.category,
                        categoryId: item.categoryId,
                        selectedMonth: selectedMonth
                    )) {
                        CategoryRowView(
                            category: item.category,
                            categoryId: item.categoryId,
                            total: item.total,
                            percentage: totalAmount > 0 ? (item.total / totalAmount) * 100 : 0
                        )
                        .environmentObject(viewModel)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                    if item.categoryId != categoryTotals.last?.categoryId {
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
                selectedMonth: selectedMonth,
                monthFormatter: monthFormatter,
                onAddExpense: {
                    navigateToInputTab()
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .refreshable {
                await refreshData()
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        contentSection()
                    } header: {
                        MonthSelectorView(selectedMonth: $selectedMonth)
                            .padding(.horizontal)
                            .padding(.bottom, 8)
                            .background(headerBackground())
                    }
                }
            }
            .navigationTitle("カテゴリ別集計")
            .navigationBarTitleDisplayMode(.large)
        }
        .onAppear {
            fetchCategoryTotals()
        }
        .onChange(of: viewModel.expenses) { _, _ in
            fetchCategoryTotals()
        }
        .onChange(of: selectedMonth) { _, _ in
            fetchCategoryTotals()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    Task {
                        await refreshData()
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(.blue)
                }
                .disabled(isRefreshing)
            }
        }
    }
    
    private func fetchCategoryTotals() {
        let calendar = Calendar.current
        let targetMonth = calendar.component(.month, from: selectedMonth)
        let targetYear = calendar.component(.year, from: selectedMonth)
        
        // 選択された月の支出のみをフィルタリング
        let filteredExpenses = viewModel.expenses.filter { expense in
            let month = calendar.component(.month, from: expense.date)
            let year = calendar.component(.year, from: expense.date)
            return month == targetMonth && year == targetYear
        }
        
        // カテゴリ別集計を効率化
        let expensesByCategory = Dictionary(grouping: filteredExpenses) { $0.categoryId }
        
        categoryTotals = viewModel.categories.compactMap { category in
            let expenses = expensesByCategory[category.id] ?? []
            let total = expenses.reduce(0) { $0 + $1.amount }
            return (category: category.name, categoryId: category.id, total: total)
        }.sorted { $0.total > $1.total }
        
        print("📊 カテゴリ別集計更新: \(categoryTotals.count)カテゴリ, 合計: ¥\(totalAmount)")
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
                
                Text("「入力」タブから支出を追加してください")
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

