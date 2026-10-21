import Foundation
import SwiftUI
import UniformTypeIdentifiers
import AVFoundation
import OpenSuperWhisperCore

@MainActor
class FileDropHandler: ObservableObject {
    static let shared = FileDropHandler()
    
    @Published var isDragging = false
    
    /// Audio, and videos whose sound the queue extracts.
    static let acceptedTypes: [UTType] = [.audio, .movie]

    private let transcriptionQueue: TranscriptionQueue
    
    private init() {
        self.transcriptionQueue = TranscriptionQueue.shared
    }
    
    func handleDrop(of providers: [NSItemProvider]) async {
        for provider in providers {
            if let type = Self.acceptedTypes.first(where: { provider.hasItemConformingToTypeIdentifier($0.identifier) }) {
                do {
                    let url = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL?, Error>) in
                        provider.loadItem(forTypeIdentifier: type.identifier) { item, error in
                            if let error = error {
                                continuation.resume(throwing: error)
                                return
                            }
                            continuation.resume(returning: item as? URL)
                        }
                    }
                    
                    guard let url = url else {
                        print("Error loading item: not a URL")
                        continue
                    }
                    
                    print("Adding to queue: \(url)")
                    await transcriptionQueue.addFileToQueue(url: url)
                    
                } catch {
                    print("Error loading dropped file: \(error)")
                }
            }
        }
    }
}

struct FileDropOverlay: ViewModifier {
    @ObservedObject private var handler: FileDropHandler
    
    init() {
        self.handler = FileDropHandler.shared
    }
    
    func body(content: Content) -> some View {
        content
            .overlay {
                if handler.isDragging {
                    ZStack {
                        Color(NSColor.windowBackgroundColor)
                            .opacity(0.95)
                        VStack(spacing: 16) {
                            Image(systemName: "arrow.down.circle")
                                .scaledFont(size: 48)
                                .foregroundColor(.accentColor)
                                .symbolEffect(.bounce, value: handler.isDragging)
                            Text("Drop audio or video files to transcribe")
                                .font(.headline)
                            Text("Multiple files will be queued")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .ignoresSafeArea()
                }
            }
            .onDrop(of: FileDropHandler.acceptedTypes, isTargeted: $handler.isDragging) { providers in
                Task {
                    await handler.handleDrop(of: providers)
                }
                return true
            }
    }
}

extension View {
    func fileDropHandler() -> some View {
        modifier(FileDropOverlay())
    }
}
