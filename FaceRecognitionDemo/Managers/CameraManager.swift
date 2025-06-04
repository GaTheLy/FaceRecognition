//
//  CameraManager.swift
//  FaceRecognitionDemo
//
//  Created by Abelito Faleyrio Visese on 02/06/25.
//

import AVFoundation
import SwiftUI // For ObservableObject, CGRect, CGImage
import Vision   // For Vision framework
import CoreImage // For CIImage in cropping, if ImageProcessingUtils uses it

class CameraManager: NSObject, ObservableObject {
    
    let session = AVCaptureSession()
    private var frontCameraInput: AVCaptureDeviceInput?
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.FaceRecognitionDemo.sessionQueue", qos: .userInitiated)
    
    // For displaying bounding boxes from VNDetectFaceRectanglesRequest
    @Published var detectedFacesBoundingBoxes: [CGRect] = []
    
    // For face sampling during registration
    @Published var sampledFaceCGImages: [CGImage] = []
    var isSamplingFaces: Bool = false
    var maxFaceSamplesInternal: Int { // Expose maxFaceSamples for UI display if needed
        return maxFaceSamples
    }
    private var maxFaceSamples: Int = 10 // Default, can be changed by startFaceSampling
    private var currentSampleCount: Int = 0
    
    override init() {
        super.init()
        sessionQueue.async {
            self.checkCameraPermissions()
        }
    }
    
    func checkCameraPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            print("CameraManager: Camera permission authorized.")
            // No need to dispatch to sessionQueue again, we are already on it from init
            self.setupCaptureSession()
            
