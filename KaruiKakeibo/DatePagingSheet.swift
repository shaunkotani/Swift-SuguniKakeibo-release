// 日付ごとに水平スワイプ可能なシート用ページングビュー
import SwiftUI

struct DatePagingSheet: View {
    let dates: [Date]
    @Binding var selectedIndex: Int
    var body: some View {
        if !dates.isEmpty {
            TabView(selection: $selectedIndex) {
                ForEach(dates.indices, id: \.self) { idx in
                    DailyDetailView(selectedDate: dates[idx])
                        .tag(idx)
                }
            }
            .tabViewStyle(.page)
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
}
