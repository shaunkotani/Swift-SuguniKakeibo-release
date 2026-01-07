//
//  DailyDetailView.swift (修正版)
//  Suguni-Kakeibo-2
//

import SwiftUI
// MARK: - PreferenceKey to track scroll offset (DailyDetailView)
private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// NOTE: カテゴリは支出/収入で別管理されることを想定。ViewModel 側の typed API に対応。

struct DailyDetailView: View {
    @EnvironmentObject var viewModel: ExpenseViewModel
    @Environment(\.dismiss) private var dismiss
    let selectedDate: Date
    @State private var selectedCategoryFilter: Int = -1 // -1 = 全て, その他はカテゴリID
    @State private var selectedExpenseId: Int? = nil
    @State private var scrollOffset: CGFloat = 0
    
    private var availableCategories: [(id: Int, name: String)] {
        let calendar = Calendar.current
        let dailyExpenses = viewModel.expenses.filter { expense in
            calendar.isDate(expense.date, inSameDayAs: selectedDate)
        }
        // 当日使われたカテゴリ（支出/収入などタイプは問わない）
        let ids = Set(dailyExpenses.map { $0.categoryId })
        return viewModel.categories
            .filter { ids.contains($0.id) }
            .sorted { $0.name < $1.name }
    }
    
    private var filteredExpenses: [Expense] {
        let calendar = Calendar.current
        let dailyExpenses = viewModel.expenses.filter { expense in
            calendar.isDate(expense.date, inSameDayAs: selectedDate)
        }
        if selectedCategoryFilter == -1 {
            return dailyExpenses.sorted { $0.date > $1.date }
        } else {
            return dailyExpenses
                .filter { $0.categoryId == selectedCategoryFilter }
                .sorted { $0.date > $1.date }
        }
    }
    
    private var expenseTotal: Double {
        filteredExpenses
            .filter { $0.type == .expense }
            .reduce(0) { $0 + $1.amount }
    }
    
    private var incomeTotal: Double {
        filteredExpenses
            .filter { $0.type == .income }
            .reduce(0) { $0 + $1.amount }
    }
    
    private var netTotal: Double {
        incomeTotal - expenseTotal
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月d日(E)"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter
    }
    
