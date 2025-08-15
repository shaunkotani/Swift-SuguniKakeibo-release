//
//  ContentView.swift (UITabBarController再選択対応版 - 修正版)
//  家計簿アプリ

import SwiftUI
import UIKit

// MARK: - 通知名（再選択イベントをSwiftUIに伝える）
extension Notification.Name {
    static let tabReselected = Notification.Name("TabReselectedNotification")
}

// MARK: - タブ識別子
enum AppTab: Int, CaseIterable {
    case calendar = 0
    case category = 1
    case input = 2
    case expenses = 3
    case settings = 4
    
    var title: String {
        switch self {
        case .calendar: return "日別集計"
        case .category: return "カテゴリ集計"
        case .input: return "入力"
        case .expenses: return "履歴と編集"
        case .settings: return "設定"
        }
    }
    
    var systemImage: String {
        switch self {
        case .calendar: return "calendar"
        case .category: return "chart.pie"
        case .input: return "plus.circle"
        case .expenses: return "list.bullet"
        case .settings: return "gear"
        }
    }
}

struct ContentView: View {
    @StateObject private var viewModel = ExpenseViewModel()
    @State private var shouldFocusAmount: Bool = false
    @State private var selectedTab: Int = AppTab.input.rawValue
    
    var body: some View {
        TabBarControllerRepresentable(
            calendarView: AnyView(CalendarView(
                selectedTab: $selectedTab,
                shouldFocusAmount: $shouldFocusAmount
            ).environmentObject(viewModel)),
            
            categoryView: AnyView(CategorySummaryView(
                selectedTab: $selectedTab,
                shouldFocusAmount: $shouldFocusAmount
            ).environmentObject(viewModel)),
            
            inputView: AnyView(InputView(
                shouldFocusAmount: $shouldFocusAmount
            ).environmentObject(viewModel)),
            
            expensesView: AnyView(ExpensesView()
                .environmentObject(viewModel)),
            
            settingsView: AnyView(SettingView()
                .environmentObject(viewModel))
        )
        .ignoresSafeArea()
    }
    
    // 他のビューから呼び出せる関数（既存機能を維持）
    func navigateToInputWithFocus() {
        // 入力タブに切り替え
        selectedTab = AppTab.input.rawValue
        
        // 少し遅延してからフォーカス
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            shouldFocusAmount = true
        }
        
        print("📱 支出追加ボタンから入力画面へ遷移")
    }
}

// MARK: - UIKit ラッパー（UITabBarControllerDelegate で再選択検知）
struct TabBarControllerRepresentable: UIViewControllerRepresentable {
    let calendarView: AnyView
    let categoryView: AnyView
    let inputView: AnyView
    let expensesView: AnyView
    let settingsView: AnyView
    
    func makeUIViewController(context: Context) -> UITabBarController {
        let tabBarController = UITabBarController()
        tabBarController.delegate = context.coordinator
        
        // 各タブをUIHostingControllerでラップ
        let calendarVC = UIHostingController(rootView: calendarView)
        calendarVC.tabBarItem = UITabBarItem(
            title: AppTab.calendar.title,
            image: UIImage(systemName: AppTab.calendar.systemImage),
            tag: AppTab.calendar.rawValue
        )
        
        let categoryVC = UIHostingController(rootView: categoryView)
        categoryVC.tabBarItem = UITabBarItem(
            title: AppTab.category.title,
            image: UIImage(systemName: AppTab.category.systemImage),
            tag: AppTab.category.rawValue
        )
        
        let inputVC = UIHostingController(rootView: inputView)
        inputVC.tabBarItem = UITabBarItem(
            title: AppTab.input.title,
            image: UIImage(systemName: AppTab.input.systemImage),
            tag: AppTab.input.rawValue
        )
        
        let expensesVC = UIHostingController(rootView: expensesView)
        expensesVC.tabBarItem = UITabBarItem(
            title: AppTab.expenses.title,
            image: UIImage(systemName: AppTab.expenses.systemImage),
            tag: AppTab.expenses.rawValue
        )
        
        let settingsVC = UIHostingController(rootView: settingsView)
        settingsVC.tabBarItem = UITabBarItem(
            title: AppTab.settings.title,
            image: UIImage(systemName: AppTab.settings.systemImage),
            tag: AppTab.settings.rawValue
        )
        
        tabBarController.viewControllers = [
            calendarVC, categoryVC, inputVC, expensesVC, settingsVC
        ]
        
        // デフォルトで入力タブを選択
        tabBarController.selectedIndex = AppTab.input.rawValue
        
        print("✅ UITabBarController 設定完了")
        return tabBarController
    }
    
    func updateUIViewController(_ uiViewController: UITabBarController, context: Context) {
        // 必要に応じて動的更新
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    // MARK: Coordinator = UITabBarControllerDelegate 実装
    final class Coordinator: NSObject, UITabBarControllerDelegate {
        func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
            print("🔄 shouldSelect 呼び出し")
            
            // 現在選択中のVCと、これから選択しようとしているVCが同一なら「再選択」
            if tabBarController.selectedViewController === viewController {
                print("🔥 タブ再選択を検出")
                
                // インデックスを特定
                if let viewControllers = tabBarController.viewControllers,
                   let index = viewControllers.firstIndex(where: { $0 === viewController }) {
                    print("📱 再選択されたタブインデックス: \(index)")
                    
                    // 通知を送信
                    NotificationCenter.default.post(
                        name: .tabReselected,
                        object: nil,
                        userInfo: ["index": index]
                    )
                }
            } else {
                print("🔄 通常のタブ選択")
            }
            
            return true // 選択自体は許可
        }
        
        func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
            if let index = tabBarController.viewControllers?.firstIndex(where: { $0 === viewController }) {
                print("🏷️ タブ選択完了: index \(index)")
            }
        }
    }
}
