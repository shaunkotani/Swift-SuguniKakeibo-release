//
//  ContentView.swift (TabView再タップ機能追加版)
//  家計簿アプリ

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ExpenseViewModel()
    @State private var shouldFocusAmount: Bool = false
    @State private var selectedTab: Int = 0
    
    // TabView再タップ検出用の状態
    @State private var previousSelectedTab: Int = 0
    @State private var lastTapTime: Date = Date()
    
    var body: some View {
        TabView(selection: $selectedTab) {
            CalendarView(
                selectedTab: $selectedTab,
                shouldFocusAmount: $shouldFocusAmount
            )
            .environmentObject(viewModel)
            .tabItem {
                Label("日別集計", systemImage: "calendar")
            }
            .tag(0)

            CategorySummaryView(
                selectedTab: $selectedTab,
                shouldFocusAmount: $shouldFocusAmount
            )
            .environmentObject(viewModel)
            .tabItem {
                Label("カテゴリ集計", systemImage: "chart.pie")
            }
            .tag(1)

            InputView(shouldFocusAmount: $shouldFocusAmount)
                .environmentObject(viewModel)
                .tabItem {
                    Label("入力", systemImage: "plus.circle")
                }
                .tag(2)

            ExpensesView()
                .environmentObject(viewModel)
                .tabItem {
                    Label("履歴と編集", systemImage: "list.bullet")
                }
                .tag(3)

            SettingView()
                .environmentObject(viewModel)
                .tabItem {
                    Label("設定", systemImage: "gear")
                }
                .tag(4)
        }
        .onChange(of: selectedTab) { oldValue, newValue in
            handleTabChange(from: oldValue, to: newValue)
        }
    }
    
    private func handleTabChange(from oldTab: Int, to newTab: Int) {
        let now = Date()
        let timeDifference = now.timeIntervalSince(lastTapTime)
        
        // 入力タブ（2）が選択された場合の処理
        if newTab == 2 {
            // 既に入力タブが選択されていて、0.5秒以内に再タップされた場合
            if oldTab == 2 && timeDifference < 0.5 {
                // 金額フィールドにフォーカス
                shouldFocusAmount = true
                
                // ハプティックフィードバック
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
                
                print("💰 入力タブ再タップ - 金額フィールドにフォーカス")
            }
        }
        
        // 現在の時刻を記録
        lastTapTime = now
        previousSelectedTab = oldTab
    }
    
    // 他のビューから呼び出せる関数（既存機能を維持）
    func navigateToInputWithFocus() {
        // 入力タブに切り替え
        selectedTab = 2
        
        // 少し遅延してからフォーカス
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            shouldFocusAmount = true
        }
        
        print("📱 支出追加ボタンから入力画面へ遷移")
    }
}
