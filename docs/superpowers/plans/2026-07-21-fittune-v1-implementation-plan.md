# FitTune v1.0 Implementation Plan

> **状态：待用户审阅。** 本计划只描述实施顺序；获得确认前不修改业务代码。

**目标：** 在不丢失 v0.6 用户数据的前提下，把 FitTune 升级为支持自由计划、实时/延迟可穿戴数据、自适应力量与有氧训练、科学估算、训练总结和详细历史的 v1.0。

**架构：** 保留 SwiftUI + 本地 `AppStore` 的离线优先结构，将领域模型、算法、HealthKit、实时数据源和总结计算拆成独立模块。所有训练先写本地不可变原始记录，再由带版本的算法生成可修订摘要。Apple Watch 或标准 BLE 心率设备最多一个实时来源；华为 FIT 3 仅通过 Apple Health 延迟导入，不占实时连接位。

**技术栈：** Swift 6、SwiftUI、XCTest、HealthKit、CoreBluetooth、CoreMotion、CoreLocation、ActivityKit、WatchConnectivity、watchOS WorkoutKit/HealthKit；最低 iOS 17，watchOS 最低版本在创建 Watch target 时按当前 Xcode 支持范围确定。

**设计依据：** `docs/superpowers/specs/2026-07-21-fittune-v1-live-training-design.md`

---

## 实施纪律

每个任务按测试驱动方式完成：先增加失败测试，再实现最小改动，通过该任务测试后才进入下一任务。每个阶段还要运行全量 `swift test`；涉及 UI/系统框架的阶段额外执行 iOS Simulator 构建。所有新增可选数据提供旧版本解码默认值，禁止以重装应用解决迁移问题。

## 阶段 A：数据安全与领域基础

### 任务 1：锁定 v0.6 基线和迁移样本

**修改：**

- `FitTuneTests/Fixtures/V06SnapshotFixture.swift`（新增）
- `FitTuneTests/AppStoreTests.swift`
- `FitTune/Models/DomainModels.swift`

**测试先行：**

1. 建立包含历史力量、有氧、体重、回收站和进行中草稿的 v0.6 JSON fixture。
2. 写测试证明当前数据可恢复，已完成组、训练状态和删除状态不改变。
3. 增加 `schemaVersion`，测试没有该字段的旧快照自动解释为 v0.6。

**实现：** 为 `AppSnapshot` 增加显式版本和迁移入口；迁移采用复制后解码，不在成功持久化前覆盖旧快照。

**验证：** `swift test --filter AppStoreTests`

### 任务 2：拆分 v1.0 核心数据模型

**修改：**

- `FitTune/Models/DomainModels.swift`
- `FitTune/Models/WorkoutModels.swift`（新增）
- `FitTune/Models/HealthMetricModels.swift`（新增）
- `Package.swift`
- `FitTune.xcodeproj/project.pbxproj`
- `FitTuneTests/DomainModelTests.swift`（新增）

**测试先行：** 为以下模型写 Codable 往返和缺失字段兼容测试：

- `DataConfidence`：measured、derived、estimated、unavailable。
- `MetricProvenance`：来源、覆盖率、采集时间和算法版本。
- `PlanSnapshot`、`WorkoutChangeEvent`。
- `RecoveryCheckIn`：睡眠、酸痛、压力、动力的自动值、手动值和最终值。
- `PersonalSafetySettings`：伤病部位、禁用动作、疼痛阈值和最大心率提醒。
- `WorkoutMetricSample`、`WorkoutSummary`、`SummaryRevision`。

**实现：** 引入稳定数据结构，旧 `WorkoutRecord` 以可选字段桥接，保持现有初始化器和测试可编译。

**验证：** `swift test`

### 任务 3：持久化、原子检查点与修订记录

**修改：**

- `FitTune/Store/AppStore.swift`
- `FitTuneTests/AppStoreTests.swift`

**测试先行：**

1. 每次完成组后重建 `AppStore`，当前动作、组次和所有已完成组保持一致。
2. 模拟持久化失败时旧快照仍可恢复。
3. 训练摘要修订只能追加，不能改写原始组记录。
4. 放弃训练不进历史；保存并结束生成部分完成记录。

