"""Keep one clean Git revision attached to every stage of local release preparation."""
import subprocess


def git(root, *arguments):
    return subprocess.check_output(["git", *arguments], cwd=root, text=True).strip()


def verify_source(root, commit):
    if git(root, "rev-parse", "HEAD") != commit or git(root, "status", "--porcelain"):
        raise ValueError("Source changed during beta preparation. Commit changes and restart with a new build number.")


def capture_source(root):
    commit = git(root, "rev-parse", "HEAD")
    if git(root, "status", "--porcelain"):
        raise ValueError("Commit source changes before preparing a beta so provenance is reproducible.")
    verify_source(root, commit)
    return commit
