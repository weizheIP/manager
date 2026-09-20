import CoreTransferable
import PhotosUI
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

private struct PickedPhoto: Transferable, Sendable {
    let url: URL
    nonisolated static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            let directory = URL.temporaryDirectory.appending(path: "chidi-photo-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let output = directory.appendingPathComponent(received.file.lastPathComponent)
            do {
                try FileManager.default.copyItem(at: received.file, to: output)
                return PickedPhoto(url: output)
            } catch { try? FileManager.default.removeItem(at: directory); throw error }
        }
    }
}

struct AttachmentPreview: Identifiable {
    var id: URL { url }
    let url: URL
    let title: String
}

struct FilePreview: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let file: AttachmentPreview
    func makeCoordinator() -> Coordinator { Coordinator(file: file, dismiss: dismiss) }
    func makeUIViewController(context: Context) -> UINavigationController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        controller.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "关闭", style: .plain, target: context.coordinator, action: #selector(Coordinator.close))
        return UINavigationController(rootViewController: controller)
    }
    func updateUIViewController(_ navigation: UINavigationController, context: Context) {
        guard context.coordinator.item.previewItemURL != file.url else { return }
        context.coordinator.item = PreviewItem(file: file)
        (navigation.viewControllers.first as? QLPreviewController)?.reloadData()
    }
    final class PreviewItem: NSObject, QLPreviewItem {
        var previewItemURL: URL?
        var previewItemTitle: String?
        init(file: AttachmentPreview) { previewItemURL = file.url; previewItemTitle = file.title }
    }
    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var item: PreviewItem
        let dismiss: DismissAction
        init(file: AttachmentPreview, dismiss: DismissAction) { item = PreviewItem(file: file); self.dismiss = dismiss }
        @objc func close() { dismiss() }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem { item }
    }
}

struct AttachmentRows: View {
    @Environment(TaskStore.self) private var store
    let taskID: UUID
    var stepID: UUID?
    @State private var importing = false
    @State private var showFiles = false
    @State private var photo: PhotosPickerItem?
    @State private var showRecording = false
    @State private var preview: AttachmentPreview?
    @State private var errorText: String?

    private var files: [AttachmentRecord] { store.document.attachments.filter { $0.taskID == taskID && $0.stepID == stepID && $0.deletedAt == nil } }
    private var editable: Bool { store.task(taskID).map { !store.document.isDeleted($0) } == true && !store.isReadOnly }
    var body: some View {
        ForEach(files) { file in
            HStack {
                Button {
                    do { preview = AttachmentPreview(url: try store.attachmentURL(file), title: file.filename) }
                    catch { errorText = error.localizedDescription }
                } label: {
                    Label(file.filename, systemImage: file.kind == .image ? "photo" : file.kind == .audio ? "waveform" : "doc")
                        .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.borderless)
                if editable {
                    Button("移除附件", systemImage: "trash", role: .destructive) {
                        _ = store.change { doc in
                            if let i = doc.attachments.firstIndex(where: { $0.id == file.id }) { doc.attachments[i].deletedAt = .now }
                        }
                    }.labelStyle(.iconOnly).buttonStyle(.borderless)
                        .accessibilityLabel("移除附件：\(file.filename)")
                }
            }
        }
        if editable {
            HStack(spacing: 20) {
                PhotosPicker(selection: $photo, matching: .images) { Label("图片", systemImage: "photo.badge.plus") }
                Button { showFiles = true } label: { Label("文件", systemImage: "doc.badge.plus") }
                Button { showRecording = true } label: { Label("录音", systemImage: "mic") }
            }.buttonStyle(.borderless).disabled(importing)
                .fileImporter(isPresented: $showFiles, allowedContentTypes: [.item]) { result in
                    switch result {
                    case .success(let url): Task { await add(url) }
                    case .failure(let error): errorText = error.localizedDescription
                    }
                }
                .onChange(of: photo) { _, selected in
                    guard let selected else { return }
                    Task {
                        importing = true
                        defer { importing = false; photo = nil }
                        do {
                            guard let imported = try await selected.loadTransferable(type: PickedPhoto.self) else { throw ChidiDataError.invalid("无法读取所选图片，请重试。") }
                            defer { try? FileManager.default.removeItem(at: imported.url.deletingLastPathComponent()) }
                            if !(await store.importAttachment(from: imported.url, taskID: taskID, stepID: stepID, kind: .image)) { takeError() }
                        } catch { errorText = error.localizedDescription }
                    }
                }
            if importing { ProgressView("正在保存附件…") }
            Text("单个附件最多 100 MB；移除后可在废纸篓保留 30 天。").font(.caption).foregroundStyle(.secondary)
        }
        if let errorText { Text(errorText).font(.footnote).foregroundStyle(.red) }
        Color.clear.frame(height: 0)
            .sheet(item: $preview) { file in FilePreview(file: file).ignoresSafeArea() }
            .sheet(isPresented: $showRecording) { AudioNoteSheet(taskID: taskID, stepID: stepID) }
    }
    private func add(_ url: URL) async {
        importing = true
        defer { importing = false }
        if !(await store.importAttachment(from: url, taskID: taskID, stepID: stepID)) { takeError() }
    }
    private func takeError() { errorText = store.errorMessage; store.errorMessage = nil }
}

