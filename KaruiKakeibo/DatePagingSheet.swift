// 日付ごとに水平スワイプ可能なシート用ページングビュー
import SwiftUI

struct DatePagingSheet: View {
    @Binding var dates: [Date]
    @Binding var selectedIndex: Int

    private let calendar = Calendar.current

    var body: some View {
        if !dates.isEmpty {
            NavigationStack{
                TabView(selection: $selectedIndex) {
                    ForEach(dates.indices, id: \.self) { idx in
                        DailyDetailView(selectedDate: dates[idx])
                            .tag(idx)
                    }
                }
                .tabViewStyle(.page)
            }
            .onAppear {
                clampIndex()
                extendIfNeededAtMonthEdges()
            }
            .onChange(of: dates.count) { _, _ in
                clampIndex()
            }
            .onChange(of: selectedIndex) { _, _ in
                DispatchQueue.main.async {
                    extendIfNeededAtMonthEdges()
                }
            }
        } else {
            VStack(spacing: 16) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.largeTitle)
                    .foregroundColor(.gray)
                Text("日付データがありません。カレンダーから日付を選択してください。")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.gray)
            }
            .padding()
        }
            
    }

    private func clampIndex() {
        if selectedIndex < 0 || selectedIndex >= dates.count {
            selectedIndex = 0
        }
    }

    /// 今見ている日が「月初 or 月末」なら、前月/次月の日付を dates に追加
    private func extendIfNeededAtMonthEdges() {
        guard dates.indices.contains(selectedIndex) else { return }

        let current = calendar.startOfDay(for: dates[selectedIndex])

        // 今の月の 1日 と 末日
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: current))!
        let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart)!

        // 月初に到達 → 前月を prepend（先頭に入るので selectedIndex をずらす）
        if calendar.isDate(current, inSameDayAs: monthStart) {
            let prevMonthStart = calendar.date(byAdding: .month, value: -1, to: monthStart)!
            // すでに前月を追加済みなら何もしない
            if dates.contains(where: { calendar.isDate($0, inSameDayAs: prevMonthStart) }) { return }

            let prevMonthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: prevMonthStart)!
            let newDates = enumerateDays(from: prevMonthStart, to: prevMonthEnd)

            dates.insert(contentsOf: newDates, at: 0)
            selectedIndex += newDates.count
            return
        }

        // 月末に到達 → 次月を append
        if calendar.isDate(current, inSameDayAs: monthEnd) {
            let nextMonthStart = calendar.date(byAdding: .month, value: 1, to: monthStart)!
            // すでに次月を追加済みなら何もしない
            if dates.contains(where: { calendar.isDate($0, inSameDayAs: nextMonthStart) }) { return }

            let nextMonthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: nextMonthStart)!
            let newDates = enumerateDays(from: nextMonthStart, to: nextMonthEnd)

            dates.append(contentsOf: newDates)
        }
    }

    private func enumerateDays(from start: Date, to end: Date) -> [Date] {
        var out: [Date] = []
        var d = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        while d <= last {
            out.append(d)
            d = calendar.date(byAdding: .day, value: 1, to: d)!
        }
        return out
    }
}
