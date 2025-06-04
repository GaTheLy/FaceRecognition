//
//  ContentView.swift
//  FaceRecognitionDemo
//
//  Created by Abelito Faleyrio Visese on 02/06/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    
    var body: some View {
        NavigationView {
            ZStack {
                CameraPreviewView(session: cameraManager.session)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
                
                // Overlay for bounding boxes
                GeometryReader { geometryProxy in // geometryProxy gives you the size of CameraPreviewView
                    ForEach(cameraManager.detectedFacesBoundingBoxes.indices, id: \.self) { index in
                        let normalizedBox = cameraManager.detectedFacesBoundingBoxes[index]
                        
                        // Convert normalizedBox to screen coordinates
                        let rectInSwiftUICoordinates = CGRect(
                            x: normalizedBox.origin.x * geometryProxy.size.width,
                            y: (1 - normalizedBox.maxY) * geometryProxy.size.height,
                            width: normalizedBox.width * geometryProxy.size.width,
                            height: normalizedBox.height * geometryProxy.size.height
                        )
                        
                        Rectangle()
                            .stroke(Color.red, lineWidth: 3) // Made line thicker for visibility
                            .frame(width: rectInSwiftUICoordinates.width, height: rectInSwiftUICoordinates.height)
                            .position(x: rectInSwiftUICoordinates.midX, y: rectInSwiftUICoordinates.midY)
                    }
                }
                .allowsHitTesting(false) // Important: So the overlay doesn't block your button
                
                // Button
                VStack {
                    Spacer()
                    
                    NavigationLink("Register A New Face", destination: RegistrationView())
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue.opacity(0.7))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        .padding(.horizontal)
                        .padding(.bottom, 30)
                }
            }
            .navigationTitle("Face Recognition")
            .navigationBarHidden(true)
            .onAppear {
                // CameraManager's init -> checkCameraPermissions -> setupCaptureSession (simplified version)
                // will be called. Then we start the session.
                print("ContentView: .onAppear has been called.")
                cameraManager.startSession()
            }
            .onDisappear {
                cameraManager.stopSession()
            }
        }
    }
}

#Preview {
    ContentView()
}
