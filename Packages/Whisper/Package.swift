// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Whisper",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "whisper", targets: ["whisper", "whisper_metal"])
    ],
    targets: [
        // Objective-C target: ggml-metal.m + ggml-metal.metal as resource.
        // Изолирован от whisper-таргета, чтобы автогенеренный
        // resource_bundle_accessor (включающий Foundation) не подмешивался
        // в C/C++ исходники whisper.cpp.
        .target(
            name: "whisper_metal",
            path: "Sources/whisper_metal",
            resources: [
                .process("ggml-metal.metal")
            ],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("../whisper"),
                .headerSearchPath("../whisper/include"),
                .define("GGML_USE_METAL"),
                .unsafeFlags(["-fno-objc-arc"])
            ],
            linkerSettings: [
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("Foundation"),
                .linkedFramework("CoreGraphics")
            ]
        ),
        .target(
            name: "whisper",
            dependencies: ["whisper_metal"],
            path: "Sources/whisper",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("."),
                .headerSearchPath("../whisper_metal/include"),
                .define("GGML_USE_ACCELERATE"),
                .define("ACCELERATE_NEW_LAPACK"),
                .define("ACCELERATE_LAPACK_ILP64"),
                .define("GGML_USE_METAL")
            ],
            cxxSettings: [
                .headerSearchPath("."),
                .headerSearchPath("../whisper_metal/include"),
                .define("GGML_USE_ACCELERATE"),
                .define("GGML_USE_METAL")
            ],
            linkerSettings: [
                .linkedFramework("Accelerate")
            ]
        )
    ],
    cxxLanguageStandard: .cxx17
)