    private var shortDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日(E)"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter
    }
    
    private var isWeekend: Bool {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: selectedDate)
        return weekday == 1 || weekday == 7 // 日曜日(1) または 土曜日(7)
    }

    private var expenseSheetItem: Binding<ExpenseSheetItem?> {
        Binding(
            get: {
                selectedExpenseId.map { ExpenseSheetItem(id: $0) }
            },
            set: { _ in
                selectedExpenseId = nil
            }
        )
    }

    private func refreshAfterEdit() {
        // 編集後に最新データを反映
        viewModel.refreshAllData()
    }
    
    var body: some View {
        // Collapsible behavior tuning
        let collapseThreshold: CGFloat = 120
        let topInfoHeight: CGFloat = 92
        let summaryBlockHeight: CGFloat = 96
        let categoryFilterHeight: CGFloat = availableCategories.isEmpty ? 0 : 150
        let headerPadding: CGFloat = 16

        let baseHeaderHeight = topInfoHeight + summaryBlockHeight + categoryFilterHeight + headerPadding
        let minHeaderHeight = topInfoHeight + categoryFilterHeight + headerPadding

        let progress = min(1, max(0, scrollOffset / collapseThreshold))
        let currentHeaderHeight = max(minHeaderHeight, baseHeaderHeight - (summaryBlockHeight * progress))

        ZStack {
            // Main scroll content
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    // Track scroll offset
                    GeometryReader { geo in
                        Color.clear
                            .preference(key: ScrollOffsetKey.self,
                                        value: geo.frame(in: .named("dailyDetailScroll")).minY)
                    }
                    .frame(height: 0)

                    // Reserve space for overlay header (dynamic height so the list expands when header collapses)
                    Spacer().frame(height: currentHeaderHeight + 8)

                    // Expense rows
                    LazyVStack(spacing: 0) {
                        ForEach(filteredExpenses) { expense in
                            VStack(spacing: 0) {
                                DailyDetailRowView(
                                    expense: expense,
                                    categories: viewModel.categories,
                                    showCategory: selectedCategoryFilter == -1,
                                    viewModel: viewModel
                                )
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                    impactFeedback.impactOccurred()
                                    selectedExpenseId = expense.id
                                }

                                Divider()
                                    .opacity(0.35)
                            }
                        }
                    }
                }
            }
            .coordinateSpace(name: "dailyDetailScroll")
            .onPreferenceChange(ScrollOffsetKey.self) { value in
                // value is positive when pulling down, negative when scrolling up
                scrollOffset = max(0, -value)
            }
            .overlay(alignment: .top) {
                DailyDetailCollapsibleHeader(
                    selectedDate: selectedDate,
                    expenseTotal: expenseTotal,
                    incomeTotal: incomeTotal,
                    netTotal: netTotal,
                    transactionCount: filteredExpenses.count,
                    isWeekend: isWeekend,
                    selectedCategoryName: selectedCategoryFilter == -1 ? nil :
                        availableCategories.first(where: { $0.id == selectedCategoryFilter })?.name,
                    availableCategories: availableCategories,
                    selectedCategoryFilter: $selectedCategoryFilter,
                    viewModel: viewModel,
                    collapseProgress: progress,
                    headerHeight: currentHeaderHeight,
                    summaryBlockHeight: summaryBlockHeight
                )
                .padding(.horizontal)
                .padding(.top, 8)
            }

            // Floating bottom buttons (元のまま)
            VStack {
                Spacer()
                HStack(spacing: 16) {
                    if #available(iOS 26.0, *) {
                        Button(action: {
                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                            impactFeedback.impactOccurred()

                            let noon = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: selectedDate) ?? selectedDate
                            viewModel.pendingInputDate = noon
                            NotificationCenter.default.post(name: .switchTab, object: nil, userInfo: ["index": 2])
                            dismiss()
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 20))
                                Text("この日に追加")
                                    .fontWeight(.semibold)
                            }
                            .frame(width: 200, height: 48)
                        }
                        .buttonStyle(.glassProminent)

                        Button(action: {
                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                            impactFeedback.impactOccurred()
                            dismiss()
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 20))
                                .frame(width: 48, height: 48)
                        }
                        .buttonStyle(.glass)
                    } else {
                        Button(action: {
                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                            impactFeedback.impactOccurred()

                            let noon = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: selectedDate) ?? selectedDate
                            viewModel.pendingInputDate = noon
                            NotificationCenter.default.post(name: .switchTab, object: nil, userInfo: ["index": 2])
                            dismiss()
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 20))
                                Text("この日に追加")
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.white)
                            .background(Color.blue)
                            .cornerRadius(24)
                            .frame(width: 200, height: 48)
                        }

                        Button(action: {
                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                            impactFeedback.impactOccurred()
                            dismiss()
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                                .background(Color.orange)
                                .cornerRadius(24)
                                .frame(width: 48, height: 48)
                        }
                    }
                }
                .padding(.bottom, 30)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .navigationTitle("\(shortDateFormatter.string(from: selectedDate))の支出")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: expenseSheetItem, onDismiss: refreshAfterEdit) { item in
            NavigationStack {
                EditExpenseView(expenseId: item.id)
                    .environmentObject(viewModel)
            }
            .accessibilityLabel("支出編集画面")
        }
        .overlay {
            if filteredExpenses.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: isWeekend ? "calendar" : "calendar.badge.exclamationmark")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)

                    if selectedCategoryFilter == -1 {
                        Text("\(shortDateFormatter.string(from: selectedDate))の支出がありません")
                            .font(.headline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    } else {
                        let categoryName = availableCategories.first(where: { $0.id == selectedCategoryFilter })?.name ?? "不明"
                        Text("\(shortDateFormatter.string(from: selectedDate))の\(categoryName)の支出がありません")
                            .font(.headline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    Text("「入力」タブから支出を追加してください")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
        }
    }
}

