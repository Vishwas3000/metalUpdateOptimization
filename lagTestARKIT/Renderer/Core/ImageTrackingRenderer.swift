//
//  ImageTrackingRenderer.swift
//  lagTestARKIT
//
//  Created by Vishwas Prakash on 21/04/25.
//

import Foundation
import Metal
import MetalKit
import ARKit


// Vertex structure for rectangle rendering
struct RectangleVertex {
    var position: SIMD3<Float>
    var color: SIMD4<Float>
}


/// Renderer for drawing content on tracked images
class ImageTrackingRenderer: BaseRenderer {
    // Tracked image data structure
    private struct TrackedImage {
        let id: UUID
        let name: String
        var transform: simd_float4x4
        let physicalSize: CGSize
        var isTracking: Bool
        
        // Render properties
        var color: simd_float4 = simd_float4(0.0, 1.0, 0.3, 1.0) // Default color
        var scale: Float = 1.0
        var outlineWidth: Float = 0.005 // 5mm outline width
    }
    
    // Currently tracked images
    private var trackedImages: [UUID: TrackedImage] = [:]
    
    // Outline rectangle geometry
    private var rectVertexBuffer: MTLBuffer?
    private var rectIndexBuffer: MTLBuffer?
    
    // Pipeline state
    private var rectanglePipelineState: MTLRenderPipelineState?
    private var depthState: MTLDepthStencilState?
    
    // Render order between background and anchors
    override var renderOrder: Int {
        get{
            return super.renderOrder
        }
        set{
            super.renderOrder = newValue
        }
    }
    
    override func setup(device: MTLDevice, library: MTLLibrary) {
        super.setup(device: device, library: library)
        
        // Create pipeline state for drawing rectangles
        setupRenderPipeline(device: device, library: library)
        
        // Create geometry for rectangles
        setupRectangleGeometry(device: device)
        
        // Create depth state
        let depthStateDescriptor = MTLDepthStencilDescriptor()
        depthStateDescriptor.depthCompareFunction = .less
        depthStateDescriptor.isDepthWriteEnabled = true
        depthState = device.makeDepthStencilState(descriptor: depthStateDescriptor)
    }
    
    private func setupRenderPipeline(device: MTLDevice, library: MTLLibrary) {
        // Get vertex and fragment functions
        guard let vertexFunction = library.makeFunction(name: "imageTrackingVertexShader"),
              let fragmentFunction = library.makeFunction(name: "imageTrackingFragmentShader") else {
            print("Failed to find image tracking shader functions")
            return
        }
        
        // Create a render pipeline descriptor
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "Rectangle Pipeline"
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = config.pixelFormat
        pipelineDescriptor.depthAttachmentPixelFormat = config.depthStencilFormat
        pipelineDescriptor.stencilAttachmentPixelFormat = config.depthStencilFormat
        
        // Configure blending for transparency
        let attachment = pipelineDescriptor.colorAttachments[0]
        attachment?.isBlendingEnabled = true
        attachment?.rgbBlendOperation = .add
        attachment?.alphaBlendOperation = .add
        attachment?.sourceRGBBlendFactor = .sourceAlpha
        attachment?.sourceAlphaBlendFactor = .one
        attachment?.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment?.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        // Create vertex descriptor to match shader attributes
        let vertexDescriptor = MTLVertexDescriptor()

        // Position attribute (index 0 for position)
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0

        // Color attribute (index 1 for color)
        vertexDescriptor.attributes[1].format = .float4
        vertexDescriptor.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride
        vertexDescriptor.attributes[1].bufferIndex = 0

        // Buffer layout
        vertexDescriptor.layouts[0].stride = MemoryLayout<SIMD3<Float>>.stride + MemoryLayout<SIMD4<Float>>.stride
        vertexDescriptor.layouts[0].stepRate = 1
        vertexDescriptor.layouts[0].stepFunction = .perVertex
        // Buffer layout
        vertexDescriptor.layouts[0].stride = MemoryLayout<SIMD3<Float>>.stride + MemoryLayout<SIMD4<Float>>.stride
        vertexDescriptor.layouts[0].stepRate = 1
        vertexDescriptor.layouts[0].stepFunction = .perVertex
        
        pipelineDescriptor.vertexDescriptor = vertexDescriptor
        
        // Create the pipeline state
        do {
            rectanglePipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("Failed to create rectangle pipeline state: \(error)")
        }
    }

    
    private func setupRectangleGeometry(device: MTLDevice) {
        // Create rectangle outline vertices
        let vertices = createRectangleOutlineVertices(color: simd_float4(0, 1, 0, 0.7))
        
        // Create vertex buffer
        rectVertexBuffer = device.makeBuffer(
            bytes: vertices,
            length: vertices.count * (MemoryLayout<SIMD3<Float>>.stride + MemoryLayout<SIMD4<Float>>.stride),
            options: .storageModeShared
        )
        rectVertexBuffer?.label = "RectangleVertexBuffer"
        
        // Create index buffer for line segments (outline)
        let indices: [UInt16] = [
            0, 1, 2,  // First triangle (bottom-left, bottom-right, top-right)
            0, 2, 3   // Second triangle (bottom-left, top-right, top-left)
        ]
        
        rectIndexBuffer = device.makeBuffer(
            bytes: indices,
            length: indices.count * MemoryLayout<UInt16>.stride,
            options: .storageModeShared
        )
        rectIndexBuffer?.label = "RectangleIndexBuffer"
    }
    