**实现：** 用临时编码数据通过验证后再替换 UserDefaults 主快照；集中 `checkpointActiveWorkout`；为延迟健康数据增加幂等修订入口。

**验证：** `swift test --filter AppStoreTests`

## 阶段 B：组、动作与计划

### 任务 4：热身组、正式组和用户优先规则

**修改：**

- `FitTune/Models/DomainModels.swift`
- `FitTune/Engine/TrainingEngine.swift`
- `FitTune/Store/AppStore.swift`
- `FitTune/Views/WorkoutSessionView.swift`
- `FitTuneTests/TrainingEngineTests.swift`
- `FitTuneTests/AppStoreTests.swift`

**测试先行：**

1. 热身组默认 RIR 5，可输入 4–6；正式、回退、递减和 AMRAP 组可正确持久化，正式组默认 RIR 0。
2. 自动热身按正式组目标逐级加重、减次，且不计入正式有效组。
3. RIR 0、动作质量差、疼痛或心率异常均不自动减少计划组数或结束动作。
4. 用户覆盖重量/次数后，实际输入优先并持久化。
5. 复合动作连续 RIR 0 或次数显著下降时只生成减容量/延长休息建议；孤立动作采用较低的全身疲劳权重，二者都不自动删组。

**实现：** 扩展 `SetKind` 和热身处方；将“是否继续”改为提示状态；训练页醒目显示组类型及“第 N / 共 M 组”。

**验证：** `swift test && xcodebuild -scheme FitTune -sdk iphonesimulator -configuration Debug build CODE_SIGNING_ALLOWED=NO`

### 任务 5：规范化动作目录与补全动作库

**修改：**

- `FitTune/Models/ExerciseCatalog.swift`（新增）
- `FitTune/Models/DomainModels.swift`
- `FitTune/Engine/TrainingEngine.swift`
- `FitTuneTests/ExerciseCatalogTests.swift`（新增）
- `Package.swift`
- `FitTune.xcodeproj/project.pbxproj`

**测试先行：**

1. stable ID 和规范名称唯一，无组合动作。
2. 肌群、子分类、动作模式和器械字段完整。
3. 覆盖哑铃前平举、哑铃弯举、锤式弯举、负重引体、对握/窄握/反手高位下拉、泽奇深蹲、颈前深蹲及已有动作。
4. 替换结果同时满足动作模式、主要肌群和器械边界。
5. 旧名称 alias 解析到唯一内置动作。

**实现：** 将硬编码目录移入独立 catalog；使用明确子分类；保留旧记录的名称快照和 alias。

**验证：** `swift test --filter ExerciseCatalogTests`

### 任务 6：收藏与自定义动作

**修改：**

- `FitTune/Models/ExerciseCatalog.swift`
- `FitTune/Store/AppStore.swift`
- `FitTune/Views/PlanView.swift`
- `FitTune/Views/ExerciseLibraryView.swift`（新增）
- `FitTune/Views/CustomExerciseEditorView.swift`（新增）
- `FitTuneTests/AppStoreTests.swift`
- `FitTuneTests/ExerciseCatalogTests.swift`

**测试先行：**

1. 收藏持久化，已不存在的 ID 安全丢弃。
2. 新计划只在模式/肌群/器械兼容时优先收藏。
3. 自定义动作可以创建、编辑、分类、收藏和设置替换关系，并始终标记为 custom。
4. 删除自定义动作不破坏历史快照；引用它的计划进入待替换状态。

**实现：** 新增动作库和编辑器；内置与自定义动作分区显示；计划和训练动作选择器共用筛选组件。

**验证：** `swift test && xcodebuild -scheme FitTune -sdk iphonesimulator -configuration Debug build CODE_SIGNING_ALLOWED=NO`

### 任务 7：自由分化、计划编辑与不可变快照

**修改：**

- `FitTune/Engine/TrainingEngine.swift`
- `FitTune/Store/AppStore.swift`
- `FitTune/Views/PlanView.swift`
- `FitTune/Views/TodayView.swift`
- `FitTuneTests/TrainingEngineTests.swift`
- `FitTuneTests/AppStoreTests.swift`

**测试先行：**

