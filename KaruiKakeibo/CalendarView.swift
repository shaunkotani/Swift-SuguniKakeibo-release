//
//  CalendarView.swift (自動更新対応版)
//  Suguni-Kakeibo-2
//
//  Created by 大谷駿介 on 2025/07/29.
//

import SwiftUI

struct CalendarDateItem: Identifiable {
    let id = UUID()
    let date: Date
}

struct CalendarView: View {
    @EnvironmentObject var viewModel: ExpenseViewModel
    @Binding var selectedTab: Int
    @Binding var shouldFocusAmount: Bool
    @State private var dailyTotals: [String: Double] = [:]
    @State private var selectedMonth = Date()
    @State private var isCalculating = false
    @State private var lastCalculationHash: Int = 0
    @State private var selectedDate: Date? = nil
    @State private var showingDetailSheet = false
    
    @State private var selectedDateItem: CalendarDateItem? = nil

    // パフォーマンス最適化用のキャッシュ
    @State private var cachedMonthlyExpenses: [Expense] = []
    @State private var cachedMonth: Date?
    
    // フォーマッターをキャッシュして再利用
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
                
                // カレンダーグリッド
                if !isCalculating {
                    CalendarGridView(
                        selectedMonth: selectedMonth,
                        dailyTotals: filteredDailyTotals,
                        onDateTapped: { date in
                            print("📅 日付タップ検知: \(date)")
                            let dateItem = CalendarDateItem(date: date)

                            selectedDateItem = dateItem
                            print("📅 selectedDateItem設定後: \(selectedDateItem?.date.description ?? "nil")")

                            // ハプティックフィードバックを追加
                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                            impactFeedback.impactOccurred()
                        }
                    )
                    .padding(.horizontal)
                } else {
                    // ローディング状態
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
                
                Spacer()
            }
            .navigationTitle("支出カレンダー")
            // 🔥 新規追加: タブ表示時の更新処理
            .onAppear {
                print("📅 CalendarView表示開始 - 初期計算実行")
                Task {
                    await calculateDailyTotals()
                }
            }
            // 🔥 新規追加: タブ再選択時の更新処理
            .onReceive(NotificationCenter.default.publisher(for: .tabReselected)) { notification in
                if let index = notification.userInfo?["index"] as? Int,
                   index == 0 { // AppTab.calendar.rawValue
                    print("📅 カレンダータブ再選択 - 強制更新実行")
                    Task {
                        await forceRefreshCalendar()
                    }
                }
            }
            // 🔥 修正: カテゴリ別集計と同じパターンで即座に更新
            .onChange(of: viewModel.expenses) { oldExpenses, newExpenses in
                print("📊 支出データ変更検知: \(oldExpenses.count) -> \(newExpenses.count)")
                
                // 即座に同期的に更新（カテゴリ別集計と同じパターン）
                clearCache()
                calculateDailyTotalsSync()
                
                print("📊 即座更新完了")
            }
            // 🔥 修正: 月変更時も同期的に更新
            .onChange(of: selectedMonth) { oldMonth, newMonth in
                print("📅 選択月変更: \(monthFormatter.string(from: oldMonth)) -> \(monthFormatter.string(from: newMonth))")
                clearCache()
                calculateDailyTotalsSync()
            }
//            .toolbar {
//                ToolbarItem(placement: .navigationBarTrailing) {
//                    Button(action: {
//                        Task {
//                            await refreshData()
//                        }
//                    }) {
//                        Image(systemName: "arrow.clockwise")
//                            .foregroundColor(.blue)
//                    }
//                    .disabled(isCalculating)
//                }
//            }
            // シート表示
            .sheet(item: $selectedDateItem) { dateItem in
                NavigationStack {
                    DailyDetailView(selectedDate: dateItem.date)
                        .environmentObject(viewModel)
                        .onAppear {
                            print("📅 DailyDetailView表示開始: \(dateItem.date)")
                        }
                }
            }
        }
    }
    
    // 🔥 修正: キャッシュを使わずに直接計算（カテゴリ別集計と同じパターン）
    private func calculateDailyTotalsSync() {
        print("📊 同期的日別集計計算開始: \(monthFormatter.string(from: selectedMonth))")
        
        // 🔥 キャッシュを使わず、直接viewModel.expensesから計算
        let calendar = Calendar.current
        let targetMonth = calendar.component(.month, from: selectedMonth)
        let targetYear = calendar.component(.year, from: selectedMonth)
        
        // 選択された月の支出をフィルタリング
        let filteredExpenses = viewModel.expenses.filter { expense in
            let month = calendar.component(.month, from: expense.date)
            let year = calendar.component(.year, from: expense.date)
            return month == targetMonth && year == targetYear
        }
        
        print("📊 対象支出数: \(filteredExpenses.count)件")
        
        // Dictionary(grouping:)を使用して日別にグループ化
        let groupedExpenses = Dictionary(grouping: filteredExpenses) { expense in
            dateFormatter.string(from: expense.date)
        }
        
        // 各日の合計を計算
        dailyTotals = groupedExpenses.mapValues { expenses in
            expenses.reduce(0) { $0 + $1.amount }
        }
        
        print("📊 同期的日別集計計算完了: \(dailyTotals.count)日分")
        
        // 計算完了の視覚的フィードバック
        if !dailyTotals.isEmpty {
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
        }
    }
    
    private func forceRefreshCalendar() async {
        print("🔄 カレンダー強制更新開始")
        clearCache()
        
        // ViewModelから最新データを取得
        viewModel.refreshAllData()
        
        // 少し待ってからカレンダーを更新
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
        
        await calculateDailyTotals()
        print("🔄 カレンダー強制更新完了")
    }
    
    // 🔥 修正: 非同期版も残しておく（初期表示用）
    @MainActor
    private func calculateDailyTotals() async {
        // 重複計算を防ぐ
        guard !isCalculating else {
            print("📊 既に計算中のためスキップ")
            return
        }
        
        print("📊 非同期日別集計計算開始: \(monthFormatter.string(from: selectedMonth))")
        isCalculating = true
        
        // 🔥 修正: より短い遅延で確実に更新
        try? await Task.sleep(nanoseconds: 50_000_000) // 0.05秒
        
        // 同期的計算を呼び出し
        clearCache()
        calculateDailyTotalsSync()
        
        isCalculating = false
        print("📊 非同期日別集計計算完了")
    }
    
    // データのハッシュ値を計算（変更検出用）
    private func calculateExpensesHash(_ expenses: [Expense]) -> Int {
        var hasher = Hasher()
        hasher.combine(expenses.count)
        
        // 月に関連する支出のみをハッシュに含める
        let calendar = Calendar.current
        let targetMonth = calendar.component(.month, from: selectedMonth)
        let targetYear = calendar.component(.year, from: selectedMonth)
        
        let relevantExpenses = expenses.filter { expense in
            let month = calendar.component(.month, from: expense.date)
            let year = calendar.component(.year, from: expense.date)
            return month == targetMonth && year == targetYear
        }
        
        for expense in relevantExpenses {
            hasher.combine(expense.id)
            hasher.combine(expense.amount)
            hasher.combine(expense.date.timeIntervalSince1970)
            hasher.combine(expense.categoryId)
        }
        
        return hasher.finalize()
    }
    
    private func clearCache() {
        cachedMonthlyExpenses.removeAll()
        cachedMonth = nil
        print("📊 キャッシュクリア完了")
    }
    
    private func refreshData() async {
        print("🔄 手動リフレッシュ開始")
        clearCache()
        viewModel.refreshAllData()
        await calculateDailyTotals()
        print("🔄 手動リフレッシュ完了")
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

// MARK: - カレンダーグリッドビューは変更なし
struct CalendarGridView: View {
    let selectedMonth: Date
    let dailyTotals: [String: Double]
    let onDateTapped: (Date) -> Void
    
    private let calendar = Calendar.current
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    
    // 曜日のヘッダー
    private let weekdaySymbols = ["日", "月", "火", "水", "木", "金", "土"]
    
    // 月の日付配列を取得
    private var monthDates: [Date?] {
        var dates: [Date?] = []
        
        // 月の最初の日を取得
        let startOfMonth = calendar.dateInterval(of: .month, for: selectedMonth)?.start ?? selectedMonth
        
        // 月の最初の週の開始日（日曜日）を取得
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: startOfMonth)?.start ?? startOfMonth
        
        // 6週間分の日付を生成（42日）
        for i in 0..<42 {
            if let date = calendar.date(byAdding: .day, value: i, to: startOfWeek) {
                // 現在の月の日付のみ追加、それ以外はnil
                if calendar.isDate(date, equalTo: selectedMonth, toGranularity: .month) {
                    dates.append(date)
                } else {
                    dates.append(nil)
                }
            } else {
                dates.append(nil)
            }
        }
        
        return dates
    }
    
    // 🎯 最大支出日を計算するプロパティを追加
    private var maxExpenseDate: String? {
        guard !dailyTotals.isEmpty else { return nil }
        return dailyTotals.max { $0.value < $1.value }?.key
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // 曜日ヘッダー
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { index in
                    Text(weekdaySymbols[index])
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(index == 0 ? .red : index == 6 ? .blue : .secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 4)
            
            // カレンダーグリッド
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 4) {
                ForEach(0..<monthDates.count, id: \.self) { index in
                    if let date = monthDates[index] {
                        CalendarDayView(
                            date: date,
                            total: dailyTotals[dateFormatter.string(from: date)] ?? 0,
                            isToday: calendar.isDateInToday(date),
                            isMaxExpenseDay: maxExpenseDate == dateFormatter.string(from: date),
                            onTapped: {
                                print("📅 CalendarDayView タップ: \(date)")
                                onDateTapped(date)
                            }
                        )
                    } else {
                        // 空のセル
                        Rectangle()
                            .fill(Color.clear)
                            .frame(height: 60)
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.05))
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - その他のビューは変更なし（CalendarDayView, MonthSummaryHeaderView等）
struct CalendarDayView: View {
    let date: Date
    let total: Double
    let isToday: Bool
    let isMaxExpenseDay: Bool
    let onTapped: () -> Void
    
    private var dayNumber: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }
    
    private var isWeekend: Bool {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 || weekday == 7 // 日曜日(1) または 土曜日(7)
    }
    
    private var hasExpense: Bool {
        return total > 0
    }
    
    private var intensityLevel: Int {
        // 支出額に応じて強度レベルを決定（0-3）
        if total == 0 { return 0 }
        if total < 1000 { return 1 }
        if total < 5000 { return 2 }
        return 3
    }
    
    private var cellColor: Color {
        if !hasExpense { return Color.clear }
        
        if isMaxExpenseDay {
            // 最大支出日は特別なカラーグラデーション
            return Color.red.opacity(0.5)
        }
        
        switch intensityLevel {
        case 1: return Color.blue.opacity(0.3)
        case 2: return Color.blue.opacity(0.6)
        case 3: return Color.blue.opacity(0.9)
        default: return Color.clear
        }
    }
    
    private var textColor: Color {
        if isToday {
            return .white
        } else if isMaxExpenseDay {
            return .white
        } else if isWeekend {
            return intensityLevel >= 2 ? .white : (Calendar.current.component(.weekday, from: date) == 1 ? .red : .blue)
        } else {
            return intensityLevel >= 2 ? .white : .primary
        }
    }
    
    var body: some View {
        Button(action: onTapped) {
            VStack(spacing: 2) {
                // 日付
                Text(dayNumber)
                    .font(.headline)
                    .fontWeight(isToday ? .bold : .medium)
                    .foregroundColor(textColor)
                
                // 支出金額
                Text("¥\(total, specifier: "%.0f")")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(textColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isToday ? Color.orange : cellColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                isToday ? Color.orange.opacity(0.8) :
                                    isMaxExpenseDay ? Color.red.opacity(0.8) :
                                hasExpense ? Color.blue.opacity(0.4) : Color.clear,
                                lineWidth: isToday || isMaxExpenseDay ? 2 : 1
                            )
                    )
            )
        }
        .buttonStyle(CalendarCellButtonStyle())
        .disabled(false)
    }
}

// MARK: - カレンダーセル用ボタンスタイル
struct CalendarCellButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
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
    
    // 🎯 最大支出情報を表示（シンプル版）
    private var maxExpenseInfo: (date: String, amount: Double)? {
        guard !dailyTotals.isEmpty else { return nil }
        if let maxEntry = dailyTotals.max(by: { $0.value < $1.value }) {
            return (date: maxEntry.key, amount: maxEntry.value)
        }
        return nil
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
                            .foregroundColor(.red)
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

// 月選択ビュー
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