        case .notDetermined:
            print("CameraManager: Camera permission not determined. Requesting access.")
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self = self else { return }
                if granted {
                    print("CameraManager: Camera permission granted.")
                    self.sessionQueue.async { // Ensure setup is on the session queue
                        self.setupCaptureSession()
                    }
                } else {
                    print("CameraManager: Camera permission denied by user.")
                    // TODO: Handle UI update to inform user permission is needed
                }
            }
            
        case .denied, .restricted:
            print("CameraManager: Camera permission denied or restricted.")
            // TODO: Handle UI update to inform user permission is needed
            return
            
        @unknown default:
            print("CameraManager: Unknown camera permission status.")
            return
        }
    }
    
    func setupCaptureSession() {
        guard !session.isRunning else {
            print("CameraManager: Session is already running. Setup skipped.")
            return
        }
        
        session.beginConfiguration()
        
        if session.canSetSessionPreset(.iFrame1280x720) { // Using 720p for a balance
            session.sessionPreset = .iFrame1280x720
        } else {
            print("CameraManager: Could not set session preset to .hd1280x720. Using default.")
            session.sessionPreset = .high // Fallback
        }
        
        guard let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            print("CameraManager: Error: Could not find front camera.")
            session.commitConfiguration()
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: frontCamera)
            if session.canAddInput(input) {
                session.addInput(input)
                self.frontCameraInput = input
            } else {
                print("CameraManager: Error: Could not add front camera input to session.")
                session.commitConfiguration()
                return
            }
        } catch {
            print("CameraManager: Error creating device input: \(error.localizedDescription)")
            session.commitConfiguration()
            return
        }
        
        videoDataOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        
        if session.canAddOutput(videoDataOutput) {
            session.addOutput(videoDataOutput)
        } else {
            print("CameraManager: Error: Could not add video data output to session.")
            session.commitConfiguration()
            return
        }
        
        session.commitConfiguration()
        print("CameraManager: Capture session setup complete.")
    }
    
    func startSession() {
        sessionQueue.async {
            if !self.session.isRunning {
                self.session.startRunning()
                print("CameraManager: Capture session started.")
            } else {
                print("CameraManager: Capture session already running.")
            }
        }
    }
    
    func stopSession() {
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
                self.isSamplingFaces = false // Ensure sampling stops if session stops
                print("CameraManager: Capture session stopped.")
            } else {
                print("CameraManager: Capture session already stopped.")
            }
        }
    }

    // MARK: - Face Sampling Control
    func startFaceSampling(targetSamples: Int = 100) {
        // Ensure this is called from the main thread if triggered by UI,
        // but the actual state changes can be managed here.
        // The properties themselves will be updated on main via @Published if needed by subscribers.
        print("CameraManager: startFaceSampling called. Target: \(targetSamples)")
        DispatchQueue.main.async { // Ensure @Published property is updated on main for immediate UI reflection
             self.sampledFaceCGImages.removeAll()
        }
        self.currentSampleCount = 0
        self.maxFaceSamples = targetSamples
        self.isSamplingFaces = true
    }

    func stopFaceSampling() {
        self.isSamplingFaces = false
        print("CameraManager: stopFaceSampling called. Collected \(self.currentSampleCount) of \(self.maxFaceSamples) samples.")
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("CameraManager: Failed to get CVPixelBuffer from sample buffer.")
            return
        }
        let bufferWidth = CVPixelBufferGetWidth(pixelBuffer)
        let bufferHeight = CVPixelBufferGetHeight(pixelBuffer)
        print("CameraManager: PixelBuffer dimensions - Width: \(bufferWidth), Height: \(bufferHeight)")
        
        // This print can be very noisy, comment out once things are working.
        // print("CameraManager: Captured a frame. isSamplingFaces: \(isSamplingFaces), currentSampleCount: \(currentSampleCount)")

        let faceDetectionRequest = VNDetectFaceRectanglesRequest { (request, error) in
            // Pass the pixelBuffer to the handler for potential cropping
            self.handleFaceDetectionObservations(request: request, error: error, pixelBuffer: pixelBuffer)
        }
        
        // !!! IMPORTANT !!! THE 'orientation' PARAMETER IS CRITICAL!
        // Your previous issue ("bounding box only around eyes" and raw H being much smaller than W)
        // STRONGLY suggests this orientation might be incorrect for your setup.
        // `.leftMirrored` is a common starting point for front camera in portrait.
        // If your saved cropped faces are distorted/incorrect, you MUST provide the diagnostic info:
        // 1. The ACTUAL `orientation` value you are using here.
        // 2. The console output for "PixelBuffer dimensions" (add a print for CVPixelBufferGetWidth/Height here).
        // 3. The console output for "GeometryReader size" from your SwiftUI view.
        // Only with that info can the correct orientation be determined.
        
        let currentOrientation: CGImagePropertyOrientation = .leftMirrored // Store this
        let imageRequestHandler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: currentOrientation,
            options: [:]
        )
        
        do {
            try imageRequestHandler.perform([faceDetectionRequest])
        } catch {
            print("CameraManager: Failed to perform face detection request: \(error.localizedDescription)")
        }
    }
    
    func handleFaceDetectionObservations(request: VNRequest, error: Error?, pixelBuffer: CVPixelBuffer) {
        if let nsError = error as NSError? {
            print("CameraManager: Face detection error: \(nsError.localizedDescription)")
            DispatchQueue.main.async {
                self.detectedFacesBoundingBoxes = []
                // If an error occurs during sampling, consider stopping sampling
                // if self.isSamplingFaces { self.stopFaceSampling() }
            }
            return
        }

        guard let observations = request.results as? [VNFaceObservation] else {
            DispatchQueue.main.async {
                self.detectedFacesBoundingBoxes = []
            }
            return
        }
        
        // --- Face Sampling Logic ---
        if isSamplingFaces && currentSampleCount < maxFaceSamples {
            if let firstFaceObservation = observations.first {
                // Ensure ImageProcessingUtils.cropFace is available in your project
                let visionOrientation: CGImagePropertyOrientation = .leftMirrored
                if let croppedCGImage = ImageProcessingUtils.cropFace(
                    from: pixelBuffer,
                    normalizedBoundingBox: firstFaceObservation.boundingBox,
                    orientationForVision: visionOrientation,
                    targetSize: CGSize(width: 224, height: 224)) {
                    
                    DispatchQueue.main.async { // Modifying @Published property
                        self.sampledFaceCGImages.append(croppedCGImage)
                        self.currentSampleCount = self.sampledFaceCGImages.count // Update count based on array
                        print("CameraManager: Sampled face image #\(self.currentSampleCount) / \(self.maxFaceSamples)")
                        
                        if self.currentSampleCount >= self.maxFaceSamples {
                            self.stopFaceSampling()
                        }
                    }
                } else {
                    print("CameraManager: Failed to crop face for sampling.")
                }
            }
        }
        // --- End Face Sampling Logic ---

        // Update bounding boxes for UI display (if any view is observing this)
        let displayBoundingBoxes = observations.map { $0.boundingBox }
        DispatchQueue.main.async {
            self.detectedFacesBoundingBoxes = displayBoundingBoxes
        }
    }
}