struct AudioNoteSheet: View {
    @Environment(TaskStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let taskID: UUID
    let stepID: UUID?
    @State private var recorder = AudioNoteRecorder()
    @State private var saving = false
    @State private var name = ""
    @State private var preview: AttachmentPreview?
    @State private var discard = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("录音名称（选填）", text: $name)
                    if recorder.recording {
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            Label("正在录音", systemImage: "record.circle").foregroundStyle(.red)
                        }
                        Button("停止录音", systemImage: "stop.circle") { recorder.stop() }
                    } else if recorder.url == nil {
                        Button(recorder.requesting ? "正在申请权限…" : "开始录音", systemImage: "mic") { Task { await recorder.start() } }
                            .disabled(recorder.requesting)
                    } else {
                        Label("录音已停止", systemImage: "waveform")
                        Button("试听") { if let url = recorder.url { preview = AttachmentPreview(url: url, title: "录音预览") } }
                        Button("重新录制", role: .destructive) { discard = true }
                    }
                } footer: { Text("最长录制 60 分钟。离开 App 或收到音频中断时停止录音；点击保存后才会添加到附件。") }
                if let message = errorText ?? recorder.errorMessage { Text(message).foregroundStyle(.red) }
            }.navigationTitle("录音附件").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { recorder.discard(); dismiss() }.disabled(saving || recorder.requesting)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(saving ? "保存中…" : "保存") { Task { await save() } }
                            .disabled(recorder.recording || recorder.url == nil || saving || recorder.requesting)
                    }
                }
                .confirmationDialog("放弃这段录音并重新录制？", isPresented: $discard, titleVisibility: .visible) {
                    Button("重新录制", role: .destructive) { Task { await recorder.start() } }
                }
                .sheet(item: $preview) { FilePreview(file: $0).ignoresSafeArea() }
        }.interactiveDismissDisabled(recorder.recording || recorder.url != nil || saving || recorder.requesting)
            .onChange(of: scenePhase) { _, phase in if phase != .active && recorder.recording { recorder.stop() } }
            .onDisappear { recorder.discard() }
    }
    private func save() async {
        guard let url = recorder.url else { return }
        saving = true
        defer { saving = false }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = (trimmed.isEmpty ? "录音 " + Date.now.formatted(.dateTime.year().month().day().hour().minute()) : trimmed) + ".m4a"
        if await store.importAttachment(from: url, taskID: taskID, stepID: stepID, kind: .audio, filename: title) {
            recorder.discard(); dismiss()
        } else { errorText = store.errorMessage; store.errorMessage = nil }
    }
}