1. 三分化、四分化、胸肩背腿和自由组训均生成力量/有氧独立模块。
2. 今日可选择不训练、只力量、只有氧或两者，并可绕过计划选择部位。
3. 开始训练即冻结 `PlanSnapshot`；之后编辑计划不改变活动训练和历史。
4. 训练中增删/替换动作只写 `WorkoutChangeEvent`。
5. 禁用动作不进入计划或自动替换候选；用户临时手选只提示，不被系统强制阻止。

**实现：** 扩展分化编辑、当天组训入口和快照创建；伤病/避用部位继续作为筛选条件。

**验证：** `swift test`

## 阶段 C：恢复量表与 HealthKit

### 任务 8：四维主观恢复和恢复算法

**修改：**

- `FitTune/Models/HealthMetricModels.swift`
- `FitTune/Engine/RecoveryEngine.swift`（新增）
- `FitTune/Store/AppStore.swift`
- `FitTune/Views/TodayView.swift`
- `FitTuneTests/RecoveryEngineTests.swift`（新增）
- `Package.swift`
- `FitTune.xcodeproj/project.pbxproj`

**测试先行：**

1. 睡眠、酸痛、压力、动力分别保存和评分。
2. 自动值缺失时使用手动值；无数据不解释为 0。
3. 自动值与手动值同时存在时，界面采用值和来源可解释。
4. 静息心率基线不足 7 天时不扣分；满足条件后按已确认阈值调整。

**实现：** 替换当前单一 readiness 输入，但保留旧输入的迁移映射；恢复结果输出贡献明细而不是黑盒总分。

**验证：** `swift test --filter RecoveryEngineTests`

### 任务 9：Apple Health 睡眠、静息心率和来源检测

**修改：**

- `FitTune/Services/HealthKitService.swift`
- `FitTune/Services/HealthImportModels.swift`（新增）
- `FitTune/Resources/FitTune.entitlements`
- `FitTune.xcodeproj/project.pbxproj`
- `FitTune/Views/ProfileView.swift`
- `FitTune/Views/DeviceCenterView.swift`（新增）
- `FitTuneTests/HealthImportMergeTests.swift`（新增；使用纯数据适配层，不依赖真实 HealthKit）

**测试先行：**

1. 睡眠阶段合并时正确处理重叠样本、时区和来源。
2. 华为/Apple/其他来源可以识别但不硬编码单一 bundle ID。
3. HealthKit UUID 重复导入不会重复记录。
4. 没有压力通用数据时明确回退手动输入，不从 HRV 推造“压力分”。

**实现：** 请求 sleepAnalysis、restingHeartRate、heartRate、stepCount、distance、activeEnergy、workout 等必要读取权限；返回逐类型状态。华为 FIT 3 只导入其实际写入 Apple Health 的项目。

**验证：** 单元测试、模拟器构建；真机只验证权限和真实可用字段，不以缺少华为字段判失败。

## 阶段 D：唯一实时数据源

### 任务 10：实时来源状态机和数据质量

**修改：**

- `FitTune/Services/LiveSensorSource.swift`（新增）
- `FitTune/Services/LiveSensorCoordinator.swift`（新增）
- `FitTune/Models/HealthMetricModels.swift`
- `FitTune/Views/DeviceCenterView.swift`
- `FitTuneTests/LiveSensorCoordinatorTests.swift`（新增）
- `FitTune.xcodeproj/project.pbxproj`

**测试先行：**

1. 同时只有一个 `activeLiveSource`。
2. 发现新设备不会抢占；切换必须显式确认。
3. 断线只重连原设备，超时后进入 estimated，不自动连其他设备。
4. 心率过期、异常跳变和缺口被标记并排除出算法输入。
5. BLE 接触不良时立即将对应样本标为无效并公开显示 estimated 降级状态。

**实现：** 协调器统一管理 none、Apple Watch 和 BLE；输出规范化 `WorkoutMetricSample` 和连接状态。

**验证：** `swift test --filter LiveSensorCoordinatorTests`

### 任务 11：标准 BLE 心率设备通路

**修改：**

- `FitTune/Services/BluetoothHeartRateSource.swift`（新增）
- `FitTune/Resources/FitTune.entitlements`
- `FitTune/Resources/PrivacyInfo.xcprivacy`
- `FitTune.xcodeproj/project.pbxproj`
- `FitTune/Views/DeviceCenterView.swift`
- `FitTuneTests/BluetoothHeartRateParserTests.swift`（新增）

