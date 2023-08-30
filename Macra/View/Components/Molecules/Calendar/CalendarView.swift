//
//  CalendarView.swift
//  PuppySchool
//
//  Created by Tremaine Grant on 7/22/23.
//

import SwiftUI

class CalendarViewModel: ObservableObject {
    @Published var appCoordinator: AppCoordinator
    @Published var selectedYear: Int = Calendar.current.component(.year, from: Date())
    
    init(appCoordinator: AppCoordinator) {
        self.appCoordinator = appCoordinator
    }
}

struct CalendarView: View {
    @ObservedObject var viewModel: CalendarViewModel
    
    var body: some View {
        VStack {
            HStack {
                CloseButtonView {
                    viewModel.appCoordinator.closeModals()
                }
                Spacer()
            }
            .padding(.top, 50)
            .padding(.leading, 20)
            HStack {
                Menu {
                   Picker(selection: $viewModel.selectedYear) {
                       ForEach(filteredYears, id: \.self) { year in
                           Text(NumberFormatter.localizedString(from: NSNumber(value: year), number: .none)).tag(year)
                       }
                   } label: {}
               } label: {
                   ZStack {
                       Rectangle()
                           .fill(Color.ash)
                           .frame(width:200, height: 60)
                       HStack {
                           IconImage(.sfSymbol(.squareDownChev, color: .secondaryWhite))
                           Text(NumberFormatter.localizedString(from: NSNumber(value: viewModel.selectedYear), number: .none))
                               .foregroundColor(.secondaryWhite)
                               .font(.title)
                               .bold()
                       }
                   }
               }.id(viewModel.selectedYear)
            }
            .padding(.bottom, 40)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack {
                        ForEach(1..<13, id: \.self) { index in
                            let date = Calendar.current.date(from: DateComponents(year: viewModel.selectedYear, month: index))!
                            MonthView(date: date, workoutDates: workoutDates, onSelectDay: { date in
                              
                                // Call back for when day is selected
                                //viewModel.appCoordinator.closeModals()
                            })
                            .id(index)
                        }
                    }
                    .onAppear {
                        let currentMonth = Calendar.current.component(.month, from: Date())
                        if viewModel.selectedYear == Calendar.current.component(.year, from: Date()) {
                            proxy.scrollTo(currentMonth, anchor: .top)
                        } else {
                            proxy.scrollTo(1, anchor: .top) // Scroll to January for other years
                        }
                    }
                }
            }
        }
        .background(LinearGradient(gradient: Gradient(colors: [Color.primaryPurple, Color.primaryPurple]), startPoint: .bottom, endPoint: .top))
        .ignoresSafeArea(.all)
    }
    
    var workoutDates: Set<Date> {
        return Set([Date()])
    }
    
    var filteredYears: [Int] {
        return [2020]
    }
}

struct MonthView: View {
    let date: Date
    let workoutDates: Set<Date>
    let onSelectDay: (Date) -> Void
    
    var body: some View {
        VStack {
            Text(date.monthYearFormat)
                .foregroundColor(.secondaryWhite)
                .font(.title2)
                .bold()
            LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 7)) {
                ForEach(daysInMonth, id: \.self) { date in
                    VStack {
                        if workoutDates.contains(where: { $0.dayMonthYearFormat == date.dayMonthYearFormat }) {
                            ZStack {
                                Circle()
                                    .fill(Color.secondaryWhite)
                                    .frame(width: 40)
                                Text("\(date.dayFormat)")
                                    .foregroundColor(.primaryPurple)
                                    .font(.title2)
                            }
                            .onTapGesture {
                                onSelectDay(date)
                            }
                            
                        } else {
                            Text("\(date.dayFormat)")
                                .foregroundColor(.secondaryWhite)
                                .font(.title)
                        }
                        Spacer()
                    }
                }
            }
        }.padding()
    }
    
    var daysInMonth: [Date] {
        guard let range = Calendar.current.range(of: .day, in: .month, for: date) else { return [] }
        return range.map {
            Calendar.current.date(byAdding: .day, value: $0 - 1, to: date.startOfMonth)!
        }
    }
}

struct CalendarView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            CalendarView(viewModel: CalendarViewModel(appCoordinator: AppCoordinator(serviceManager: ServiceManager())  ))
        }
    }
}
