//
//  ContentView.swift
//  StretchTextDemo
//
//  Created by João Pedro Torres on 20/10/26.
//

import StretchTextUI
import SwiftUI

struct ContentView: View {
    @State private var model = DemoModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading) {
                    Picker("Frase dobrada", selection: $model.mode) {
                        ForEach(FoldMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    StatusView(isWorking: model.isWorking, notice: model.notice)

                    StretchTextView(state: $model.state)
                }
                .padding()
            }
            .navigationTitle("StretchText")
            .task(id: model.mode) {
                await model.refold()
            }
        }
    }
}

#Preview {
    ContentView()
}