**测试先行：** 用固定字节样本验证标准 Heart Rate Measurement 的 8/16 位 bpm、接触状态、能量和 RR interval 解析。

**实现：** CoreBluetooth 扫描、配对、状态恢复和后台模式；仅连接标准心率服务，不声称可直连不广播心率的 FIT 3。

**验证：** 解析测试、模拟器编译；有兼容设备时才做实物验收。

### 任务 12：Apple Watch 配套应用和镜像会话

**修改/新增：**

- `FitTuneWatch/` watchOS target
- `FitTuneWatch/WorkoutSessionManager.swift`
- `FitTuneWatch/WorkoutView.swift`
- `FitTune/Services/WatchWorkoutBridge.swift`
- `FitTune.xcodeproj/project.pbxproj`
- iOS/watchOS entitlements 与 Info 配置
- `FitTuneTests/WatchMetricMergeTests.swift`

**测试先行：**

1. iPhone/Watch 同 session ID 的样本按时间去重合并。
2. Watch 断开后 iPhone 进入 stale/estimated，恢复后不生成第二条训练。
3. Watch 暂停、继续和结束正确镜像到 iPhone；Watch 结束只保存同一 session ID 的一条记录。

**实现：** Watch 上使用 `HKWorkoutSession` 和 live workout builder 采集心率、能量及运动支持指标，通过镜像/WatchConnectivity 发送到 iPhone；设备中心可选 Apple Watch 作为唯一实时源；Watch 训练页提供暂停、继续和结束关键操作。

**验证：** iPhone + Watch Simulator 联合构建和会话测试；用户购入 Apple Watch 后再完成实表校验，不阻塞手机端 v1.0 使用。

## 阶段 E：训练中实时调整与后台能力

### 任务 13：力量训练实时休息和下组建议

**修改：**

- `FitTune/Engine/TrainingEngine.swift`
- `FitTune/Engine/LiveAdaptationEngine.swift`（新增）
- `FitTune/Store/AppStore.swift`
- `FitTune/Views/WorkoutSessionView.swift`
- `FitTuneTests/LiveAdaptationEngineTests.swift`（新增）

**测试先行：**

1. 完成次数、RIR、恢复和历史仍是重量建议主输入。
2. 心率恢复差只能延长休息、阻止加重或给出保守建议，不能单独加重。
3. 心率无效/缺失时结果退回原算法且训练可继续。
4. 所有建议包含原因、可信度和用户覆盖能力。
5. 前 3–5 次同动作训练分别累计心率反应、组间恢复、实际 RIR、容量和表现，推荐权重逐次增加；样本不足时不得冒充已个体化。
6. 达到用户疼痛或最大心率提醒阈值时只生成醒目提示和停止入口，不自动结束。

**实现：** 将休息拆为初始建议与实时更新；记录 60/120 秒恢复；训练页显示数据来源和不确定性。

**验证：** `swift test --filter LiveAdaptationEngineTests`

### 任务 14：后台有氧会话与本机传感器

**修改：**

- `FitTune/Services/CardioSessionCoordinator.swift`（新增）
- `FitTune/Services/MotionLocationSource.swift`（新增）
- `FitTune/Store/AppStore.swift`
- `FitTune/Views/CardioSessionView.swift`（新增）
- `FitTune/Resources/FitTune.entitlements`
- `FitTune/Resources/PrivacyInfo.xcprivacy`
- `FitTune.xcodeproj/project.pbxproj`
- `FitTuneTests/CardioSessionTests.swift`（新增）

**测试先行：**

1. 跑步、爬坡、爬楼、骑行、游泳按能力暴露不同字段。
2. 后台检查点恢复后时长和样本不重复。
3. 无 Watch 时游泳划水显示 unavailable，不生成估算划水。
4. 强制结束/权限撤回产生带数据缺口说明的部分总结。

**实现：** Core Motion/Location 与唯一实时来源合并；锁屏或切应用持续系统允许的数据采集；FIT 3 后续样本可修订摘要。

**验证：** 模拟器构建和真机锁屏/切应用场景。

### 任务 15：Live Activity、退出选择与动作完成反馈

**修改/新增：**

