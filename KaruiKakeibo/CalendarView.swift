//
//  CalendarView.swift
//  Suguni-Kakeibo-2
//
//  Created by 大谷駿介 on 2025/07/29.
//

import SwiftUI

struct CalendarView: View {
    @EnvironmentObject var viewModel: ExpenseViewModel
    @Binding var selectedTab: Int
    @Binding var shouldFocusAmount: Bool
    @State private var dailyTotals: [String: Double] = [:]
    @State private var selectedMonth = Date()
    @State private var isCalculating = false
    @State private var lastCalculationHash: Int = 0
    
    // パフォーマンス最適化用のキャッシュ
    @State private var cachedMonthlyExpenses: [Expense] = []
    @State private var cachedMonth: Date?
    
    // フォーマッタをキャッシュして再利用
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    
    private var monthlyExpenses: [Expense] {
        // キャッシュを確認
        let calendar = Calendar.current
        if let cached = cachedMonth,
           calendar.isDate(cached, equalTo: selectedMonth, toGranularity: .month) {
            return cachedMonthlyExpenses
        }
        
        // 新しい月のデータを計算
        let targetMonth = calendar.component(.month, from: selectedMonth)
        let targetYear = calendar.component(.year, from: selectedMonth)
        
        let filtered = viewModel.expenses.filter { expense in
            let month = calendar.component(.month, from: expense.date)
            let year = calendar.component(.year, from: expense.date)
            return month == targetMonth && year == targetYear
        }
        
        // キャッシュを更新
        cachedMonthlyExpenses = filtered
        cachedMonth = selectedMonth
        
        return filtered
    }
    
    private var filteredDailyTotals: [String: Double] {
        // 既に月でフィルタリング済みのデータから日別合計を作成
        return dailyTotals
    }
    
    private var sortedDailyTotals: [(key: String, value: Double)] {
        filteredDailyTotals.sorted { $0.key > $1.key }
    }
    
    private var monthFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 月選択ヘッダー
                MonthSelectorView(selectedMonth: $selectedMonth)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                
                // 月間サマリー
                MonthSummaryHeaderView(
                    selectedMonth: selectedMonth,
                    dailyTotals: filteredDailyTotals,
                    isCalculating: isCalculating
                )
                .padding(.horizontal)
                .padding(.bottom, 16)
                
