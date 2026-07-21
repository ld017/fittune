# FitTune v0.5 科学依据与工程边界

## 能量消耗

- 静息能量按证据层级选择：用户录入的间接测热 RMR > Cunningham 去脂体重公式 `500 + 22 × FFM(kg)` > Mifflin–St Jeor。Cunningham 原始研究指出去脂体重是其数据中的主要预测量：<https://pubmed.ncbi.nlm.nih.gov/7435418/>；Mifflin 原始研究：<https://pubmed.ncbi.nlm.nih.gov/2305711/>。
- 力量成绩、训练总重量和训练年限不会被直接加进基础代谢。它们受神经适应、技术和动作选择影响，不能可靠替代去脂体重。训练历史只有在体重、体脂率或去脂体重被实际记录后才更新代谢输入。
- 运动 MET 取值方向来自 2024 Adult Compendium of Physical Activities：<https://pmc.ncbi.nlm.nih.gov/articles/PMC10818145/> 与 <https://pacompendium.com/adult-compendium/>。
- App 采用 `净主动消耗 = (MET - 1) × 3.5 × 体重kg ÷ 200 × 分钟`，再与全天静息能量相加，避免把运动期间的静息消耗重复计算。
- 有氧估算顺序为：设备实测主动能量 > 走/跑速度与坡度方程 > Keytel 平均心率方程 > 2024 Compendium MET。Keytel 模型使用年龄、体重、生理性别和平均心率，原始研究：<https://pubmed.ncbi.nlm.nih.gov/15966347/>。
- 力量训练消耗优先使用 Watch 实测；其次使用带较宽误差区间的心率模型；数据不足时使用 Compendium 抗阻训练 MET 与 session-RPE。2024 年方法综述指出力量训练能耗受无氧供能与测量方法影响很大，实验室外无法仅由组数和训练容量精确反推：<https://pubmed.ncbi.nlm.nih.gov/38896201/>。因此 App 不再用“总负重训练量”制造虚假的精确小数。
- 每个估算同时保存方法、置信度和上下界。设备值也不是实验室金标准；误差区间用于提醒，不用于临床决策。
- 日常步数优先读取 HealthKit 步数与步行距离。无距离时才按步数与体重作低置信度估算；若已有 Apple Watch 全天主动能量，步行只作为其中的拆分展示，不重复加总。
- Apple Health 的 `HKWorkout` 可承载运动时长、距离、主动能量及关联心率样本：<https://developer.apple.com/documentation/healthkit/hkworkout>。无手表时先保存估算；之后同步到匹配的运动类型、日期和时长时，用 Watch 能量/心率回填原记录，避免重复记录。

## 动作选择与训练自由度

- 动作替换坚持“相同动作模式”原则，避免把目标肌群和技术需求完全不同的动作视作等价。
- ACSM 2026 更新强调个体化、持续性和覆盖主要肌群；器械类型本身并未稳定决定一般成年人的训练效果，因此动作库同时提供杠铃、哑铃、史密斯、固定器械、绳索、徒手和弹力带版本：<https://acsm.org/resistance-training-guidelines-update-2026/>。
- “高效”在本 App 中表示能以可控动作质量、目标 RIR、现有器械和可持续训练量完成，而不是宣称某一个动作对所有人最优。

## 逐组建议与停止规则

- RIR 越接近 0，急性神经肌肉疲劳通常越高；研究显示 3 RIR 可降低急性疲劳，而接近力竭会增加疲劳：<https://pmc.ncbi.nlm.nih.gov/articles/PMC9908800/>。
- 力竭训练可能让部分疲劳指标延长到训练后 24–48 小时：<https://pubmed.ncbi.nlm.nih.gov/28965198/>。
- RPE 在抗阻训练中可用于监控主观强度；综述支持 session-RPE 作为多种运动中的训练负荷工具：<https://pubmed.ncbi.nlm.nih.gov/35000021/>、<https://pubmed.ncbi.nlm.nih.gov/29163016/>。
- App 因此把精细 RPE 档位、RIR、动作质量、连续困难组数、今日恢复和上次训练质量共同用于下组负重、休息时间、剩余组数与停止建议。训练负荷以 `session-RPE × 时长` 表示，并结合相对强度和有效组质量。
- 恢复改为范围（如 24–48 小时），不再显示伪精确单点。范围仍是工程估算，不代表组织已经恢复；下一次训练必须由热身表现、疼痛、睡眠与主观恢复再次确认。

## 安全边界

FitTune 不诊断伤病，不替代医生、物理治疗师或合格教练。尖锐疼痛、胸痛、眩晕、异常气短、麻木或动作突然失控时，应立即停止训练并视情况寻求专业帮助。