- `FitTuneWidgets/` ActivityKit widget extension
- `FitTune/Services/WorkoutActivityController.swift`
- `FitTune/Views/RootView.swift`
- `FitTune/Views/WorkoutSessionView.swift`
- `FitTune/Views/CardioSessionView.swift`
- `FitTune.xcodeproj/project.pbxproj`
- `FitTuneTests/WorkoutLifecycleTests.swift`

**测试先行：** 验证恢复路由、继续/保存并结束/放弃三分支、动作完成动画只触发一次、草稿结束后 Live Activity 清理。

**实现：** 打开应用自动恢复训练；锁屏显示时长、动作/组次、心率和休息倒计时；主动返回主页弹出三项选择。

**验证：** 模拟器 UI 流程和真机锁屏验收。

## 阶段 F：科学估算、总结与进展

### 任务 16：能量消耗分层和去重

**修改：**

- `FitTune/Engine/EnergyEngine.swift`（新增）
- `FitTune/Engine/TrainingEngine.swift`
- `FitTune/Store/AppStore.swift`
- `FitTune/Views/TodayView.swift`
- `FitTuneTests/EnergyEngineTests.swift`（新增）
- `SCIENTIFIC_BASIS.md`

**测试先行：**

1. 今日总消耗正确拆分静息、日常步数、力量和有氧。
2. 已有 HealthKit 主动能量的时间段不重复叠加本地估算。
3. 数据优先级为可验证设备能量 → 心率时序 → 运动专用方程 → MET/训练估算。
4. 每个结果返回区间、来源、覆盖率和可信度。
5. 基础代谢按可用身体参数选择公式，不用力量水平直接伪造 BMR。

**实现：** 把现有能量函数移入 `EnergyEngine`，建立时间区间去重和可解释结果。

**验证：** `swift test --filter EnergyEngineTests`

### 任务 17：训练总结、曲线和延迟修订

**修改：**

- `FitTune/Engine/SummaryEngine.swift`（新增）
- `FitTune/Store/AppStore.swift`
- `FitTune/Views/WorkoutSummaryView.swift`（新增）
- `FitTune/Views/HistoryDetailView.swift`（新增）
- `FitTuneTests/SummaryEngineTests.swift`（新增）

**测试先行：**

1. 通用总结生成平均/最大心率、曲线、区间时长、能量、负荷、恢复和数据覆盖。
2. 力量总结包含容量、组类型、力竭率、e1RM 和肌群负荷。
3. 有氧总结按方式包含距离、配速、步频/划水和心率恢复；数据不足不生成 VO₂max。
4. 华为/HealthKit 延迟样本只追加摘要修订，原始记录不变。
5. e1RM 超出算法适用次数/RIR 范围时标记低可信度且不进入力量进步判定；同重量次数趋势仍可独立计算。
6. 热量、恢复时间和训练效果在结果旁显示来源、可信度和合理区间；延迟修订保留初始估算、更新时间和修正原因。

**实现：** 结束训练强制弹出总结；历史详情复用总结组件并展示计划快照、组明细、曲线及修订来源。

**验证：** `swift test --filter SummaryEngineTests && xcodebuild -scheme FitTune -sdk iphonesimulator -configuration Debug build CODE_SIGNING_ALLOWED=NO`

### 任务 18：近 30 天力量、心肺、睡眠与恢复趋势

**修改：**

- `FitTune/Engine/TrendEngine.swift`（新增）
- `FitTune/Views/InsightsView.swift`
- `FitTuneTests/TrendEngineTests.swift`（新增）

**测试先行：**

1. 30 天窗口边界正确，不受删除/回收站记录污染。
2. e1RM、相对力量、训练容量、心率恢复、配速、睡眠和恢复趋势分别计算。
3. 样本不足时返回 unavailable，不用单点制造趋势。
4. 连续低恢复/表现下降只生成减量建议，不修改计划。
5. 心率区间按近期可靠实测最大心率 → 可识别手表记录 → 年龄公式的顺序选择来源，并结合个人静息心率计算；来源和用户修正会被保留。

**实现：** 新增趋势聚合层和图表；显示数据来源及样本数。

**验证：** `swift test --filter TrendEngineTests`

### 任务 19：算法说明、数据管理和隐私文案

**修改：**