                // 日別リストまたは空状態
                if !filteredDailyTotals.isEmpty {
                    List {
                        ForEach(sortedDailyTotals, id: \.key) { date, total in
                            NavigationLink(destination: DailyDetailView(selectedDate: stringToDate(date))) {
                                DailyTotalRowView(date: date, total: total)
                            }
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        }
                    }
                    .listStyle(.plain)
                    .refreshable {
                        await refreshData()
                    }
                } else if !isCalculating {
                    CalendarEmptyStateView(
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
                
                // ローディング状態
                if isCalculating {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("データを計算中...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.clear)
                }
            }
            .navigationTitle("日別集計")
            .onAppear {
                calculateDailyTotalsIfNeeded()
            }
            .onChange(of: viewModel.expenses) { _, newExpenses in
                // データのハッシュ値を計算して変更を検出
                let newHash = calculateExpensesHash(newExpenses)
                if newHash != lastCalculationHash {
                    clearCache()
                    calculateDailyTotalsIfNeeded()
                    lastCalculationHash = newHash
                }
            }
            .onChange(of: selectedMonth) { _, _ in
                calculateDailyTotalsIfNeeded()
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
                    .disabled(isCalculating)
                }
            }
        }
    }
    
    // MARK: - パフォーマンス最適化されたデータ計算
    private func calculateDailyTotalsIfNeeded() {
        // 既に計算済みで変更がない場合はスキップ
        if isCalculating { return }
        
        Task {
            await calculateDailyTotals()
        }
    }
    
    @MainActor
    private func calculateDailyTotals() async {
        isCalculating = true
        
        // バックグラウンドで重い計算を実行
        let result = await withTaskGroup(of: [String: Double].self, returning: [String: Double].self) { group in
            group.addTask {
                await self.performDailyCalculation()
            }
            
            // 最初のタスクの結果を返す
            if let result = await group.next() {
                return result
            }
            return [:]
        }
        
        // メインスレッドで結果を更新
        dailyTotals = result
        isCalculating = false
        
        print("📅 日別集計計算完了: \(result.count)日分, 月: \(monthFormatter.string(from: selectedMonth))")
    }
    
    private func performDailyCalculation() async -> [String: Double] {
        // Dictionary(grouping:)を使用してパフォーマンスを最適化
        let groupedExpenses = Dictionary(grouping: monthlyExpenses) { expense in
            dateFormatter.string(from: expense.date)
        }
        
        // 各日の合計を計算
        return groupedExpenses.mapValues { expenses in
            expenses.reduce(0) { $0 + $1.amount }
        }
    }
    
    // データのハッシュ値を計算（変更検出用）
    private func calculateExpensesHash(_ expenses: [Expense]) -> Int {
        var hasher = Hasher()
        hasher.combine(expenses.count)
        
        // 最新の10件の支出のIDと金額をハッシュに含める
        for expense in expenses.prefix(10) {
            hasher.combine(expense.id)
            hasher.combine(expense.amount)
            hasher.combine(expense.date.timeIntervalSince1970)
        }
        
        return hasher.finalize()
    }
    
    private func clearCache() {
        cachedMonthlyExpenses.removeAll()
        cachedMonth = nil
    }
    
    private func refreshData() async {
        clearCache()
        viewModel.refreshAllData()
        await calculateDailyTotals()
    }
    
    // 文字列をDateに変換するヘルパー関数
    private func stringToDate(_ dateString: String) -> Date {
        return dateFormatter.date(from: dateString) ?? Date()
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
        
        print("📅 カレンダービューから入力画面へ遷移")
    }
}

// 月間サマリーヘッダー
struct MonthSummaryHeaderView: View {
    let selectedMonth: Date
    let dailyTotals: [String: Double]
    let isCalculating: Bool
    
    private var monthFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter
    }
    
    private var totalAmount: Double {
        dailyTotals.values.reduce(0, +)
    }
    
    private var expenseDays: Int {
        dailyTotals.count
    }
    
    private var averagePerDay: Double {
        expenseDays > 0 ? totalAmount / Double(expenseDays) : 0
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // 月と合計金額
            VStack(spacing: 4) {
                Text("\(monthFormatter.string(from: selectedMonth))の合計")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                HStack {
                    Text("¥\(totalAmount, specifier: "%.0f")")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .animation(.easeInOut(duration: 0.3), value: totalAmount)
                    
                    if !isCalculating && totalAmount > 0 {
                        Image(systemName: "calendar.badge.plus")
                            .font(.title2)
                            .foregroundColor(.blue)
                            .opacity(0.7)
                    }
                }
            }
            
            // 詳細統計
            if !isCalculating && expenseDays > 0 {
                HStack(spacing: 0) {
                    // 支出日数
                    VStack(spacing: 2) {
                        Text("支出日数")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(expenseDays)日")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                    }
                    .frame(maxWidth: .infinity)
                    
                    // 区切り線
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 1, height: 30)
                    
                    // 1日平均
                    VStack(spacing: 2) {
                        Text("1日平均")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("¥\(averagePerDay, specifier: "%.0f")")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                    }
                    .frame(maxWidth: .infinity)
                    
                    // 区切り線
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 1, height: 30)
                    
                    // 最大支出日
                    VStack(spacing: 2) {
                        Text("最大支出")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("¥\(dailyTotals.values.max() ?? 0, specifier: "%.0f")")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.blue.opacity(0.05))
                        .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                )
                .animation(.easeInOut(duration: 0.3), value: expenseDays)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(totalAmount > 0 ? Color.blue.opacity(0.1) : Color.gray.opacity(0.05))
                .stroke(totalAmount > 0 ? Color.blue.opacity(0.3) : Color.gray.opacity(0.2), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.3), value: totalAmount > 0)
    }
}

