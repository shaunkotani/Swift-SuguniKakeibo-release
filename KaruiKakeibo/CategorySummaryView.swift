//
//  CategorySummaryView.swift
//  Suguni-Kakeibo-2
//
//  Created by 大谷駿介 on 2025/07/29.
//

import SwiftUI

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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 月選択ヘッダー
                MonthSelectorView(selectedMonth: $selectedMonth)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                
                // 合計金額表示
                TotalAmountHeaderView(
                    totalAmount: totalAmount,
                    selectedMonth: selectedMonth,
                    hasExpenses: hasAnyExpenses,
                    categoryTotals: categoryTotals
                )
                .padding(.horizontal)
                .padding(.bottom, 16)
                
                // カテゴリリストまたは空状態表示
                if hasAnyExpenses {
                    List(categoryTotals, id: \.categoryId) { item in
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
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                    .listStyle(.plain)
                    .refreshable {
                        await refreshData()
                    }
                } else {
                    // 空状態表示
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
            .navigationTitle("カテゴリ別集計")
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
