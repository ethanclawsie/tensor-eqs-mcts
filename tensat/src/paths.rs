use std::env;
use std::path::PathBuf;

pub fn repo_root() -> PathBuf {
    env::var_os("TENSOR_EQS_MCTS_ROOT")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(env!("CARGO_MANIFEST_DIR")).join(".."))
}

pub fn tensat_dir() -> PathBuf {
    repo_root().join("tensat")
}

pub fn experiments_dir() -> PathBuf {
    repo_root().join("experiments")
}

pub fn tensat_file(relative_path: &str) -> String {
    tensat_dir()
        .join(relative_path)
        .to_string_lossy()
        .into_owned()
}
