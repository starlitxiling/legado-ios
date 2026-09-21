import SwiftUI
import PhotosUI
import VisionKit
import CoreImage

struct SourceGroupManagementView: View {
    @Bindable var model: SourcesViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var editing: String?
    @State private var name = ""
    var body: some View {
        NavigationStack {
            List {
                ForEach(model.groups, id: \.self) { group in
                    Button(group) { editing = group; name = group }
                        .swipeActions { Button("删除", role: .destructive) { Task { await model.renameGroup(group, to: "") } } }
                }
                if let error = model.errorMessage { Text(error).foregroundStyle(.red) }
            }.legadoNavigationTitle("分组管理")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
                .alert("重命名分组", isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
                    TextField("分组名称", text: $name)
                    Button("保存") { if let editing { Task { await model.renameGroup(editing, to: name) } }; editing = nil }
                    Button("取消", role: .cancel) { editing = nil }
                }
        }
    }
}

struct SourceQRImportView: View {
    let completion: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var photo: PhotosPickerItem?
    @State private var error: String?
    @State private var scanning = false
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if scanning { SourceQRScanner(completion: completion, failure: { error = $0; scanning = false }).ignoresSafeArea(edges: .bottom) }
                else {
                    Image(systemName: "qrcode.viewfinder").font(.system(size: 80))
                    Button("扫描二维码") { scanning = true }
                        .disabled(!DataScannerViewController.isSupported || !DataScannerViewController.isAvailable)
                    PhotosPicker("从图片识别", selection: $photo, matching: .images)
                    if let error { Text(error).foregroundStyle(.red) }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .legadoNavigationTitle("二维码导入")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
                .task(id: photo) {
                    guard let photo else { return }
                    do {
                        guard let data = try await photo.loadTransferable(type: Data.self), let image = CIImage(data: data),
                              let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]),
                              let text = (detector.features(in: image).first as? CIQRCodeFeature)?.messageString else {
                            error = "未找到可识别的二维码。"; return
                        }
                        completion(text)
                    } catch { self.error = error.localizedDescription }
                }
        }
    }
}

private struct SourceQRScanner: UIViewControllerRepresentable {
    let completion: (String) -> Void
    let failure: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion) }
    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])], qualityLevel: .balanced, recognizesMultipleItems: false)
        scanner.delegate = context.coordinator
        do { try scanner.startScanning() } catch { DispatchQueue.main.async { failure(error.localizedDescription) } }
        return scanner
    }
    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}
    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) { controller.stopScanning() }
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let completion: (String) -> Void
        private var finished = false
        init(_ completion: @escaping (String) -> Void) { self.completion = completion }
        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !finished else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item, let text = barcode.payloadStringValue { finished = true; dataScanner.stopScanning(); completion(text); return }
            }
        }
    }
}
