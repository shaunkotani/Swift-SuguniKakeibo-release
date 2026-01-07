//
//  DailyDetailView.swift (修正版)
//  Suguni-Kakeibo-2
//

import SwiftUI

// NOTE: カテゴリは支出/収入で別管理されることを想定。ViewModel 側の typed API に対応。

struct DailyDetailView: View {
    @EnvironmentObject var viewModel: ExpenseViewModel
    @Environment(\.dismiss) private var dismiss
    let selectedDate: Date
    @State private var selectedCategoryFilter: Int = -1 // -1 = 全て, その他はカテゴリID
    
    private var availableCategories: [(id: Int, name: String)] {
        let calendar = Calendar.current
        let dailyExpenses = viewModel.expenses.filter { expense in
            calendar.isDate(expense.date, inSameDayAs: selectedDate)
        }
        // その日のタイプ（支出/収入）を推定
        let activeType: TransactionType = {
            if let first = filteredExpenses.first { return first.type }
            if let any = dailyExpenses.first { return any.type }
            return .expense
        }()
        // タイプ別カテゴリ（当日使われたカテゴリのみ）
        let idsOfType = Set(dailyExpenses.filter { $0.type == activeType }.map { $0.categoryId })
        let typedCategories = viewModel.categoriesByType(activeType)
        return typedCategories.filter { idsOfType.contains($0.id) }.sorted { $0.name < $1.name }
    }
    
    private var filteredExpenses: [Expense] {
        let calendar = Calendar.current
        let dailyExpenses = viewModel.expenses.filter { expense in
            calendar.isDate(expense.date, inSameDayAs: selectedDate)
        }
        // 選択カテゴリからタイプを優先推定
        let activeType: TransactionType = {
            if selectedCategoryFilter != -1 {
                return viewModel.categoryType(for: selectedCategoryFilter)
            }
            return dailyExpenses.first?.type ?? .expense
        }()
        let typed = dailyExpenses.filter { $0.type == activeType }
        if selectedCategoryFilter == -1 {
            return typed.sorted { $0.date > $1.date }
        } else {
            return typed.filter { $0.categoryId == selectedCategoryFilter }.sorted { $0.date > $1.date }
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
    
    var body: some View {
        ZStack {
            VStack {
                // ヘッダー情報
                DailyDetailHeaderView(
                    selectedDate: selectedDate,
                    expenseTotal: expenseTotal,
                    incomeTotal: incomeTotal,
                    netTotal: netTotal,
                    transactionCount: filteredExpenses.count,
                    isWeekend: isWeekend,
                    selectedCategoryName: selectedCategoryFilter == -1 ? nil : availableCategories.first(where: { $0.id == selectedCategoryFilter })?.name
                )
                .padding(.horizontal)
                .padding(.bottom, 16)
                
                // カテゴリフィルター
                if !availableCategories.isEmpty {
                    CategoryFilterView(
                        availableCategories: availableCategories,
                        selectedCategoryFilter: $selectedCategoryFilter,
                        viewModel: viewModel
                    )
                    .padding(.horizontal)
                    .padding(.bottom, 16)
                }
                
                // 支出履歴リスト
                List {
                    ForEach(filteredExpenses) { expense in
                        DailyDetailRowView(
                            expense: expense,
                            categories: viewModel.categories,
                            showCategory: selectedCategoryFilter == -1,
                            viewModel: viewModel
                        )
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            }
            
            VStack {
                Spacer()
                HStack(spacing: 16) {
                    if #available(iOS 26.0, *) {
                        Button(action: {
                            // この日に追加: 入力タブへ遷移し、日付を12:00で設定
                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                            impactFeedback.impactOccurred()
                            
                            // 12:00 に補正
                            let noon = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: selectedDate) ?? selectedDate
                            
                            // ViewModelへ指示
                            viewModel.pendingInputDate = noon
                            
                            // 入力タブへ遷移を通知（タブ選択はContentViewのバインディング経由のため通知で指示）
                            NotificationCenter.default.post(name: .switchTab, object: nil, userInfo: ["index": 2])
                            
                            // 画面を閉じる
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
                            // この日に追加: 入力タブへ遷移し、日付を12:00で設定
                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                            impactFeedback.impactOccurred()
                            
                            // 12:00 に補正
                            let noon = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: selectedDate) ?? selectedDate
                            
                            // ViewModelへ指示
                            viewModel.pendingInputDate = noon
                            
                            // 入力タブへ遷移を通知（タブ選択はContentViewのバインディング経由のため通知で指示）
                            NotificationCenter.default.post(name: .switchTab, object: nil, userInfo: ["index": 2])
                            
                            // 画面を閉じる
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
