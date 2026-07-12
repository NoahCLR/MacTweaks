import AppKit
import Foundation
import Vision
import os

/// Screen-region OCR: run macOS's own interactive capture (`screencapture -i`,
/// which gives the native crosshair selection UI for free), recognize text in the
/// grab with the Vision framework, and put the result on the general pasteboard.
///
/// App-only and OS-bound: the capture (a subprocess) and Vision both need a real
/// screen and the Screen Recording permission, so there is nothing to unit-test
/// here except the pure text assembly (`assembleText`) — see `HotKeyTests`.
final class OCRService {
    private let logger = Logger(subsystem: "com.ncleroy.MacTweaks", category: "OCR")
    private let workQueue = DispatchQueue(label: "com.ncleroy.MacTweaks.ocr", qos: .userInitiated)
    /// Confirmation toast; touched from the main queue only.
    private let toast = OCRToastPresenter()

    /// Guards against overlapping runs if the hotkey is hammered — a second
    /// invocation while a capture UI is already up is dropped.
    private var isBusy = false

    /// Capture a screen region and copy any recognized text to the clipboard.
    /// Silent when the user cancels the selection (Esc). Beeps on a hard failure
    /// or when the grab contained no text, so the hotkey never feels dead.
    func captureAndCopy() {
        guard !isBusy else {
            logger.info("OCR ignored: a capture is already in progress")
            return
        }
        isBusy = true

        workQueue.async { [weak self] in
            guard let self else { return }
            defer { self.isBusy = false }

            guard let imageURL = self.captureRegionToTempFile() else {
                // User pressed Esc, or the capture produced nothing — not an error.
                return
            }
            defer { try? FileManager.default.removeItem(at: imageURL) }

            guard let cgImage = self.loadCGImage(from: imageURL) else {
                self.logger.error("OCR failed: could not load captured image")
                self.failOnMain()
                return
            }

            let text = self.recognizeText(in: cgImage)
            DispatchQueue.main.async {
                guard !text.isEmpty else {
                    self.logger.info("OCR found no text in the selection")
                    self.toast.showNoTextFound()
                    return
                }
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
                self.logger.info("OCR copied \(text.count) character(s) to the clipboard")
                self.toast.showCopied(text)
            }
        }
    }

    // MARK: - Capture

    /// Runs the system interactive screen capture into a temporary PNG. Returns nil
    /// when no file was written (the user cancelled the selection).
    private func captureRegionToTempFile() -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacTweaks-OCR-\(UUID().uuidString).png")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        // -i interactive selection, -x no camera sound, -t png output format.
        process.arguments = ["-i", "-x", "-t", "png", url.path]

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            logger.error("OCR capture failed to launch screencapture: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    private func loadCGImage(from url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    // MARK: - Recognition

    private func recognizeText(in image: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            logger.error("OCR recognition failed: \(error.localizedDescription, privacy: .public)")
            return ""
        }

        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return OCRService.assembleText(from: lines)
    }

    private func failOnMain() {
        DispatchQueue.main.async { NSSound.beep() }
    }

    /// Join recognized lines into the clipboard string. Vision returns one
    /// observation per detected text line, top-to-bottom; we keep that order,
    /// drop blank lines, and trim surrounding whitespace. Pure — tested directly.
    static func assembleText(from lines: [String]) -> String {
        lines
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
