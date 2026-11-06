use std::{
    process::{Command, Stdio},
    time::{Duration, Instant},
};

#[test]
fn pipe_holder_helper() {
    if std::env::var_os("FILEBACKUP_PIPE_HOLDER").is_some() {
        std::thread::sleep(Duration::from_secs(20));
    }
}
#[test]
#[allow(clippy::zombie_processes)] // Intentionally orphan a pipe holder; ToolChild must kill its group/job.
fn pipe_parent_helper() {
    if std::env::var_os("FILEBACKUP_PIPE_PARENT").is_some() {
        // Deliberately keep inherited stdout open after this direct child exits.
        let _child = Command::new(std::env::current_exe().unwrap())
            .args(["--exact", "pipe_holder_helper", "--nocapture"])
            .env_remove("FILEBACKUP_PIPE_PARENT")
            .env("FILEBACKUP_PIPE_HOLDER", "1")
            .stdin(Stdio::null())
            .stdout(Stdio::inherit())
            .stderr(Stdio::null())
            .spawn()
            .unwrap();
    }
}
#[test]
fn inherited_output_pipe_cannot_extend_tool_deadline() {
    let start = Instant::now();
    let error = filebackup::tools::output(
        Command::new(std::env::current_exe().unwrap())
            .args(["--exact", "pipe_parent_helper", "--nocapture"])
            .env("FILEBACKUP_PIPE_PARENT", "1"),
        4096,
        Duration::from_millis(500),
    )
    .unwrap_err();
    assert!(filebackup::platform::is_host_stop(&error), "{error:#}");
    assert!(start.elapsed() < Duration::from_secs(5));
}
