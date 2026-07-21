import SwiftUI

struct AlgorithmInfoView: View {
    var body: some View {
        List {
            Section("当前算法版本") {
                LabeledContent("训练处方", value: TrainingEngine.ruleVersion)
                LabeledContent("恢复", value: RecoveryEngine.algorithmVersion)
                LabeledContent("能量", value: EnergyEngine.algorithmVersion)
                LabeledContent("训练总结", value: SummaryEngine.algorithmVersion)
                LabeledContent("趋势", value: TrendEngine.algorithmVersion)
            }
            Section("下组重量与休息") {
                Text("重量建议主要使用完成次数、RIR、四维恢复和同动作历史。实时心率只能延长休息、阻止冒进加重和触发安全提示，不能单凭心率加重。所有建议均可修改，不会擅自删组或结束训练。")
                Text("热身组默认 RIR 5（可调 4–6），正式组默认 RIR 0。只有正式组进入主要训练量、力竭率和力量趋势。")
            }
            Section("能量") {
                Text("静息代谢优先使用实测 RMR；其次为有去脂体重时的 Cunningham；否则在年龄、身高和生理性别完整时使用 Mifflin–St Jeor。力量水平不直接代入基础代谢。")
                Text("运动能量优先级：设备实测 → 合格心率数据 → 速度/坡度等专项方程 → MET 估算。全天设备主动能量作为去重上限，避免与训练和步数重复相加。")
            }
            Section("限制") {
                Text("e1RM 仅在合理次数/RIR 范围内作为个人纵向指标；高次数力竭组可信度较低。数据不足时不会强行生成 VO₂max。热量、恢复时间和训练效果均为区间估计，不是医学诊断。")
                Text("华为健康数据若写入 Apple 健康，可在同步后修订总结；它不是实时源，也不会占用 Apple Watch 或蓝牙心率设备连接位。")
            }
            Section("主要依据") {
                Link("Mifflin–St Jeor 静息代谢方程", destination: URL(string: "https://pubmed.ncbi.nlm.nih.gov/2305711/")!)
                Link("Keytel 心率能量预测", destination: URL(string: "https://pubmed.ncbi.nlm.nih.gov/15966347/")!)
                Link("RIR 量表应用", destination: URL(string: "https://pubmed.ncbi.nlm.nih.gov/27531969/")!)
                Link("RIR 负荷处方可靠性", destination: URL(string: "https://pubmed.ncbi.nlm.nih.gov/36135029/")!)
                Link("组间休息系统综述", destination: URL(string: "https://pubmed.ncbi.nlm.nih.gov/39205815/")!)
                Link("力竭与非力竭训练 Meta 分析", destination: URL(string: "https://pubmed.ncbi.nlm.nih.gov/33497853/")!)
            }
        }
        .navigationTitle("算法与科学依据")
    }
}
