//
//  RegistrationView.swift
//  FaceRecognitionDemo
//
//  Created by Abelito Faleyrio Visese on 02/06/25.
//

import SwiftUI
import CoreGraphics // For CGImage when mapping
import UIKit      // For UIImage in saveCapturedFaces

struct RegistrationView: View {
    @StateObject private var cameraManager = CameraManager()
    @Environment(\.presentationMode) var presentationMode

    @State private var personName: String = ""
    @State private var isRecording: Bool = false
    @State private var capturedImages: [Image] = [] // For UI thumbnails

    // Define how many samples you want to collect per registration
    private let numberOfSamplesToCollect = 100 // Or 15, 20, etc.

    var body: some View {
        VStack {
            Text("Register New Face")
                .font(.largeTitle)
                .padding()

            ZStack {
                CameraPreviewView(session: cameraManager.session)
                    .frame(height: 300)
                    .cornerRadius(10)
                    .padding()
            }
            .allowsHitTesting(false)

            if !capturedImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(0..<capturedImages.count, id: \.self) { index in
                            capturedImages[index]
                                .resizable()
                                .scaledToFit()
                                .frame(width: 60, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.gray))
                        }
                    }
                    Text("Collected \(capturedImages.count) / \(numberOfSamplesToCollect) samples")
                        .font(.caption)
                        .padding(.top, 2)
                }
                .frame(height: 90) // Adjusted height for text
                .padding(.horizontal)
            }
            
            TextField("Enter Name", text: $personName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()

            Button(action: {
                isRecording.toggle()
                if isRecording {
                    print("RegistrationView: Started recording face frames...")
                    // Clear UI thumbnails; CameraManager's startFaceSampling should clear its own samples.
                    self.capturedImages.removeAll()
                    cameraManager.startFaceSampling(targetSamples: numberOfSamplesToCollect)
                } else {
                    print("RegistrationView: Stopped recording face frames.")
                    cameraManager.stopFaceSampling()
                }
            }) {
                // Updated button text to reflect sample count and target
                let recordButtonText = isRecording ?
                    "Stop Recording (\(cameraManager.sampledFaceCGImages.count)/\(numberOfSamplesToCollect))" :
                    "Start Recording Faces"
                Text(recordButtonText)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(isRecording ? Color.red : Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding(.horizontal)
            // Disable button if max samples reached while recording
            .disabled(isRecording && cameraManager.sampledFaceCGImages.count >= numberOfSamplesToCollect)


            Button(action: {
                saveCapturedFaces()
            }) {
                Text("Save Registration")
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(canSave() ? Color.blue : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding([.horizontal, .bottom])
            .disabled(!canSave())

            Spacer()
        }
        .onReceive(cameraManager.$sampledFaceCGImages) { cgImages in
            // Update UI thumbnails when CameraManager publishes new CGImage samples
            self.capturedImages = cgImages.map { Image(decorative: $0, scale: 1.0, orientation: .up) }
            // If max samples are reached, automatically toggle recording off
            if cgImages.count >= numberOfSamplesToCollect && self.isRecording {
                print("RegistrationView: Max samples reached, auto-stopping.")
                self.isRecording = false
                // cameraManager.stopFaceSampling() // This is already called by CameraManager itself
            }
        }
        .onAppear {
            cameraManager.startSession()
        }
        .onDisappear {
            cameraManager.stopSession()
            if isRecording { // Ensure sampling stops if view disappears
                isRecording = false
                cameraManager.stopFaceSampling()
            }
        }
    }
    
    private func canSave() -> Bool {
        // Check against the actual data source for saving and ensure enough samples are collected
        return !personName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
               cameraManager.sampledFaceCGImages.count >= numberOfSamplesToCollect && // Ensure enough samples
               !isRecording // Should not be recording when trying to save
    }

    private func saveCapturedFaces() {
        guard canSave() else {
             print("Cannot save. Conditions not met: Name empty, not enough samples, or still recording.")
             // You could show an alert here with a more specific reason
             return
         }
        
        let name = personName.trimmingCharacters(in: .whitespacesAndNewlines)
        // Get the actual CGImages from CameraManager
        let imagesToSave = cameraManager.sampledFaceCGImages
        
        print("Attempting to save \(imagesToSave.count) images for \(name)...")
        
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("Error: Could not access documents directory.")
            return
        }
        
        let mainDatasetDirectoryURL = documentsDirectory.appendingPathComponent("FaceRecognitionDataset")
        do {
            if !FileManager.default.fileExists(atPath: mainDatasetDirectoryURL.path) {
                try FileManager.default.createDirectory(at: mainDatasetDirectoryURL, withIntermediateDirectories: true, attributes: nil)
                print("Created main dataset directory: \(mainDatasetDirectoryURL.path)")
            }
        } catch {
            print("Error creating main dataset directory: \(error.localizedDescription)")
            return
        }
        
        let personDirectoryURL = mainDatasetDirectoryURL.appendingPathComponent(name)
        do {
            if FileManager.default.fileExists(atPath: personDirectoryURL.path) {
                // Option: Overwrite, ask user, or create new with unique name. For now, let's just proceed.
                // You might want to remove old images if re-registering the same name:
                // try? FileManager.default.removeItem(at: personDirectoryURL)
            }
            try FileManager.default.createDirectory(at: personDirectoryURL, withIntermediateDirectories: true, attributes: nil)
            print("Created/Ensured directory for person: \(personDirectoryURL.path)")
        } catch {
            print("Error creating directory for person \(name): \(error.localizedDescription)")
            return
        }
        
        var savedCount = 0
        for (index, cgImage) in imagesToSave.enumerated() {
            let uiImage = UIImage(cgImage: cgImage)
            guard let imageData = uiImage.jpegData(compressionQuality: 0.85) else { // Slightly higher quality
                print("Error converting CGImage \(index) to JPEG data for \(name).")
                continue
            }
            
            let fileName = "\(name.lowercased().replacingOccurrences(of: " ", with: "_"))_face_\(String(format: "%03d", index + 1)).jpg"
            let fileURL = personDirectoryURL.appendingPathComponent(fileName)
            
            do {
                try imageData.write(to: fileURL)
                print("Saved image to: \(fileURL.path)")
                savedCount += 1
            } catch {
                print("Error saving image \(fileName) for \(name): \(error.localizedDescription)")
            }
        }
        
        if savedCount == imagesToSave.count && savedCount > 0 {
            print("Successfully saved \(savedCount) images for \(name).")
            // TODO: Show success alert to user
        } else if savedCount > 0 {
            print("Partially saved \(savedCount) out of \(imagesToSave.count) images for \(name).")
            // TODO: Show partial success/error alert
        } else {
            print("Failed to save any images for \(name).")
            // TODO: Show failure alert
        }
        
        DispatchQueue.main.async {
            cameraManager.sampledFaceCGImages.removeAll()
            // self.capturedImages.removeAll() // This will be handled by .onReceive
        }
        
        presentationMode.wrappedValue.dismiss()
    }
}

struct RegistrationView_Previews: PreviewProvider {
    static var previews: some View {
        RegistrationView()
    }
}
