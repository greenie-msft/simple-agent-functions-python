---
name: Daily Repo Digest Agent
description: Creates a daily GitHub repository digest on a timer and writes it to the function logs.

trigger:
  type: timer_trigger
  args:
    # 16:00 UTC daily = 9 AM Pacific Daylight Time (8 AM during Pacific Standard Time).
    # Linux Flex Consumption does not support WEBSITE_TIME_ZONE/TZ, so the schedule is UTC.
    schedule: "0 0 16 * * *"
---

Once a day, create a concise digest of recent activity for the `$GITHUB_REPOSITORY` repository. If that value is empty, use `Azure/azure-functions-host`.

Call the `get_repo_digest` tool for the last 24 hours, then summarize:

- Merged pull requests
- Open pull requests needing attention
- New issues
- Closed issues
- Failing workflow runs

Write it like a short, skimmable update to a teammate: start with the main themes you noticed, then list the items with their numbers and titles. Keep it action-oriented. Return the finished digest so it is captured in the function logs.
