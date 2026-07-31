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
                LabeledContent("多运动", value: SportAnalysisEngine.algorithmVersion)
            }
            Section("下组重量与休息") {
                Text("重量建议主要使用完成次数、RIR、四维恢复和同动作历史。实时心率只提供个人恢复参考与安全提示，不能单凭心率加重。休息倒计时和所有建议均可跳过或修改，不会锁定下一组、擅自删组或结束训练。")
                Text("热身组默认 RIR 5（可调 4–6），正式组默认 RIR 0。只有正式组进入主要训练量、力竭率和力量趋势。")
            }
            Section("能量") {
                Text("静息代谢优先使用实测 RMR；其次为有去脂体重时的 Cunningham；否则在年龄、身高和生理性别完整时使用 Mifflin–St Jeor。力量水平不直接代入基础代谢。")
                Text("有氧主动能量优先级：专项机械模型 -> 心率 -> MET -> 仅设备降级。设备主动能量通常作为对照，不会覆盖合格的速度/坡度、功率或心率模型。")
                Text("力量训练以时长、组数密度、复合动作占比和真实 session-RPE 的结构模型为主，心率只在覆盖充分时校正；EPOC 不叠加到本次主动能量。")
            }
            Section("限制") {
                Text("e1RM 仅在合理次数/RIR 范围内作为个人纵向指标；高次数力竭组可信度较低。数据不足时不会强行生成 VO₂max。热量、恢复时间和训练效果均为区间估计，不是医学诊断。")
                Text("华为健康数据若写入 Apple 健康，可在同步后修订总结；它不是实时源，也不会占用 Apple Watch 或蓝牙心率设备连接位。")
            }
            Section("多运动") {
                Text("羽毛球、乒乓球、足球、攀岩、徒步、登山和越野跑按独立项目分析。主动热量以 2024 Adult Compendium 的净 MET 区间回退，训练负荷为有效分钟 × session-RPE；暂停时间不计入。")
                Text("应用只显示传感器确有证据的距离、步数、海拔和爬升。不会推测击球、触球、冲刺、攀岩等级或高原风险；缺数据时降低可信度但不阻止训练。")
            }
            Section("主要依据") {
                Link("Mifflin–St Jeor 静息代谢方程", destination: URL(string: "https://pubmed.ncbi.nlm.nih.gov/2305711/")!)
                Link("Keytel 心率能量预测", destination: URL(string: "https://pubmed.ncbi.nlm.nih.gov/15966347/")!)
                Link("RIR 量表应用", destination: URL(string: "https://pubmed.ncbi.nlm.nih.gov/27531969/")!)
                Link("RIR 负荷处方可靠性", destination: URL(string: "https://pubmed.ncbi.nlm.nih.gov/36135029/")!)
                Link("组间休息系统综述", destination: URL(string: "https://pubmed.ncbi.nlm.nih.gov/39205815/")!)
                Link("力竭与非力竭训练 Meta 分析", destination: URL(string: "https://pubmed.ncbi.nlm.nih.gov/33497853/")!)
                Link("腕式设备心率与能量误差", destination: URL(string: "https://pubmed.ncbi.nlm.nih.gov/28538708/")!)
                Link("成人最大心率年龄预测", destination: URL(string: "https://pubmed.ncbi.nlm.nih.gov/11153730/")!)
                Link("Fatmax 个体差异", destination: URL(string: "https://pubmed.ncbi.nlm.nih.gov/14598198/")!)
                Link("最大脂肪氧化评估综述", destination: URL(string: "https://pubmed.ncbi.nlm.nih.gov/30929281/")!)
                Link("session-RPE 训练负荷", destination: URL(string: "https://pubmed.ncbi.nlm.nih.gov/11708692/")!)
                Link("2024 Adult Compendium", destination: URL(string: "https://doi.org/10.1016/j.jshs.2023.10.010")!)
                Link("PCr 恢复综述", destination: URL(string: "https://pubmed.ncbi.nlm.nih.gov/12238940/")!)
                Link("1 分钟与 3 分钟组间休息试验", destination: URL(string: "https://pubmed.ncbi.nlm.nih.gov/26605807/")!)
                Link("EPOC 影响因素综述", destination: URL(string: "https://pubmed.ncbi.nlm.nih.gov/17101527/")!)
            }
        }
        .navigationTitle("算法与科学依据")
    }
}
