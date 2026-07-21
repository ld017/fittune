import SwiftUI

struct PlanView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ZStack {
            FitBackground()
            ScrollView {
                VStack(spacing: 18) {
                    SectionHeading(
                        eyebrow: "当前训练块",
                        title: store.plan?.title ?? "尚未生成计划",
                        detail: store.plan?.rationale
                    )
                    .padding(.top, 10)

                    if let plan = store.plan {
                        planSummary(plan)
                        SectionHeading(
                            eyebrow: "模块一",
                            title: "力量训练",
                            detail: "首组重量由上次训练间隔、表现质量与今日恢复共同计算。"
                        )
                        ForEach(Array(plan.sessions.enumerated()), id: \.element.id) { index, session in
                            sessionCard(index: index, session: session)
                        }
                        cardioSection(plan.cardioSessions ?? [])
                        evidenceCard
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
        }
        .navigationTitle("训练计划")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func planSummary(_ plan: TrainingPlan) -> some View {
        HStack(spacing: 10) {
            MetricChip(value: "\(plan.sessions.count)", label: "每周训练")
            MetricChip(
                value: "\(plan.sessions.flatMap(\.exercises).reduce(0) { $0 + $1.sets })",
                label: "力量总组数",
                tint: FitTheme.accentBlue
            )
            MetricChip(value: "\(plan.cardioSessions?.count ?? 0)", label: "有氧训练", tint: FitTheme.warning)
        }
    }

    private func sessionCard(index: Int, session: TrainingSession) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("0\(index + 1)")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(FitTheme.background)
                    .frame(width: 34, height: 34)
                    .background(index == 0 ? FitTheme.accent : FitTheme.accentBlue, in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.name).font(.headline)
                    Text(session.focus)
                        .font(.caption)
                        .foregroundStyle(FitTheme.secondaryText)
                }
                Spacer()
                Text("≈ \(session.estimatedMinutes) 分")
                    .font(.caption.bold())
                    .foregroundStyle(FitTheme.secondaryText)
            }

            VStack(spacing: 0) {
                ForEach(session.exercises) { exercise in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(exercise.isPriority ? FitTheme.warning : FitTheme.accent.opacity(0.55))
                            .frame(width: 7, height: 7)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(exercise.name)
                                .font(.subheadline.weight(exercise.isPriority ? .semibold : .regular))
                            Text(exercise.targetText)
                                .font(.caption2)
                                .foregroundStyle(FitTheme.secondaryText)
                            let load = store.loadRecommendation(for: exercise)
                            Text("建议 \(load.displayLoad) · \(load.confidence)置信度")
                                .font(.caption2.bold())
                                .foregroundStyle(load.loadKg == nil ? FitTheme.warning : FitTheme.accentBlue)
                            Text(load.reason)
                                .font(.caption2)
                                .foregroundStyle(FitTheme.secondaryText)
                                .lineLimit(2)
                        }
                        Spacer()
                        Menu {
                            ForEach(TrainingEngine.exerciseAlternatives(for: exercise.pattern)) { option in
                                Button {
                                    store.replaceExercise(sessionID: session.id, exerciseID: exercise.id, with: option)
                                } label: {
                                    Label(option.name, systemImage: option.name == exercise.name ? "checkmark" : "arrow.triangle.2.circlepath")
                                }
                            }
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                                .font(.title3)
                                .foregroundStyle(FitTheme.accent)
                        }
                        .accessibilityLabel("替换 \(exercise.name)")
                    }
                    .padding(.vertical, 9)
                    if exercise.id != session.exercises.last?.id {
                        Divider().overlay(Color.white.opacity(0.07))
                    }
                }
            }
        }
        .fitCard(padding: 17)
    }

    @ViewBuilder
    private func cardioSection(_ sessions: [CardioSession]) -> some View {
        SectionHeading(
            eyebrow: "模块二",
            title: "有氧训练",
            detail: sessions.isEmpty ? "当前关闭，可在“我的”中选择减脂、基础有氧或心肺表现。" : "与力量计划独立安排；同日训练时默认先完成力量。"
        )
        if sessions.isEmpty {
            HStack {
                Image(systemName: "heart.slash")
                    .foregroundStyle(FitTheme.secondaryText)
                Text("暂未安排有氧模块")
                    .font(.subheadline)
                    .foregroundStyle(FitTheme.secondaryText)
                Spacer()
            }
            .fitCard()
        } else {
            ForEach(sessions) { cardio in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: cardio.intensity == .intervals ? "bolt.heart.fill" : "figure.run")
                            .foregroundStyle(cardio.intensity == .intervals ? FitTheme.warning : FitTheme.accentBlue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(cardio.name).font(.headline)
                            Text("\(cardio.modality) · \(cardio.minutes) 分钟 · \(cardio.intensity.title)")
                                .font(.caption)
                                .foregroundStyle(FitTheme.secondaryText)
                        }
                    }
                    Text(cardio.guidance)
                        .font(.subheadline)
                        .foregroundStyle(FitTheme.secondaryText)
                }
                .fitCard()
            }
        }
    }

    private var evidenceCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("为什么这样安排", systemImage: "doc.text.magnifyingglass")
                .font(.headline)
                .foregroundStyle(FitTheme.accent)
            Text("总量相当时，全身训练与分化训练没有稳定的力量或增肌优劣，因此分化可按偏好选择。首组负重以最近同动作记录为基线，下组建议只根据次数、RIR、恢复与历史记录；器械替换始终保持相同动作模式。")
                .font(.subheadline)
                .foregroundStyle(FitTheme.secondaryText)
            Text("规则版本：\(store.plan?.ruleVersion ?? TrainingEngine.ruleVersion)")
                .font(.caption2.monospaced())
                .foregroundStyle(FitTheme.secondaryText)
        }
        .fitCard()
    }
}
