use std::path::PathBuf;

fn main() {
    let bridge_files = ["src/lib.rs"];

    for bridge_file in bridge_files {
        println!("cargo:rerun-if-changed={bridge_file}");
    }

    let generated_directory = PathBuf::from("../Swiftify/Swiftify/Generated");
    std::fs::create_dir_all(&generated_directory)
        .expect("failed to create the swift-bridge output directory");

    swift_bridge_build::parse_bridges(bridge_files)
        .write_all_concatenated(generated_directory, env!("CARGO_PKG_NAME"));
}
