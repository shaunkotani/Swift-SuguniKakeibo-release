//
//  ContentView.swift (修正版)
//  ダブルタップでフォーカス機能を追加

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ExpenseViewModel()
    @State private var shouldFocusAmount: Bool = false
    @State private var selectedTab: Int = 0
    
    // ダブルタップ検出用の状態
    @State private var lastTapTime: Date = Date()
    @State private var tapCount: Int = 0
    
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
                    Label("履歴", systemImage: "list.bullet")
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
            // 入力タブが選択されたときの処理
            if newValue == 2 {
                handleInputTabSelection()
            }
        }
    }
    
    private func handleInputTabSelection() {
        let now = Date()
        let timeDifference = now.timeIntervalSince(lastTapTime)
        
        // 0.5秒以内の連続タップをダブルタップとして検出
        if timeDifference < 0.5 && selectedTab == 2 {
            tapCount += 1
            if tapCount >= 2 {
                // ダブルタップ検出
                shouldFocusAmount = true
                tapCount = 0
                
                // ハプティックフィードバック
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
                
                print("💰 入力タブをダブルタップ - 金額フィールドにフォーカス")
            }
        } else {
            tapCount = 1
        }
        
        lastTapTime = now
        
        // タップカウントをリセット（1秒後）
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            tapCount = 0
        }
    }
    
    // 他のビューから呼び出せる関数
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
