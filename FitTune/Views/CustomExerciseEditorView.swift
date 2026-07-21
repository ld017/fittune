import SwiftUI

struct CustomExerciseEditorView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    private let stableID: String?
    @State private var name: String
    @State private var pattern: MovementPattern
    @State private var equipment: EquipmentKind
    @State private var category: ExerciseCategory
    @State private var subcategory: ExerciseSubcategory
    @State private var replacementIDs: Set<String>

    init(exercise: ExerciseOption? = nil) {
        stableID = exercise?.stableID
        _name = State(initialValue: exercise?.name ?? "")
        _pattern = State(initialValue: exercise?.pattern ?? .horizontalPush)
        _equipment = State(initialValue: exercise?.equipment ?? .dumbbell)
        _category = State(initialValue: exercise?.resolvedCategory ?? .chest)
        _subcategory = State(initialValue: exercise?.resolvedSubcategory ?? .horizontalPress)
        _replacementIDs = State(initialValue: Set(exercise?.replacementIDs ?? []))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("动作名称", text: $name)
                    Picker("主要肌群", selection: $category) {
                        ForEach(ExerciseCategory.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("动作模式", selection: $pattern) {
                        ForEach(MovementPattern.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("器械", selection: $equipment) {
                        ForEach(EquipmentKind.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("子分类", selection: $subcategory) {
                        ForEach(ExerciseSubcategory.allCases) { Text($0.rawValue).tag($0) }
                    }
                }

                Section("可替换动作") {
                    ForEach(TrainingEngine.exerciseAlternatives(for: pattern)) { option in
                        Toggle(option.name, isOn: Binding(
                            get: { replacementIDs.contains(option.id) },
                            set: { enabled in
                                if enabled { replacementIDs.insert(option.id) }
                                else { replacementIDs.remove(option.id) }
                            }
                        ))
                    }
                }
            }
            .navigationTitle(stableID == nil ? "创建动作" : "编辑动作")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        store.saveCustomExercise(ExerciseOption(
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            pattern: pattern,
                            equipment: equipment,
                            category: category,
                            subcategory: subcategory,
                            stableID: stableID,
                            replacementIDs: Array(replacementIDs).sorted(),
                            source: .custom
                        ))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
