// swift-tools-version: 5.7
import PackageDescription
let package = Package(
    name: "KindleDeskRendering",
    platforms: [.macOS(.v12)],
    products: [.executable(name: "KindleDeskRenderer", targets: ["KindleDeskRenderer"])],
    dependencies: [.package(url: "https://github.com/mgriebling/SwiftMath.git", revision: "1d2c90827e9c3908269d810d055fb03b7da5fd53")],
    targets: [.executableTarget(name: "KindleDeskRenderer", dependencies: ["SwiftMath"], path: "Renderer")]
)
