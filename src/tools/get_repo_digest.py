"""GitHub repository digest tool for the Azure Functions serverless agents runtime.

Returns recent public GitHub activity (pull requests, issues, and workflow runs) for a
repository. Set the ``GITHUB_TOKEN`` app setting for higher GitHub API rate limits.
"""
from datetime import UTC, datetime, timedelta
import json
import os
from urllib.error import HTTPError
from urllib.parse import quote
from urllib.request import Request, urlopen

from pydantic import BaseModel, Field

DEFAULT_DIGEST_REPO = os.environ.get("GITHUB_REPOSITORY") or "Azure/azure-functions-host"
GITHUB_API = "https://api.github.com"


class RepoDigestParams(BaseModel):
    repository: str = Field(
        default=DEFAULT_DIGEST_REPO,
        description=(
            "GitHub repository in owner/name format. Defaults to the GITHUB_REPOSITORY "
            "app setting, or Azure/azure-functions-host when unset."
        ),
    )
    hours: int = Field(
        default=24,
        description="Number of hours of repository activity to include.",
    )


def get_repo_digest(params: RepoDigestParams) -> str:
    """Return recent public GitHub activity (PRs, issues, workflow runs) for a repository."""

    def _github_get(path: str) -> dict:
        headers = {
            "Accept": "application/vnd.github+json",
            "User-Agent": "simple-agent-functions-python",
            "X-GitHub-Api-Version": "2022-11-28",
        }
        token = os.environ.get("GITHUB_TOKEN")
        if token:
            headers["Authorization"] = f"Bearer {token}"

        request = Request(f"{GITHUB_API}{path}", headers=headers)
        try:
            with urlopen(request, timeout=20) as response:
                return json.loads(response.read().decode("utf-8"))
        except HTTPError as exc:
            detail = exc.read().decode("utf-8", errors="replace")
            raise RuntimeError(f"GitHub API request failed with {exc.code}: {detail}") from exc

    repo = params.repository.strip() or DEFAULT_DIGEST_REPO
    hours = params.hours
    since = datetime.now(UTC) - timedelta(hours=hours)
    since_iso = since.isoformat(timespec="seconds").replace("+00:00", "Z")
    encoded_repo = quote(repo, safe="/")

    pulls = _github_get(
        f"/repos/{encoded_repo}/pulls?state=all&sort=updated&direction=desc&per_page=30"
    )
    issues = _github_get(
        f"/repos/{encoded_repo}/issues?state=all&since={quote(since_iso)}&per_page=30"
    )
    runs = _github_get(
        f"/repos/{encoded_repo}/actions/runs?created=>={quote(since_iso)}&per_page=20"
    )

    merged_prs = [
        f"#{pr['number']} {pr['title']} by {pr['user']['login']}"
        for pr in pulls
        if pr.get("merged_at") and pr["merged_at"] >= since_iso
    ][:10]
    open_prs = [
        f"#{pr['number']} {pr['title']} by {pr['user']['login']} (updated {pr['updated_at']})"
        for pr in pulls
        if pr.get("state") == "open"
    ][:10]
    new_issues = [
        f"#{issue['number']} {issue['title']} by {issue['user']['login']}"
        for issue in issues
        if "pull_request" not in issue
        and issue["state"] == "open"
        and issue["created_at"] >= since_iso
    ][:10]
    closed_issues = [
        f"#{issue['number']} {issue['title']}"
        for issue in issues
        if "pull_request" not in issue
        and issue["state"] == "closed"
        and (issue.get("closed_at") or "") >= since_iso
    ][:10]
    failing_runs = [
        f"{run['name']} on {run['head_branch']} ({run['conclusion'] or run['status']})"
        for run in runs.get("workflow_runs", [])
        if run.get("conclusion") in {"failure", "timed_out", "cancelled", "action_required"}
    ][:10]

    return json.dumps(
        {
            "repo": repo,
            "window": f"last {hours} hours",
            "merged_prs": merged_prs,
            "open_prs_needing_attention": open_prs,
            "new_issues": new_issues,
            "closed_issues": closed_issues,
            "failing_workflow_runs": failing_runs,
        },
        indent=2,
    )
