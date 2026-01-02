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
    @State private var selectedMonthIndex: Int = 24
    @State private var showDataLoadingAlert: Bool = false
    private let months: [Date] = {
        let calendar = Calendar.current
        let today = Date()
        // -24ヶ月から+24ヶ月まで計算し配列化
        return (-24...24).compactMap { offset in
            calendar.date(byAdding: .month, value: offset, to: today)
        }
    }()

    @State private var isCalculating = false
    @State private var dateListForSheet: [Date] = []
    @State private var selectedDateIndex: Int = 0
    @State private var showingDetailSheet: Bool = false

    // パフォーマンス最適化用のキャッシュ
    @State private var cachedMonthlyExpenses: [Expense] = []
    @State private var cachedMonth: Date?


    // フォーマッターをキャッシュして再利用
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private var selectedMonth: Date {
        months[selectedMonthIndex]
    }

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

    private var monthFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // TabViewで月ページを切り替え
                TabView(selection: $selectedMonthIndex) {
                    ForEach(months.indices, id: \.self) { index in
                        makeMonthPage(for: months[index], at: index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.3), value: selectedMonthIndex)
                .disabled(showingDetailSheet)
            }
            .navigationTitle("支出カレンダー")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                print("📅 CalendarView表示開始 - 初期計算実行")
                calculateDailyTotalsSync()
                Task {
                    await calculateDailyTotals()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .tabReselected)) { notification in
                if let index = notification.userInfo?["index"] as? Int,
                   index == 0 { // AppTab.calendar.rawValue
                    print("📅 カレンダータブ再選択 - 強制更新実行")
                    Task {
                        await forceRefreshCalendar()
                    }
                }
            }
            .onChange(of: viewModel.expenses) { oldExpenses, newExpenses in
                print("📊 支出データ変更検知: \(oldExpenses.count) -> \(newExpenses.count)")

                // 即座に同期的に更新（カテゴリ別集計と同じパターン）
                clearCache()
                calculateDailyTotalsSync()

                print("📊 即座更新完了")
            }
            .onChange(of: selectedMonthIndex) { oldIndex, newIndex in
                print("📅 選択月インデックス変更: \(monthFormatter.string(from: months[oldIndex])) -> \(monthFormatter.string(from: months[newIndex]))")
                clearCache()
                calculateDailyTotalsSync()
            }
            // シート表示
            .sheet(isPresented: $showingDetailSheet) {
                DatePagingSheet(dates: $dateListForSheet, selectedIndex: $selectedDateIndex)
                    .environmentObject(viewModel)
            }
            .alert("データ読み込み中です。しばらくしてから再度お試しください", isPresented: $showDataLoadingAlert) {
                Button("OK", role: .cancel) { }
            }
        }
    }

    private func makeMonthPage(for month: Date, at index: Int) -> some View {
        VStack(spacing: 0) {
            MonthSelectorViewPage(
                selectedMonth: month,
                monthString: monthFormatter.string(from: month)
            )
            .padding(.horizontal)
            .padding(.bottom, 8)

            MonthSummaryHeaderView(
                selectedMonth: month,
                dailyTotals: dailyTotals,
                isCalculating: isCalculating
            )
            .padding(.horizontal)
            .padding(.bottom, 16)

            Group {
                if !isCalculating {
                    CalendarGridView(
                        selectedMonth: month,
                        dailyTotals: dailyTotals,
                        onDateTapped: { date in
                            Task {
                                await handleDateTapped(date: date, month: month)
                            }
                        }
                    )
                    .padding(.horizontal)
                } else {
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
            Spacer()
        }
        .tag(index)
        .onAppear {
            if index == selectedMonthIndex {
                // 月ページが表示されるたびに同期的に計算
                clearCache()
                calculateDailyTotalsSync()
            }
        }
    }

    private func handleDateTapped(date: Date, month: Date) async {
        // 最大2~3秒間隔でチェックしつつ待つ
        let maxWaitTime: UInt64 = 3_000_000_000 // 3秒（ナノ秒）
        let checkInterval: UInt64 = 100_000_000  // 0.1秒
        var waitedTime: UInt64 = 0

        while (viewModel.isLoading || viewModel.expenses.isEmpty) && waitedTime < maxWaitTime {
            try? await Task.sleep(nanoseconds: checkInterval)
            waitedTime += checkInterval
        }

        if viewModel.isLoading || viewModel.expenses.isEmpty {
            print("⚠️ データの読み込みが完了しませんでした。シートを表示しません。")
            await MainActor.run {
                showDataLoadingAlert = true
            }
            return
        }

        print("📅 日付タップ検知: \(date)")

        // 月の日付配列を生成（カレンダーに表示されている実際の日付を集める）
        let calendar = Calendar.current
        var dates: [Date] = []

        // 月の最初の日を取得
        let startOfMonth = calendar.dateInterval(of: .month, for: month)?.start ?? month

        // 月の最初の週の開始日（日曜日）を取得
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: startOfMonth)?.start ?? startOfMonth

        // 6週間分の日付を生成（42日）
        for i in 0..<42 {
            if let currentDate = calendar.date(byAdding: .day, value: i, to: startOfWeek) {
                let normalizedDate = calendar.startOfDay(for: currentDate)
                // 現在の月の日付のみ追加
                if calendar.isDate(normalizedDate, equalTo: month, toGranularity: .month) {
                    dates.append(normalizedDate)
                }
            }
        }

//        await MainActor.run {
//            self.dateListForSheet = dates
//            print("[DEBUG] onDateTapped: dateListForSheet count = \(dateListForSheet.count)")
//            // タップされた日付のインデックスをセット
//            let normalizedTappedDate = calendar.startOfDay(for: date)
//            if let tappedIndex = dates.firstIndex(where: { calendar.isDate($0, inSameDayAs: normalizedTappedDate) }) {
//                self.selectedDateIndex = tappedIndex
//            } else {
//                // 万が一見つからなければ0にする
//                self.selectedDateIndex = 0
//            }
//            let sortedKeys = Array(dailyTotals.keys).sorted()
//            print("[DEBUG] onDateTapped: selectedDateIndex = \(selectedDateIndex)")
//            print("[DEBUG] onDateTapped: dailyTotals.keys = \(sortedKeys)")
//
//            if !dateListForSheet.isEmpty {
//                self.showingDetailSheet = true
//            }
//
//            // ハプティックフィードバックを追加
//            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
//            impactFeedback.impactOccurred()
//        }
        // ✅ 重要: first-launch 時に「シート表示が先に走って dates が空のまま描画される」ことがあるため、
        // 1) dates/index を先に確定 → 2) 1tick(=Task.yield) 進める → 3) sheet を表示、の順にする
        await MainActor.run {
            self.dateListForSheet = dates
            print("[DEBUG] onDateTapped: dateListForSheet count = \(dateListForSheet.count)")

            // タップされた日付のインデックスをセット
            let normalizedTappedDate = calendar.startOfDay(for: date)
            if let tappedIndex = dates.firstIndex(where: { calendar.isDate($0, inSameDayAs: normalizedTappedDate) }) {
                self.selectedDateIndex = tappedIndex
            } else {
                self.selectedDateIndex = 0
            }

            let sortedKeys = Array(dailyTotals.keys).sorted()
            print("[DEBUG] onDateTapped: selectedDateIndex = \(selectedDateIndex)")
            print("[DEBUG] onDateTapped: dailyTotals.keys = \(sortedKeys)")
        }

        // 1フレーム進めて state の反映を確実にする（sheet が空で開く現象の対策）
        await Task.yield()

        await MainActor.run {
            if !dateListForSheet.isEmpty {
                self.showingDetailSheet = true
            }

            // ハプティックフィードバックを追加
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
        }
    }

    private func calculateDailyTotalsSync() {
        print("📊 同期的日別集計計算開始: \(monthFormatter.string(from: selectedMonth))")

        let calendar = Calendar.current
        let targetMonth = calendar.component(.month, from: selectedMonth)
        let targetYear = calendar.component(.year, from: selectedMonth)

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
        print("[DEBUG] calculateDailyTotalsSync: dailyTotals = \(dailyTotals)")

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

    @MainActor
    private func calculateDailyTotals() async {
        // 重複計算を防ぐ
        guard !isCalculating else {
            print("📊 既に計算中のためスキップ")
            return
        }

        print("📊 非同期日別集計計算開始: \(monthFormatter.string(from: selectedMonth))")
        isCalculating = true

        try? await Task.sleep(nanoseconds: 50_000_000) // 0.05秒

        // 同期的計算を呼び出し
        clearCache()
        calculateDailyTotalsSync()

        isCalculating = false
        print("📊 非同期日別集計計算完了")
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

// MARK: - 月選択ビュー（TabView併用版）
// 左右の矢印ボタンを削除し、表示のみとしたビュー
struct MonthSelectorViewPage: View {
    let selectedMonth: Date
    let monthString: String

    var body: some View {
        HStack {
            Spacer()
            Text(monthString)
                .font(.title2)
                .fontWeight(.semibold)
            Spacer()
        }
        .padding(.vertical, 8)
        .background {
            if #available(iOS 26.0, *) {
                Color.clear
                    .glassEffect(.regular.tint(.blue.opacity(0.25)).interactive(), in: .rect(cornerRadius: 10))
            } else {
                Color.clear
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                    )
            }
        }
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
            if let dateRaw = calendar.date(byAdding: .day, value: i, to: startOfWeek) {
                let date = calendar.startOfDay(for: dateRaw)
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
            Group {
                if #available(iOS 26.0, *) {
                    AnyView(EmptyView().glassEffect(.regular.tint(.blue).interactive(), in: .rect(cornerRadius: 12)))
                } else {
                    AnyView(EmptyView().background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray.opacity(0.05))
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    ))
                }
            }
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
            .modifier(
                GroupModifier {
                    if #available(iOS 26.0, *) {
                        $0.glassEffect(.regular.tint(isToday ? .orange : (isMaxExpenseDay ? .red : (hasExpense ? .blue : .clear))).interactive(), in: .rect(cornerRadius: 8))
                    } else {
                        $0.background(
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
                }
            )
        }
        .buttonStyle(CalendarCellButtonStyle())
        .disabled(false)
    }
}

// Helper to conditionally apply modifiers inside view builder
struct GroupModifier: ViewModifier {
    let transform: (AnyView) -> AnyView

    init<Content: View>(@ViewBuilder transform: @escaping (AnyView) -> Content) {
        self.transform = { AnyView(transform($0)) }
    }

    func body(content: Content) -> some View {
        transform(AnyView(content))
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

// 月間サマリーヘダー
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
            Group {
                if #available(iOS 26.0, *) {
                    AnyView(EmptyView().glassEffect(.regular.tint(totalAmount > 0 ? .blue : .gray).interactive(), in: .rect(cornerRadius: 12)))
                } else {
                    AnyView(EmptyView().background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(totalAmount > 0 ? Color.blue.opacity(0.1) : Color.gray.opacity(0.05))
                            .stroke(totalAmount > 0 ? Color.blue.opacity(0.3) : Color.gray.opacity(0.2), lineWidth: 1)
                    ))
                }
            }
        )
        .animation(.easeInOut(duration: 0.3), value: totalAmount > 0)
    }
}