- `SCIENTIFIC_BASIS.md`
- `README.md`
- `FitTune/Views/AlgorithmInfoView.swift`（新增）
- `FitTune/Services/DataExportService.swift`（新增）
- `FitTune/Views/ProfileView.swift`
- `FitTune/Views/SafetySettingsView.swift`（新增）
- `FitTune/Views/HealthDataManagementView.swift`（新增）
- `FitTune/Resources/PrivacyInfo.xcprivacy`
- `FitTuneTests/DataExportServiceTests.swift`（新增）
- Info.plist 构建设置

**测试先行：** 完整 JSON 导出后可恢复计划、原始训练、指标样本和摘要修订；CSV 分别导出训练、组明细、时序和恢复表，特殊字符与小数格式稳定，且不把 CSV 宣称为完整备份。分别删除某设备导入副本、选定训练心率曲线和整次训练后，保留范围及摘要降级结果正确；删除本地副本不宣称删除外部健康库原始数据。

**实施：** 展示算法版本、输入、公式选择、可信度含义和限制；实现用户主动触发的 JSON/CSV 导出和系统分享；更新 HealthKit、蓝牙、定位和运动权限说明；保留回收、恢复与永久删除入口。

**验证：** 搜索所有健康权限用途文案，确认功能与声明一一对应；运行隐私清单和模拟器构建检查。

## 阶段 G：版本、回归与交付

### 任务 20：完整回归与性能/中断测试

**新增基准 fixture：**

- `FitTuneTests/Fixtures/EnergyBenchmarks.json`
- `FitTuneTests/Fixtures/RestRecommendationBenchmarks.json`
- `FitTuneTests/Fixtures/E1RMBenchmarks.json`
- `FitTuneTests/Fixtures/RecoveryBenchmarks.json`
- `FitTuneTests/Fixtures/HealthDeduplicationBenchmarks.json`

每个 fixture 保存固定输入、预期输出、容差、算法版本和依据说明。算法结果有意调整时必须同时更新版本、fixture 和 `SCIENTIFIC_BASIS.md`，禁止只放宽测试容差。

**验证矩阵：**

- `swift test` 全量通过。
- iPhone Simulator Debug/Release 构建通过。
- iPhone + Watch Simulator 构建通过。
- 用 v0.6 fixture、当前真机快照副本验证升级迁移。
- 无健康权限、部分权限、无设备、BLE 断线、Watch 断线、华为延迟同步分别验收。
- 力量训练覆盖切后台、锁屏、杀进程后恢复、主动返回三分支、增删替换动作和永久删除。
- 有氧覆盖跑步/爬坡等本机模式和游泳无数据降级。
- 长样本曲线做内存和持久化大小检查；必要时按时间窗口降采样但保留摘要原始统计。

### 任务 21：版本升级、归档和 iPhone 覆盖安装

**修改：**

- `FitTune.xcodeproj/project.pbxproj`：`MARKETING_VERSION = 1.0.0`，`CURRENT_PROJECT_VERSION = 10`。
- `VALIDATION.md`

**步骤：**

1. 生成签名真机构建，沿用 `com.codex.fittune`。
2. 安装前确认设备连接、解锁、开发者模式和信任状态；不卸载旧版本。
3. 覆盖安装到现有 iPhone，启动并验证旧数据、进行中训练迁移、健康权限和核心流程。
4. 记录实际可见的 FIT 3/Apple Health 数据类型，不把未同步字段记为应用故障。
5. 生成 `FitTune-iOS-v1.0.0.zip`，包含源码、规格、实施记录和验证结果。

## 建议实施检查点

- **检查点 1（阶段 A–B）：** 本地数据迁移、RIR、动作库、收藏、自定义动作、自由计划完成后先交付一次模拟器预览。
- **检查点 2（阶段 C–D）：** 恢复量表、HealthKit、设备中心和实时来源状态机完成后在用户 iPhone 核验权限及 FIT 3 实际数据。
- **检查点 3（阶段 E）：** 力量实时调整、后台有氧和 Live Activity 完成后做真机中断测试。
- **检查点 4（阶段 F–G）：** 科学估算、总结、历史和趋势全部完成后执行最终覆盖安装。

这些检查点用于验收和发现真机平台限制，不改变“数据缺失不能阻塞训练”的规则。
