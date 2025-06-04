//
//  ImageProcessingUtils.swift
//  FaceRecognitionDemo
//
//  Created by Abelito Faleyrio Visese on 02/06/25.
//

import AVFoundation
import UIKit
import CoreImage
import CoreGraphics

class ImageProcessingUtils {

    static func cropFace(from pixelBuffer: CVPixelBuffer,
                         normalizedBoundingBox: CGRect,
                         orientationForVision: CGImagePropertyOrientation, // <<< NEW PARAMETER
                         targetSize: CGSize? = CGSize(width: 224, height: 224)) -> CGImage? {

        // 1. Create CIImage from the raw pixel buffer
        let originalCIImage = CIImage(cvPixelBuffer: pixelBuffer)

        // 2. Apply the SAME orientation transform that Vision used
        // This makes the ciImage appear "upright" as Vision saw it.
        let orientedCIImage = originalCIImage.oriented(orientationForVision)
        
        // The imageSize for denormalization should now be from the orientedCIImage
        let imageSizeForDenormalization = orientedCIImage.extent.size

        // 3. Denormalize the bounding box relative to this oriented image's dimensions
        // Vision's normalizedBoundingBox origin is bottom-left, matching CIImage.
        let denormalizedBoundingBox = CGRect(
            x: normalizedBoundingBox.origin.x * imageSizeForDenormalization.width,
            y: normalizedBoundingBox.origin.y * imageSizeForDenormalization.height,
            width: normalizedBoundingBox.width * imageSizeForDenormalization.width,
            height: normalizedBoundingBox.height * imageSizeForDenormalization.height
        )
        
        // Ensure the crop box is within the image bounds
        let validCropBox = denormalizedBoundingBox.intersection(orientedCIImage.extent)
        guard !validCropBox.isNull, !validCropBox.isEmpty else {
            print("ImageProcessingUtils: Invalid crop box. Normalized: \(normalizedBoundingBox), Denormalized: \(denormalizedBoundingBox), Oriented Extent: \(orientedCIImage.extent)")
            return nil
        }
        
        let croppedCIImage = orientedCIImage.cropped(to: validCropBox)

        // 4. Optional resize
        var finalCIImage = croppedCIImage
        if let targetSize = targetSize, !croppedCIImage.extent.isEmpty {
            let scaleX = targetSize.width / croppedCIImage.extent.width
            let scaleY = targetSize.height / croppedCIImage.extent.height
            if scaleX.isFinite && scaleY.isFinite && scaleX > 0 && scaleY > 0 {
                 finalCIImage = croppedCIImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            } else {
                print("ImageProcessingUtils: Invalid scale factors for resizing.")
            }
        }
        
        // 5. Convert to CGImage
        let context = CIContext(options: nil)
        guard !finalCIImage.extent.isEmpty,
              let cgImage = context.createCGImage(finalCIImage, from: finalCIImage.extent) else {
            print("ImageProcessingUtils: Failed to create CGImage. Final CIImage extent: \(finalCIImage.extent)")
            return nil
        }
        
        return cgImage
    }
}
