//
//  CameraPreviewView.swift
//  FaceRecognitionDemo
//
//  Created by Abelito Faleyrio Visese on 02/06/25.
//

import SwiftUI
import AVFoundation

class PreviewHostingView: UIView {
    var previewLayer: AVCaptureVideoPreviewLayer // Make it non-optional for simplicity here

    init(session: AVCaptureSession) {
        self.previewLayer = AVCaptureVideoPreviewLayer(session: session) // Initialize it here
        super.init(frame: .zero) // Initial frame, will be updated by layout system

        self.previewLayer.videoGravity = .resizeAspectFill
        self.previewLayer.backgroundColor = UIColor.blue.cgColor // Blue background for the layer
        self.layer.addSublayer(self.previewLayer)
        
        print("PreviewHostingView: init called, previewLayer added to self.layer.")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // 2. Override layoutSubviews to set the previewLayer's frame
    override func layoutSubviews() {
        super.layoutSubviews()
        // This is the crucial part: when this view (PreviewHostingView) is laid out,
        // it sets its sublayer's (previewLayer) frame to fill its own bounds.
        previewLayer.frame = self.bounds
        print("PreviewHostingView: layoutSubviews - self.frame: \(self.frame), previewLayer.frame was set to: \(self.bounds)")
    }
}

// 3. Modify CameraPreviewView to use this PreviewHostingView
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewHostingView {
        print("CameraPreviewView: makeUIView - creating PreviewHostingView.")
        let hostingView = PreviewHostingView(session: session)
        return hostingView
    }

    func updateUIView(_ uiView: PreviewHostingView, context: Context) {
        // uiView is the PreviewHostingView instance.
        // Its layout (and thus its previewLayer's frame) is handled by its own layoutSubviews.
        // We mainly use updateUIView to react to SwiftUI state changes if needed (e.g., if the session itself could change).
        
        print("CameraPreviewView: updateUIView - uiView.frame (from SwiftUI's perspective): \(uiView.frame)") // What SwiftUI thinks its frame is
        print("CameraPreviewView: updateUIView - session.isRunning: \(session.isRunning)")
        
        if !session.inputs.isEmpty {
            print("CameraPreviewView: updateUIView - session has inputs: \(session.inputs.count)")
        } else {
            print("CameraPreviewView: updateUIView - session has NO inputs!")
        }

        // You can still set connection properties here if needed, accessing via uiView.previewLayer
        if let connection = uiView.previewLayer.connection {
            // print("CameraPreviewView: updateUIView - previewLayer.connection.isActive: \(connection.isActive), .isEnabled: \(connection.isEnabled)")
            // print("CameraPreviewView: updateUIView - previewLayer.connection.isActive: \(connection.isActive), .isEnabled: \(connection.isEnabled)")
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
        }
    }
    
    // Coordinator is not strictly necessary anymore if PreviewHostingView manages its own layer
    // and doesn't need to communicate back to CameraPreviewView via delegate patterns.
}

#Preview {
    var cameraManager = CameraManager()
    
    CameraPreviewView(session: cameraManager.session)
}
