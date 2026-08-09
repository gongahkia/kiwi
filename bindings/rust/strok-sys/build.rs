use std::env;
use std::path::{Path, PathBuf};

fn environment_path(name: &str) -> Option<PathBuf> {
    env::var_os(name).map(PathBuf::from)
}

fn existing_directory(candidates: impl IntoIterator<Item = PathBuf>, purpose: &str) -> PathBuf {
    candidates
        .into_iter()
        .find(|path| path.is_dir())
        .unwrap_or_else(|| {
            panic!(
                "could not find {purpose}; set STROK_PREFIX or STROK_INCLUDE_DIR/STROK_LIBRARY_DIR"
            )
        })
}

fn repository_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .ancestors()
        .nth(3)
        .expect("strok-sys must remain under bindings/rust")
        .to_path_buf()
}

fn main() {
    println!("cargo:rerun-if-env-changed=STROK_PREFIX");
    println!("cargo:rerun-if-env-changed=STROK_INCLUDE_DIR");
    println!("cargo:rerun-if-env-changed=STROK_LIBRARY_DIR");
    println!("cargo:rerun-if-env-changed=STROK_BUILD_DIR");

    let root = repository_root();
    let prefix = environment_path("STROK_PREFIX");
    let include_dir = environment_path("STROK_INCLUDE_DIR").unwrap_or_else(|| {
        prefix
            .as_ref()
            .map(|path| path.join("include"))
            .unwrap_or_else(|| root.join("include"))
    });
    let library_dir = environment_path("STROK_LIBRARY_DIR").unwrap_or_else(|| {
        if let Some(prefix) = prefix.as_ref() {
            existing_directory(
                [prefix.join("lib"), prefix.join("lib64")],
                "installed strok C ABI library",
            )
        } else if let Some(build_dir) = environment_path("STROK_BUILD_DIR") {
            build_dir
        } else {
            existing_directory(
                [root.join("build/core"), root.join("build/full-temp")],
                "development strok C ABI build directory",
            )
        }
    });
    let header = include_dir.join("strok/c_api.h");
    if !header.is_file() {
        panic!("could not find {}", header.display());
    }
    if !library_dir.is_dir() {
        panic!("could not find {}", library_dir.display());
    }

    println!("cargo:rerun-if-changed={}", header.display());
    println!("cargo:rustc-link-search=native={}", library_dir.display());
    println!("cargo:rustc-link-lib=dylib=strok_c_api");
    #[cfg(target_family = "unix")]
    println!("cargo:rustc-link-arg=-Wl,-rpath,{}", library_dir.display());

    let bindings = bindgen::Builder::default()
        .header(header.to_string_lossy())
        .clang_arg(format!("-I{}", include_dir.display()))
        .clang_arg("-x")
        .clang_arg("c")
        .clang_arg("-std=c11")
        .allowlist_type("Strok.*")
        .allowlist_function("strok_.*")
        .allowlist_var("STROK_.*")
        .generate_comments(false)
        .layout_tests(true)
        .parse_callbacks(Box::new(bindgen::CargoCallbacks::new()))
        .generate()
        .expect("could not generate strok C ABI bindings");
    bindings
        .write_to_file(
            PathBuf::from(env::var_os("OUT_DIR").expect("missing OUT_DIR")).join("bindings.rs"),
        )
        .expect("could not write generated strok C ABI bindings");
}