// カレンダー用空状態ビュー
struct CalendarEmptyStateView: View {
    let selectedMonth: Date
    let monthFormatter: DateFormatter
    let onAddExpense: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.1))
                    .frame(width: 120, height: 120)
                
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.system(size: 50))
                    .foregroundColor(.gray.opacity(0.6))
            }
            
            VStack(spacing: 12) {
                Text("\(monthFormatter.string(from: selectedMonth))の")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                Text("支出がありません")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text("「入力」タブから支出を追加してください")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            
            
            // タップ可能な支出追加ボタン
            Button(action: onAddExpense) {
                VStack(spacing: 8) {
                    HStack(spacing: 16) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.blue)
                            .font(.title2)
                        Text("支出を追加")
                            .foregroundColor(.blue)
                            .fontWeight(.medium)
                            .font(.headline)
                    }
                    
                    Text("タップで入力画面へ")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.blue.opacity(0.1))
                        .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(PlainButtonStyle())
            .scaleEffect(1.0)
            .animation(.easeInOut(duration: 0.1), value: false)
            .padding(.top, 8)
            
            Text("または下にスワイプして更新")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}


struct MonthSelectorView: View {
    @Binding var selectedMonth: Date
    
    private var monthFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter
    }
    
    var body: some View {
        HStack {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedMonth = Calendar.current.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
                }
            }) {
                Image(systemName: "chevron.left")
                    .font(.title2)
                    .foregroundColor(.blue)
                    .frame(width: 44, height: 44)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(PlainButtonStyle())
            
            Spacer()
            
            Text(monthFormatter.string(from: selectedMonth))
                .font(.title2)
                .fontWeight(.semibold)
                .animation(.easeInOut(duration: 0.2), value: selectedMonth)
            
            Spacer()
            
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedMonth = Calendar.current.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth
                }
            }) {
                Image(systemName: "chevron.right")
                    .font(.title2)
                    .foregroundColor(.blue)
                    .frame(width: 44, height: 44)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
    }
}

struct DailyTotalRowView: View {
    let date: String
    let total: Double
    
    private let inputFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    
    private let outputFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日(E)"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter
    }()
    
    private let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter
    }()
    
    private func formatDate(_ dateString: String) -> String {
        if let date = inputFormatter.date(from: dateString) {
            return outputFormatter.string(from: date)
        }
        return dateString
    }
    
    private func getDayOfWeek(_ dateString: String) -> String {
        if let date = inputFormatter.date(from: dateString) {
            return dayFormatter.string(from: date)
        }
        return ""
    }
    
    private var isWeekend: Bool {
        let dayOfWeek = getDayOfWeek(date)
        return dayOfWeek == "土" || dayOfWeek == "日"
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // 日付アイコン（最適化済み）
            VStack(spacing: 2) {
                if let dateObject = inputFormatter.date(from: date) {
                    Text("\(Calendar.current.component(.day, from: dateObject))")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    Text(getDayOfWeek(date))
                        .font(.caption2)
                        .foregroundColor(.white)
                } else {
                    Image(systemName: "calendar")
                        .font(.title2)
                        .foregroundColor(.white)
                }
            }
            .frame(width: 40, height: 40)
            .background(isWeekend ? Color.red : Color.blue)
            .clipShape(Circle())
            
            // 日付情報
            VStack(alignment: .leading, spacing: 4) {
                Text(formatDate(date))
                    .font(.headline)
                    .foregroundColor(.primary)
                
                HStack(spacing: 4) {
                    Text(date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("・")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("タップして詳細を表示")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // 金額と矢印
            VStack(alignment: .trailing, spacing: 2) {
                Text("¥\(total, specifier: "%.0f")")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                HStack(spacing: 4) {
                    Text("詳細")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
    }
}