// MARK: - Collapsible header (DailyDetailView)
struct DailyDetailCollapsibleHeader: View {
    let selectedDate: Date
    let expenseTotal: Double
    let incomeTotal: Double
    let netTotal: Double
    let transactionCount: Int
    let isWeekend: Bool
    let selectedCategoryName: String?

    let availableCategories: [(id: Int, name: String)]
    @Binding var selectedCategoryFilter: Int
    let viewModel: ExpenseViewModel

    /// 0.0 = expanded, 1.0 = collapsed
    let collapseProgress: CGFloat

    let headerHeight: CGFloat
    let summaryBlockHeight: CGFloat

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月d日(E)"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter
    }

    private var dayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter
    }

    private var weekdayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter
    }

    var body: some View {
        let p = min(1, max(0, collapseProgress))

        VStack(spacing: 12) {
            // Top date info (always visible)
            HStack(spacing: 12) {
                VStack(spacing: 2) {
                    Text(dayFormatter.string(from: selectedDate))
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    Text(weekdayFormatter.string(from: selectedDate))
                        .font(.caption)
                        .foregroundColor(.white)
                }
                .frame(width: 60, height: 60)
                .background(isWeekend ? Color.red : Color.blue)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(dateFormatter.string(from: selectedDate))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)

                    Text("この日の支出詳細")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    if let categoryName = selectedCategoryName {
                        Text("カテゴリ: \(categoryName)")
                            .font(.caption)
                            .foregroundColor(isWeekend ? .red : .blue)
                            .fontWeight(.medium)
                    }
                }

                Spacer()
            }

            // Collapsible summary block
            DailyDetailSummaryBlockView(
                expenseTotal: expenseTotal,
                incomeTotal: incomeTotal,
                netTotal: netTotal,
                transactionCount: transactionCount,
                isWeekend: isWeekend
            )
            .opacity(Double(1 - p))
            .frame(height: max(0, summaryBlockHeight * (1 - p)))
            .clipped()
            .accessibilityHidden(p > 0.95)

            // Category menu (always visible, moves up as summary collapses)
            if !availableCategories.isEmpty {
                CategoryFilterView(
                    availableCategories: availableCategories,
                    selectedCategoryFilter: $selectedCategoryFilter,
                    viewModel: viewModel
                )
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 12)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .top)
        .frame(height: headerHeight, alignment: .top)
        .background {
            if #available(iOS 26.0, *) {
                Color.clear
                    .glassEffect(
                        .regular.tint((isWeekend ? Color.red : Color.blue).opacity(0.18)).interactive(),
                        in: .rect(cornerRadius: 16)
                    )
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.gray.opacity(0.18), lineWidth: 1)
                    )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct DailyDetailSummaryBlockView: View {
    let expenseTotal: Double
    let incomeTotal: Double
    let netTotal: Double
    let transactionCount: Int
    let isWeekend: Bool

    var body: some View {
        if #available(iOS 26.0, *) {
            HStack(spacing: 0) {
                VStack(spacing: 4) {
                    Text("支出").font(.caption).foregroundColor(.secondary)
                    Text("¥\(expenseTotal, specifier: "%.0f")")
                        .font(.title3).fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)

                Rectangle().fill(Color.gray.opacity(0.3)).frame(width: 1, height: 40)

                VStack(spacing: 4) {
                    Text("収入").font(.caption).foregroundColor(.secondary)
                    Text("¥\(incomeTotal, specifier: "%.0f")")
                        .font(.title3).fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)

                Rectangle().fill(Color.gray.opacity(0.3)).frame(width: 1, height: 40)

                VStack(spacing: 4) {
                    Text("差額").font(.caption).foregroundColor(.secondary)
                    Text("\(netTotal >= 0 ? "+" : "-")¥\(abs(netTotal), specifier: "%.0f")")
                        .font(.title3).fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)

                Rectangle().fill(Color.gray.opacity(0.3)).frame(width: 1, height: 40)

                VStack(spacing: 4) {
                    Text("件数").font(.caption).foregroundColor(.secondary)
                    Text("\(transactionCount)件")
                        .font(.title3).fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .padding()
            .glassEffect(.regular.tint(isWeekend ? .red : .blue).interactive(),
                         in: .rect(cornerRadius: 12))
        } else {
            HStack(spacing: 0) {
                VStack(spacing: 4) {
                    Text("支出").font(.caption).foregroundColor(.secondary)
                    Text("¥\(expenseTotal, specifier: "%.0f")")
                        .font(.title3).fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)

                Rectangle().fill(Color.gray.opacity(0.3)).frame(width: 1, height: 40)

                VStack(spacing: 4) {
                    Text("収入").font(.caption).foregroundColor(.secondary)
                    Text("¥\(incomeTotal, specifier: "%.0f")")
                        .font(.title3).fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)

                Rectangle().fill(Color.gray.opacity(0.3)).frame(width: 1, height: 40)

                VStack(spacing: 4) {
                    Text("差額").font(.caption).foregroundColor(.secondary)
                    Text("\(netTotal >= 0 ? "+" : "-")¥\(abs(netTotal), specifier: "%.0f")")
                        .font(.title3).fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)

                Rectangle().fill(Color.gray.opacity(0.3)).frame(width: 1, height: 40)

                VStack(spacing: 4) {
                    Text("件数").font(.caption).foregroundColor(.secondary)
                    Text("\(transactionCount)件")
                        .font(.title3).fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill((isWeekend ? Color.red : Color.blue).opacity(0.1))
                    .stroke((isWeekend ? Color.red : Color.blue).opacity(0.3), lineWidth: 1)
            )
        }
    }
}

struct DailyDetailHeaderView: View {
    let selectedDate: Date
    let expenseTotal: Double
    let incomeTotal: Double
    let netTotal: Double
    let transactionCount: Int
    let isWeekend: Bool
    let selectedCategoryName: String?
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月d日(E)"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter
    }
    
    private var dayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter
    }
    
    private var weekdayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // 日付アイコンと情報
            HStack(spacing: 12) {
                VStack(spacing: 2) {
                    Text(dayFormatter.string(from: selectedDate))
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    Text(weekdayFormatter.string(from: selectedDate))
                        .font(.caption)
                        .foregroundColor(.white)
                }
                .frame(width: 60, height: 60)
                .background(isWeekend ? Color.red : Color.blue)
                .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(dateFormatter.string(from: selectedDate))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text("この日の支出詳細")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    if let categoryName = selectedCategoryName {
                        Text("カテゴリ: \(categoryName)")
                            .font(.caption)
                            .foregroundColor(isWeekend ? .red : .blue)
                            .fontWeight(.medium)
                    }
                }
                
                Spacer()
            }
            
            if #available(iOS 26.0, *) {
                HStack(spacing: 0) {
                    // 支出
                    VStack(spacing: 4) {
                        Text("支出")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("¥\(expenseTotal, specifier: "%.0f")")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                    }
                    .frame(maxWidth: .infinity)

                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 1, height: 40)

                    // 収入
                    VStack(spacing: 4) {
                        Text("収入")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("¥\(incomeTotal, specifier: "%.0f")")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                    }
                    .frame(maxWidth: .infinity)

                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 1, height: 40)

                    // 差額
                    VStack(spacing: 4) {
                        Text("差額")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(netTotal >= 0 ? "+" : "-")¥\(abs(netTotal), specifier: "%.0f")")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                    }
                    .frame(maxWidth: .infinity)

                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 1, height: 40)

                    // 件数
                    VStack(spacing: 4) {
                        Text("件数")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(transactionCount)件")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding()
                .glassEffect(.regular.tint(isWeekend ? .red : .blue).interactive(), in: .rect(cornerRadius: 12))
            } else {
                HStack(spacing: 0) {
                    // 支出
                    VStack(spacing: 4) {
                        Text("支出")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("¥\(expenseTotal, specifier: "%.0f")")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                    }
                    .frame(maxWidth: .infinity)

                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 1, height: 40)

                    // 収入
                    VStack(spacing: 4) {
                        Text("収入")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("¥\(incomeTotal, specifier: "%.0f")")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                    }
                    .frame(maxWidth: .infinity)

                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 1, height: 40)

                    // 差額
                    VStack(spacing: 4) {
                        Text("差額")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(netTotal >= 0 ? "+" : "-")¥\(abs(netTotal), specifier: "%.0f")")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                    }
                    .frame(maxWidth: .infinity)

                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 1, height: 40)

                    // 件数
                    VStack(spacing: 4) {
                        Text("件数")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(transactionCount)件")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill((isWeekend ? Color.red : Color.blue).opacity(0.1))
                        .stroke((isWeekend ? Color.red : Color.blue).opacity(0.3), lineWidth: 1)
                )
            }
        }
    }
}

