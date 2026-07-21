import SwiftUI

struct OnboardingView: View {
    @Environment(AppStore.self) private var store

    @State private var page = 0
    @State private var nickname = ""
    @State private var goal: TrainingGoal = .recomposition
    @State private var secondaryGoal: SecondaryGoal = .none
    @State private var experience: ExperienceLevel = .autoAssess
    @State private var splitPreference: TrainingSplit = .automatic
    @State private var strengthTrainingGoal: StrengthTrainingGoal = .balanced
    @State private var cardioTrainingGoal: CardioTrainingGoal = .fatLoss
    @State private var weeklyDays = 3
    @State private var sessionMinutes = 60
    @State private var equipment: EquipmentProfile = .fullGym
    @State private var bodyWeight = 70.0
    @State private var ageYears = 30
    @State private var heightCm = 170
    @State private var biologicalSex: BiologicalSex = .notSet

    private let pageCount = 3

    var body: some View {
        ZStack {
            FitBackground()
            VStack(spacing: 0) {
                header
                ScrollView {
                    Group {
                        switch page {
                        case 0: goalPage
                        case 1: experiencePage
                        default: schedulePage
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 130)
                }
            }
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.title3.weight(.bold))
                .foregroundStyle(FitTheme.background)
                .frame(width: 42, height: 42)
                .background(FitTheme.accent, in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 2) {
                Text("FITTUNE")
                    .font(.headline.bold())
                    .tracking(1)
                Text("科学自适应训练")
                    .font(.caption)
                    .foregroundStyle(FitTheme.secondaryText)
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? FitTheme.accent : Color.white.opacity(0.16))
                        .frame(width: index == page ? 22 : 7, height: 7)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var goalPage: some View {
        VStack(spacing: 12) {
            SectionHeading(
                eyebrow: "第一步",
                title: "你现在最想改变什么？",
                detail: "选择一个主目标。次目标不会覆盖主目标。"
            )
            .padding(.bottom, 8)

            ForEach(TrainingGoal.allCases) { option in
                ChoiceCard(
                    symbol: option.symbol,
                    title: option.title,
                    subtitle: option.subtitle,
                    isSelected: goal == option
                ) { goal = option }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("可选次目标")
                    .font(.headline)
                Picker("次目标", selection: $secondaryGoal) {
                    ForEach(SecondaryGoal.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .tint(FitTheme.accent)
            }
            .fitCard()

            VStack(alignment: .leading, spacing: 14) {
                Text("基础消耗资料")
                    .font(.headline)
                valueStepper(title: "年龄", value: $ageYears, range: 14...100, suffix: "岁")
                valueStepper(title: "身高", value: $heightCm, range: 120...230, suffix: "cm")
                HStack {
                    Text("生理性别")
                    Spacer()
                    Picker("生理性别", selection: $biologicalSex) {
                        ForEach(BiologicalSex.allCases) { item in Text(item.title).tag(item) }
                    }
                    .tint(FitTheme.accent)
                }
                Text("仅用于 Mifflin–St Jeor 静息能量估算；未设置时不会猜测基础消耗。")
                    .font(.caption)
                    .foregroundStyle(FitTheme.secondaryText)
            }
            .fitCard()
            .padding(.top, 4)

            VStack(alignment: .leading, spacing: 13) {
                Text("分别设置两个训练模块")
                    .font(.headline)
                modulePicker(title: "力量训练", selection: $strengthTrainingGoal, options: StrengthTrainingGoal.allCases) { $0.title }
                Divider().overlay(Color.white.opacity(0.08))
                modulePicker(title: "有氧训练", selection: $cardioTrainingGoal, options: CardioTrainingGoal.allCases) { $0.title }
                Text("力量和有氧分别生成；减脂不再被塞进力量动作列表。")
                    .font(.caption)
                    .foregroundStyle(FitTheme.secondaryText)
            }
            .fitCard()
        }
    }

    private var experiencePage: some View {
        VStack(spacing: 12) {
            SectionHeading(
                eyebrow: "第二步",
                title: "选择你的训练经验",
                detail: "不知道也没关系，前几次训练可以自动校准。"
            )
            .padding(.bottom, 8)

            ForEach(ExperienceLevel.allCases) { option in
                ChoiceCard(
                    symbol: option.symbol,
                    title: option.title,
                    subtitle: option.subtitle,
                    isSelected: experience == option
                ) { experience = option }
            }
        }
    }

    private var schedulePage: some View {
        VStack(spacing: 18) {
            SectionHeading(
                eyebrow: "第三步",
                title: "让计划适合你的生活",
                detail: "这些选项以后都能修改并重新生成计划。"
            )

            VStack(alignment: .leading, spacing: 16) {
                TextField("怎么称呼你（可选）", text: $nickname)
                    .textInputAutocapitalization(.never)
                    .padding(14)
                    .background(FitTheme.elevated, in: RoundedRectangle(cornerRadius: 14))

                valueStepper(title: "每周力量训练", value: $weeklyDays, range: minimumTrainingDays...6, suffix: "天")
                valueStepper(title: "每次时长", value: $sessionMinutes, range: 30...90, step: 15, suffix: "分钟")
            }
            .fitCard()

            VStack(alignment: .leading, spacing: 12) {
                Text("训练分化")
                    .font(.headline)
                Picker("训练分化", selection: $splitPreference) {
                    ForEach(TrainingSplit.allCases) { split in
                        Text(split.title).tag(split)
                    }
                }
                .pickerStyle(.menu)
                .tint(FitTheme.accent)
                Text(splitPreference.subtitle)
                    .font(.caption)
                    .foregroundStyle(FitTheme.secondaryText)
            }
            .fitCard()
            .onChange(of: splitPreference) { _, _ in
                weeklyDays = max(weeklyDays, minimumTrainingDays)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("可用器械")
                    .font(.headline)
                ForEach(EquipmentProfile.allCases) { option in
                    Button {
                        equipment = option
                    } label: {
                        HStack {
                            Image(systemName: option.symbol)
                                .foregroundStyle(FitTheme.accent)
                                .frame(width: 28)
                            Text(option.title)
                            Spacer()
                            Image(systemName: equipment == option ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(equipment == option ? FitTheme.accent : Color.white.opacity(0.2))
                        }
                        .padding(.vertical, 5)
                    }
                    .buttonStyle(.plain)
                }
            }
            .fitCard()

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("当前体重")
                        .font(.headline)
                    Spacer()
                    Text("\(bodyWeight, specifier: "%.1f") kg")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(FitTheme.accent)
                }
                Slider(value: $bodyWeight, in: 35...180, step: 0.5)
                    .tint(FitTheme.accent)
                Text("单日体重不会直接改变训练重量；算法使用趋势与表现共同判断。")
                    .font(.caption)
                    .foregroundStyle(FitTheme.secondaryText)
            }
            .fitCard()
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if page > 0 {
                Button {
                    withAnimation { page -= 1 }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .frame(width: 52, height: 52)
                        .background(FitTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            }

            Button {
                if page < pageCount - 1 {
                    withAnimation { page += 1 }
                } else {
                    finish()
                }
            } label: {
                Label(page == pageCount - 1 ? "生成我的计划" : "继续", systemImage: page == pageCount - 1 ? "sparkles" : "arrow.right")
            }
            .buttonStyle(PrimaryActionButtonStyle())
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    private func valueStepper(title: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int = 1, suffix: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Stepper(value: value, in: range, step: step) {
                Text("\(value.wrappedValue) \(suffix)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(FitTheme.accent)
            }
            .fixedSize()
        }
    }

    private func finish() {
        let profile = UserProfile(
            nickname: nickname.trimmingCharacters(in: .whitespacesAndNewlines),
            goal: goal,
            secondaryGoal: secondaryGoal,
            experience: experience,
            weeklyDays: weeklyDays,
            sessionMinutes: sessionMinutes,
            equipment: equipment,
            bodyWeightKg: bodyWeight,
            loadIncrementKg: equipment == .fullGym ? 2.5 : 1,
            splitPreference: splitPreference,
            strengthTrainingGoal: strengthTrainingGoal,
            cardioTrainingGoal: cardioTrainingGoal,
            ageYears: ageYears,
            heightCm: Double(heightCm),
            biologicalSex: biologicalSex
        )
        store.finishOnboarding(with: profile)
    }

    private var minimumTrainingDays: Int {
        switch splitPreference {
        case .automatic, .fullBody: 2
        case .upperLower, .pushPullLegs: 3
        case .chestBackShouldersLegs: 4
        }
    }

    private func modulePicker<T: Hashable>(title: String, selection: Binding<T>, options: [T], label: @escaping (T) -> String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Picker(title, selection: selection) {
                ForEach(options, id: \.self) { option in
                    Text(label(option)).tag(option)
                }
            }
            .tint(FitTheme.accent)
        }
    }
}
