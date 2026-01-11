//
//  SavingsView.swift
//  かるい家計簿！
//
//  Created by 大谷駿介 on 2026/01/12.
//

import SwiftUI

/// 「貯金チェック（今月）」を独立Viewとして切り出したもの
/// - 単体タブとしても、他のForm内のパーツとしても使えるようにしています。
struct SavingsView: View {
    @ObservedObject var store: MemoStoreModel

    var body: some View {
        NavigationStack {
            Form {
                SavingsCheckSection(store: store)
            }
            .navigationTitle("貯金")
        }
    }
}

/// Form内で再利用できる「貯金チェック（今月）」セクション
struct SavingsCheckSection: View {
    @ObservedObject var store: MemoStoreModel

    var body: some View {
        Section(
            header: Text("貯金チェック（今月）"),
            footer: Text("翌月になるとチェックが外れます")
                .foregroundColor(.secondary)
        ) {
            HStack {
                Text("目標")
                Spacer()
                TextField("30000", value: $store.savingsTargetAmount, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                Text("円")
                    .foregroundColor(.secondary)
            }

            Toggle(isOn: $store.savingsCheckedThisMonth) {
                Text("今月、貯金できた")
            }
        }
    }
}

#Preview {
    SavingsView(store: MemoStoreModel())
}
