//
//  Uniforms.swift
//  lagTestARKIT
//
//  Created by Vishwas Prakash on 21/04/25.
//

import Foundation
import Metal
import MetalKit
import ARKit

/// Shared uniform structure containing transformation matrices and lighting data
struct SharedUniforms {
    // Camera matrices
    var viewMatrix: simd_float4x4
    var projectionMatrix: simd_float4x4
    
    // Lighting properties
    var ambientLightColor: simd_float3
    var directionalLightDirection: simd_float3
    var directionalLightColor: simd_float3
    var materialShininess: Float
    
    // Extra parameters for special effects
    var time: Float = 0.0
    var pad: (Float, Float, Float) = (0, 0, 0)
}

/// Instance uniform structure for per-instance (anchor) transforms
struct InstanceUniforms {
    var modelMatrix: simd_float4x4
}

/// Layer uniform structure for parallax layers
struct LayerUniforms {
    var transform: simd_float4x4
    var scale: Float
    var depth: Float
    var mode: Int32
    var pad: Float = 0
}

/// Vertex structure for general use
struct Vertex {
    var position: simd_float3
    var texCoord: simd_float2
    var textureIndex: UInt32
    
    init(position: simd_float3, texCoord: simd_float2, textureIndex: UInt32 = 0) {
        self.position = position
        self.texCoord = texCoord
        self.textureIndex = textureIndex
    }
}

/// Vector utility functions
func vector3(_ x: Float, _ y: Float, _ z: Float) -> simd_float3 {
    return simd_float3(x, y, z)
}
