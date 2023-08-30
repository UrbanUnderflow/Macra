//
//  PieChartView.swift
//  FoodJournal
//
//  Created by Tremaine Grant on 8/29/23.
//

import Foundation
import SwiftUI

struct PieChartModel {
    var name: String
    var value: Double
}

struct PieChartView: View {
    var data: [PieChartModel]
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(0..<data.count) { index in
                    let total = data.map { $0.value }.reduce(0, +)
                    let start = data.prefix(index).map { $0.value }.reduce(0, +) / total
                    let end = start + data[index].value / total
                    PieChartSliceView(start: start, end: end, color: getColor(for: index))
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
    
    func getColor(for index: Int) -> Color {
        let colors = [Color.orange, Color.orange.opacity(0.7), Color.orange.opacity(0.4)]
        return colors[index % colors.count]
    }

}

struct PieChartSliceView: View {
    var start: Double
    var end: Double
    var color: Color
    
    var body: some View {
        GeometryReader { geometry in
            Circle()
                .trim(from: CGFloat(start), to: CGFloat(end))
                .stroke(color, lineWidth: min(geometry.size.width, geometry.size.height) / 2)
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 1))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