struct CategoryFilterView: View {
    let availableCategories: [(id: Int, name: String)]
    @Binding var selectedCategoryFilter: Int
    let viewModel: ExpenseViewModel
    
    private func categoryIcon(_ categoryName: String) -> String {
        // カテゴリ名からIDを取得してから動的に取得
        if let category = viewModel.categories.first(where: { $0.name == categoryName }) {
            return viewModel.categoryIcon(for: category.id)
        }
        return "tag.fill"  // フォールバック
    }
    
    private func categoryColor(_ categoryName: String) -> Color {
        // カテゴリ名からIDを取得してから動的に取得
        if let category = viewModel.categories.first(where: { $0.name == categoryName }) {
            let colorString = viewModel.categoryColor(for: category.id)
            return colorFromString(colorString)
        }
        return .gray  // フォールバック
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
        VStack(alignment: .leading, spacing: 12) {
            Text("カテゴリで絞り込み")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // 全て表示ボタン
                    Button(action: {
                        selectedCategoryFilter = -1
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "list.bullet")
                                .font(.caption)
                            Text("全て")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(selectedCategoryFilter == -1 ? Color.blue : Color.gray.opacity(0.2))
                        )
                        .foregroundColor(selectedCategoryFilter == -1 ? .white : .primary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // カテゴリボタン
                    ForEach(availableCategories, id: \.id) { category in
                        Button(action: {
                            selectedCategoryFilter = category.id
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: categoryIcon(category.name))
                                    .font(.caption)
                                Text(category.name)
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(selectedCategoryFilter == category.id ?
                                          categoryColor(category.name) : Color.gray.opacity(0.2))
                            )
                            .foregroundColor(selectedCategoryFilter == category.id ? .white : .primary)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.05))
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
}

struct DailyDetailRowView: View {
    let expense: Expense
    let categories: [(id: Int, name: String)]
    let showCategory: Bool
    let viewModel: ExpenseViewModel
    
    // 修正: 日時表示を「M/d HH:mm」形式に統一
    private var dateTimeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d HH:mm"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter
    }
    
    private var categoryName: String {
        viewModel.categoryNameTyped(for: expense.categoryId)
    }
    
    private var categoryIcon: String {
        return viewModel.categoryIcon(for: expense.categoryId)
    }
    
    private var categoryColor: Color {
        let colorString = viewModel.categoryColor(for: expense.categoryId)
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
                    .frame(width: 40, height: 40)
                    .background(categoryColor)
                    .clipShape(Circle())
            }
            
            // 支出情報
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("¥\(expense.amount, specifier: "%.0f")")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    // 修正: 日時表示を統一フォーマットに変更
                    Text("\(expense.date, formatter: dateTimeFormatter)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if showCategory {
                    Text(categoryName)
                        .font(.subheadline)
                        .foregroundColor(categoryColor)
                        .fontWeight(.medium)
                }
                
                if !expense.note.isEmpty {
                    Text(expense.note)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                } else {
                    Text("メモなし")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .italic()
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct DailyDetailView_Previews: PreviewProvider {
    static var previews: some View {
        DailyDetailView(selectedDate: Date())
            .environmentObject(ExpenseViewModel())
    }
}
