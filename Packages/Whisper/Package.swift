// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Whisper",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "whisper", targets: ["whisper"])
    ],
    targets: [
        .target(
            name: "whisper",
            path: "Sources/whisper",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("."),
                .define("GGML_USE_ACCELERATE"),
                .define("ACCELERATE_NEW_LAPACK"),
                .define("ACCELERATE_LAPACK_ILP64")
            ],
            cxxSettings: [
                .headerSearchPath("."),
                .define("GGML_USE_ACCELERATE")
            ],
            linkerSettings: [
                .linkedFramework("Accelerate")
            ]
        )
    ],
    cxxLanguageStandard: .cxx17
)
