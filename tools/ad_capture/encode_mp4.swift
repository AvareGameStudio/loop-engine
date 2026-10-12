// Builds an H.264 + AAC mp4 from AdCapture's JPG frames and Movie Maker's WAV, with no ffmpeg.
//   swift tools/ad_capture/encode_mp4.swift <frames_dir> <audio.wav> <out.mp4> [fps]
// <frames_dir> holds frame_00000.jpg... and start_frame.txt (the Movie Maker frame where
// capture began), so the audio is trimmed to start on the first captured frame.
import AVFoundation
import CoreImage
import Foundation
import ImageIO

let args = CommandLine.arguments
guard args.count >= 4 else {
    print("usage: encode_mp4.swift <frames_dir> <audio.wav> <out.mp4> [fps]")
    exit(2)
}
let framesDir = URL(fileURLWithPath: args[1])
let audioURL = URL(fileURLWithPath: args[2])
let outURL = URL(fileURLWithPath: args[3])
let fps = Int32(args.count > 4 ? Int(args[4]) ?? 30 : 30)

let names = try FileManager.default.contentsOfDirectory(atPath: framesDir.path)
    .filter { $0.hasPrefix("frame_") && $0.hasSuffix(".jpg") }
    .sorted()
guard let firstName = names.first else {
    print("no frames in \(framesDir.path)")
    exit(1)
}
let startFrame = Int((try? String(contentsOf: framesDir.appendingPathComponent("start_frame.txt"), encoding: .utf8))?
    .trimmingCharacters(in: .whitespacesAndNewlines) ?? "0") ?? 0

func loadImage(_ name: String) -> CGImage? {
    let url = framesDir.appendingPathComponent(name)
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
}

guard let first = loadImage(firstName) else {
    print("cannot read \(firstName)")
    exit(1)
}
let width = first.width
let height = first.height

// 1) Video-only mp4.
let videoURL = outURL.deletingPathExtension().appendingPathExtension("video.mp4")
try? FileManager.default.removeItem(at: videoURL)
let writer = try AVAssetWriter(outputURL: videoURL, fileType: .mp4)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: width,
    AVVideoHeightKey: height,
    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 6_000_000],
])
input.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
    kCVPixelBufferWidthKey as String: width,
    kCVPixelBufferHeightKey as String: height,
])
writer.add(input)
writer.startWriting()
writer.startSession(atSourceTime: .zero)

for (i, name) in names.enumerated() {
    guard let image = loadImage(name) else { continue }
    while !input.isReadyForMoreMediaData { usleep(1000) }
    var buffer: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
    guard let pb = buffer else { continue }
    CVPixelBufferLockBaseAddress(pb, [])
    let ctx = CGContext(
        data: CVPixelBufferGetBaseAddress(pb), width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: CVPixelBufferGetBytesPerRow(pb), space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)
    ctx?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    CVPixelBufferUnlockBaseAddress(pb, [])
    adaptor.append(pb, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: fps))
}
input.markAsFinished()
let done = DispatchSemaphore(value: 0)
writer.finishWriting { done.signal() }
done.wait()
guard writer.status == .completed else {
    print("video write failed: \(String(describing: writer.error))")
    exit(1)
}

// 2) Mux the audio, trimmed to the first captured frame, and export with AAC.
let video = AVURLAsset(url: videoURL)
let audio = AVURLAsset(url: audioURL)
let comp = AVMutableComposition()
let duration = CMTime(value: CMTimeValue(names.count), timescale: fps)
let sem = DispatchSemaphore(value: 0)
var vTrack: AVAssetTrack?
var aTrack: AVAssetTrack?
Task {
    vTrack = try? await video.loadTracks(withMediaType: .video).first
    aTrack = try? await audio.loadTracks(withMediaType: .audio).first
    sem.signal()
}
sem.wait()
guard let vt = vTrack else {
    print("no video track")
    exit(1)
}
let cv = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
try cv.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: vt, at: .zero)
if let at = aTrack {
    let ca = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
    let offset = CMTime(value: CMTimeValue(startFrame), timescale: fps)
    try? ca.insertTimeRange(CMTimeRange(start: offset, duration: duration), of: at, at: .zero)
} else {
    print("warning: no audio track in \(audioURL.path), exporting silent video")
}
try? FileManager.default.removeItem(at: outURL)
guard let export = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetHighestQuality) else {
    print("cannot create export session")
    exit(1)
}
export.outputURL = outURL
export.outputFileType = .mp4
let exported = DispatchSemaphore(value: 0)
export.exportAsynchronously { exported.signal() }
exported.wait()
guard export.status == .completed else {
    print("export failed: \(String(describing: export.error))")
    exit(1)
}
try? FileManager.default.removeItem(at: videoURL)
print("wrote \(outURL.path): \(names.count) frames, \(width)x\(height) @ \(fps) fps, audio offset \(startFrame) frames")