    private func createRectangleOutlineVertices(color: simd_float4) -> [RectangleVertex] {
        return [
            RectangleVertex(position: SIMD3<Float>(-0.5, -0.5, 0), color: color),
            RectangleVertex(position: SIMD3<Float>(0.5, -0.5, 0), color: color),
            RectangleVertex(position: SIMD3<Float>(0.5, 0.5, 0), color: color),
            RectangleVertex(position: SIMD3<Float>(-0.5, 0.5, 0), color: color)
        ]
    }
    
    // MARK: - Public Interface
    
    /// Start tracking a new image anchor
    func trackImage(anchor: ARImageAnchor) {
        let imageName = anchor.name ?? "unknown"
        let physicalSize = anchor.referenceImage.physicalSize
        
        // Create tracked image data
        let trackedImage = TrackedImage(
            id: anchor.identifier,
            name: imageName,
            transform: anchor.transform,
            physicalSize: physicalSize,
            isTracking: true
        )
        
        // Store in tracked images
        trackedImages[anchor.identifier] = trackedImage
        
        print("Now tracking image: \(imageName) with size: \(physicalSize)")
    }
    
    /// Update an existing image anchor
    func updateImageTracking(anchor: ARImageAnchor) {
        if var trackedImage = trackedImages[anchor.identifier] {
            trackedImage.transform = anchor.transform
            trackedImage.isTracking = true
            trackedImages[anchor.identifier] = trackedImage
        }
    }
    
    /// Stop tracking an image anchor
    func stopTrackingImage(anchorID: UUID) {
        trackedImages.removeValue(forKey: anchorID)
    }
    
    /// Set color for a specific tracked image
    func setColor(for imageID: UUID, color: SIMD4<Float>) {
        if var trackedImage = trackedImages[imageID] {
            trackedImage.color = color
            trackedImages[imageID] = trackedImage
        }
    }
    
    // MARK: - Rendering
    override func update(frame: ARFrame?) {
        super.update(frame: frame)
        
        // Update any tracked images that aren't in the current frame as not tracking
        if let frame = frame {
            let currentAnchorIDs = Set(frame.anchors.compactMap {
                ($0 as? ARImageAnchor)?.identifier
            })
            
            for (id, var image) in trackedImages where !currentAnchorIDs.contains(id) {
                image.isTracking = false
                trackedImages[id] = image
            }
        }
    }
    
   
    override func draw(renderEncoder: MTLRenderCommandEncoder,
                     uniformBuffer: MTLBuffer,
                       uniformBufferOffset: Int) {
        guard let rectanglePipelineState = rectanglePipelineState,
              let depthState = depthState,
              let rectVertexBuffer = rectVertexBuffer,
              let rectIndexBuffer = rectIndexBuffer,
              !trackedImages.isEmpty else {
            return
        }
        
        renderEncoder.pushDebugGroup("DrawTrackedImageRectangles")
        
        // Set render states
        renderEncoder.setRenderPipelineState(rectanglePipelineState)
        renderEncoder.setDepthStencilState(depthState)
        renderEncoder.setCullMode(.none)
        
        // Set shared uniform buffer (index 2 as per ShaderTypes.h)
        renderEncoder.setVertexBuffer(uniformBuffer, offset: uniformBufferOffset, index: 2)

        // Draw rectangle for each tracked image
        for (_, trackedImage) in trackedImages {
            guard trackedImage.isTracking else { continue }
            
            // Set rectangle vertices as base geometry (index 0)
            renderEncoder.setVertexBuffer(rectVertexBuffer, offset: 0, index: 0)

            // Create model matrix from image transform, size, and scale
            var modelMatrix = trackedImage.transform
            // Scale to physical size of the image
            let width = Float(trackedImage.physicalSize.width)
            let height = Float(trackedImage.physicalSize.height)
            
            // Add slight offset to prevent z-fighting (move 1mm above the image)
            let zOffset: Float = 0.001
            

            // Flip Z axis to convert from right-handed to left-handed coords
            var coordinateSpaceTransform = matrix_identity_float4x4
            coordinateSpaceTransform.columns.2.z = -1.0
            
            let angleX = -Float.pi / 2
            let rotationMatrix = simd_float4x4(
                SIMD4<Float>(1, 0, 0, 0),
                SIMD4<Float>(0, cos(angleX), sin(angleX), 0),
                SIMD4<Float>(0, -sin(angleX), cos(angleX), 0),
                SIMD4<Float>(0, 0, 0, 1)
            )
            
            
            modelMatrix = simd_mul(simd_mul(modelMatrix, rotationMatrix), coordinateSpaceTransform)

            // Apply scale and z-offset
            var scaleMatrix = matrix_identity_float4x4
            scaleMatrix.columns.0.x = width * trackedImage.scale
            scaleMatrix.columns.1.y = height * trackedImage.scale
            scaleMatrix.columns.2.z = 1.0
            scaleMatrix.columns.3.z = zOffset // Move slightly above the image
            
            modelMatrix = matrix_multiply(modelMatrix, scaleMatrix)
            
            // Create instance uniforms structure for the model matrix
            var instanceUniforms = InstanceUniforms(modelMatrix: modelMatrix)
            
            // Set instance uniforms (index 3)
            renderEncoder.setVertexBytes(&instanceUniforms,
                                      length: MemoryLayout<simd_float4x4>.size,
                                      index: 3)
            
            // Set color (index 1)
            var color = trackedImage.color
            renderEncoder.setVertexBytes(&color,
                                      length: MemoryLayout<SIMD4<Float>>.size,
                                      index: 1)
            
            // Draw rectangle outline
            renderEncoder.drawIndexedPrimitives(
                type: .triangle,           // Changed from .line to .triangle
                indexCount: 6,             // 6 indices for 2 triangles
                indexType: .uint16,
                indexBuffer: rectIndexBuffer,
                indexBufferOffset: 0
            )
        }
        
        renderEncoder.popDebugGroup()
    }
}
