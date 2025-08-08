//
//  CategoryDetailView.swift
//  Suguni-Kakeibo-2
//
//  Created by AI Assistant on 2025/08/05.
//

import SwiftUI

struct CategoryDetailView: View {
    @EnvironmentObject var viewModel: ExpenseViewModel
    let categoryName: String
    let categoryId: Int
    let selectedMonth: Date
    
    // 1. 動的にアイコンを取得するプロパティを追加
    private var categoryIcon: String {
        return viewModel.categoryIcon(for: categoryId)
    }

    // 2. 動的に色を取得するプロパティを追加
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
    
    private var filteredExpenses: [Expense] {
        let calendar = Calendar.current
        let targetMonth = calendar.component(.month, from: selectedMonth)
        let targetYear = calendar.component(.year, from: selectedMonth)
        
        return viewModel.expenses.filter { expense in
            let month = calendar.component(.month, from: expense.date)
            let year = calendar.component(.year, from: expense.date)
            return month == targetMonth && year == targetYear && expense.categoryId == categoryId
        }.sorted { $0.date > $1.date }
    }
    
    private var totalAmount: Double {
        filteredExpenses.reduce(0) { $0 + $1.amount }
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
                // ヘッダー情報
                CategoryDetailHeaderView(
                    categoryName: categoryName,
                    categoryIcon: categoryIcon,
                    categoryColor: categoryColor,
                    selectedMonth: selectedMonth,
                    totalAmount: totalAmount,
                    expenseCount: filteredExpenses.count
                )
                .padding(.horizontal)
                .padding(.bottom, 16)
                
                // 支出履歴リスト
                List {
                    ForEach(filteredExpenses) { expense in
                        CategoryDetailRowView(
                            expense: expense,
                            categoryColor: categoryColor
                        )
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("\(categoryName)の詳細")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable {
                viewModel.fetchExpenses()
            }
            .overlay {
                if filteredExpenses.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: categoryIcon)
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text("\(monthFormatter.string(from: selectedMonth))の\(categoryName)の支出がありません")
                            .font(.headline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Text("「入力」タブから支出を追加してください")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                }
            }
        }
    }
}

struct CategoryDetailHeaderView: View {
    let categoryName: String
    let categoryIcon: String
    let categoryColor: Color
    let selectedMonth: Date
    let totalAmount: Double
    let expenseCount: Int
    
    private var monthFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // カテゴリアイコンと名前
            HStack(spacing: 12) {
                Image(systemName: categoryIcon)
                    .font(.largeTitle)
                    .foregroundColor(.white)
                    .frame(width: 60, height: 60)
                    .background(categoryColor)
                    .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(categoryName)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text("\(monthFormatter.string(from: selectedMonth))の支出")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            // 統計情報
            HStack(spacing: 0) {
                // 合計金額
                VStack(spacing: 4) {
                    Text("合計金額")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("¥\(totalAmount, specifier: "%.0f")")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(categoryColor)
                }
                .frame(maxWidth: .infinity)
                
                // 区切り線
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 1, height: 40)
                
                // 支出回数
                VStack(spacing: 4) {
                    Text("支出回数")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(expenseCount)回")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(categoryColor)
                }
                .frame(maxWidth: .infinity)
                
                // 区切り線
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 1, height: 40)
                
                // 平均金額
                VStack(spacing: 4) {
                    Text("平均金額")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("¥\(expenseCount > 0 ? totalAmount / Double(expenseCount) : 0, specifier: "%.0f")")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(categoryColor)
                }
                .frame(maxWidth: .infinity)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(categoryColor.opacity(0.1))
                    .stroke(categoryColor.opacity(0.3), lineWidth: 1)
            )
        }
    }
}

struct CategoryDetailRowView: View {
    let expense: Expense
    let categoryColor: Color
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日(E)"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter
    }
    
    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // 日付アイコン
            VStack(spacing: 2) {
                Text("\(Calendar.current.component(.day, from: expense.date))")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Text(getDayOfWeek())
                    .font(.caption2)
                    .foregroundColor(.white)
            }
            .frame(width: 40, height: 40)
            .background(categoryColor)
            .clipShape(Circle())
            
            // 支出情報
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("¥\(expense.amount, specifier: "%.0f")")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Text("\(expense.date, formatter: dateFormatter)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if !expense.note.isEmpty {
                    Text(expense.note)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                } else {
                    Text("メモなし")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .italic()
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func getDayOfWeek() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: expense.date)
    }
}

struct CategoryDetailView_Previews: PreviewProvider {
    static var previews: some View {
        CategoryDetailView(
            categoryName: "食費",
            categoryId: 1,
            selectedMonth: Date()
        )
        .environmentObject(ExpenseViewModel())
    }
}
