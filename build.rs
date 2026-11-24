fn main() {
    println!("cargo:rerun-if-env-changed=GITS_VERSION");

    // Version comes only from GITS_VERSION (release workflow sets it to the pushed tag).
    // Everything else is "dev", and a "dev" build refuses to --update.
    let version = match std::env::var("GITS_VERSION") {
        Ok(val) if !val.trim().is_empty() => val.trim().to_string(),
        _ => "dev".to_string(),
    };

    println!("cargo:rustc-env=GITS_BUILD_VERSION={version}");
}
