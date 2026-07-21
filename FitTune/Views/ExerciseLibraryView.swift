import SwiftUI

struct ExerciseLibraryView: View {
    @Environment(AppStore.self) private var store
    @State private var showingCreate = false
    @State private var editingExercise: ExerciseOption?

    private var allExercises: [ExerciseOption] {
        TrainingEngine.allExercises + store.customExercises
    }

    var body: some View {
        List {
            Section {
                Button { showingCreate = true } label: {
                    Label("创建自定义动作", systemImage: "plus.circle.fill")
                }
                Text("收藏动作会在动作模式和器械兼容时优先进入下次重新生成的计划。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            let favorites = allExercises.filter { store.favoriteExerciseIDs.contains($0.id) }
            if !favorites.isEmpty {
                Section("收藏") {
                    ForEach(favorites) { exerciseRow($0) }
                }
            }

            if !store.customExercises.isEmpty {
                Section("我的自定义动作") {
                    ForEach(store.customExercises) { option in
                        exerciseRow(option)
                            .contentShape(Rectangle())
                            .onTapGesture { editingExercise = option }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { store.deleteCustomExercise(id: option.id) } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                    }
                }
            }

            ForEach(ExerciseCategory.allCases) { category in
                let items = TrainingEngine.allExercises.filter { $0.resolvedCategory == category }
                if !items.isEmpty {
                    Section(category.title) {
                        ForEach(items) { exerciseRow($0) }
                    }
                }
            }
        }
        .navigationTitle("动作库")
        .sheet(isPresented: $showingCreate) { CustomExerciseEditorView() }
        .sheet(item: $editingExercise) { CustomExerciseEditorView(exercise: $0) }
    }

    private func exerciseRow(_ option: ExerciseOption) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(option.name)
                    if option.source == .custom {
                        Text("自定义").font(.caption2.bold()).foregroundStyle(FitTheme.warning)
                    }
                }
                Text("\(option.resolvedSubcategory.rawValue) · \(option.equipment.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { store.toggleFavoriteExercise(option.id) } label: {
                Image(systemName: store.favoriteExerciseIDs.contains(option.id) ? "star.fill" : "star")
                    .foregroundStyle(store.favoriteExerciseIDs.contains(option.id) ? FitTheme.warning : FitTheme.secondaryText)
            }
            .buttonStyle(.plain)
        }
    }
}
