#!/usr/bin/env python3
"""Convert lab-state.json to a formatted markdown report.

Usage:
    python3 scripts/state-to-markdown.py docs/state/lab-state.json docs/state/lab-state.md
"""

import json
import sys
from pathlib import Path


def md_table_row(cells):
    """Format a list of cell strings as a markdown table row."""
    return "| " + " | ".join(str(c) for c in cells) + " |"


def col_widths(headers, rows):
    """Compute minimum column widths from headers and data rows."""
    widths = [len(h) for h in headers]
    for row in rows:
        for i, cell in enumerate(row):
            widths[i] = max(widths[i], len(str(cell)))
    return widths


def render_table(headers, rows):
    """Render a markdown table from headers and rows, returning a list of lines."""
    widths = col_widths(headers, rows)
    lines = []
    lines.append(md_table_row(h.ljust(widths[i]) for i, h in enumerate(headers)))
    lines.append("|" + "|".join(["-" * (w + 2) for w in widths]) + "|")
    for row in rows:
        lines.append(
            md_table_row(str(row[i]).ljust(widths[i]) for i in range(len(headers)))
        )
    return lines


def detect_drift(live_img, intended_dict):
    """
    Compare live_img against all defaults in intended_dict (a dict of var_name -> image_default).

    Returns:
        ("ok", ...)      if live_img matches any default
        ("DRIFT", ...)   if live_img matches none and comparison is possible
        ("—", ...)       if comparison is not possible (missing live or intended)
    """
    if not intended_dict:
        return "—"
    if not live_img or live_img in ("—", "unknown"):
        return "—"
    defaults = list(intended_dict.values())
    if live_img in defaults:
        return "ok"
    return "DRIFT"


def format_intended(intended_dict):
    """Format the intended images dict into a display string."""
    if not intended_dict:
        return "—"
    return ", ".join(sorted(intended_dict.values()))


def format_uptime(seconds):
    """Convert uptime in seconds to a human-readable string like '2d 4h'.

    Handles missing values (None, '—') and non-integer inputs gracefully.
    """
    if seconds is None or seconds == "—":
        return "—"
    try:
        seconds = int(seconds)
    except (ValueError, TypeError):
        return "—"
    days, remainder = divmod(seconds, 86400)
    hours, _ = divmod(remainder, 3600)
    if days > 0:
        return f"{days}d {hours}h"
    return f"{hours}h"


def section_cluster(state, lines):
    """Render the Cluster overview table."""
    lines.append("## Cluster")
    lines.append("")

    cluster = state.get("cluster", {})
    headers = ["Component", "Version", "Health / Status"]
    rows = []

    if "consul" in cluster:
        c = cluster["consul"]
        members = c.get("members", [])
        member_str = (
            f"{len(members)} members: {', '.join(members)}" if members else "no members"
        )
        rows.append(["Consul", c.get("version", "—"), member_str])

    if "nomad" in cluster:
        n = cluster["nomad"]
        members = n.get("members", [])
        member_str = (
            f"{len(members)} members: {', '.join(members)}" if members else "no members"
        )
        rows.append(["Nomad", n.get("version", "—"), member_str])

    if "ceph" in cluster:
        ce = cluster["ceph"]
        version_str = ce.get("version", "—")
        codename = ce.get("codename", "")
        if codename:
            version_str = f"{version_str} ({codename})"
        pools = ce.get("pools", [])
        pool_str = f", {len(pools)} pools" if pools else ""
        health_str = f"{ce.get('health', '—')}, {ce.get('osds', '?')} OSDs{pool_str}"
        rows.append(["Ceph", version_str, health_str])

    if rows:
        lines.extend(render_table(headers, rows))
    else:
        lines.append("*No cluster data available.*")

    lines.append("")


def section_hosts(state, lines):
    """Render the Hosts section with three sub-tables."""
    hosts = state.get("hosts", {})
    if not hosts:
        lines.append("## Hosts")
        lines.append("")
        lines.append("*No host data available.*")
        lines.append("")
        return

    sorted_hosts = sorted(hosts.keys())
    lines.append("## Hosts")
    lines.append("")

    # --- Installed Packages ---
    lines.append("### Installed Packages")
    lines.append("")

    all_pkgs = set()
    for info in hosts.values():
        all_pkgs.update(info.get("packages", {}).keys())
    pkg_list = sorted(all_pkgs)

    if pkg_list:
        headers = ["Package"] + sorted_hosts
        rows = []
        for pkg in pkg_list:
            row = [pkg]
            for host in sorted_hosts:
                row.append(hosts[host].get("packages", {}).get(pkg, "—"))
            rows.append(row)
        lines.extend(render_table(headers, rows))
    else:
        lines.append("*No package data available.*")

    lines.append("")

    # --- Service States ---
    lines.append("### Service States")
    lines.append("")

    all_svcs = set()
    for info in hosts.values():
        all_svcs.update(info.get("services", {}).keys())
    svc_list = sorted(all_svcs)

    if svc_list:
        headers = ["Service"] + sorted_hosts
        rows = []
        for svc in svc_list:
            row = [svc]
            for host in sorted_hosts:
                row.append(hosts[host].get("services", {}).get(svc, "—"))
            rows.append(row)
        lines.extend(render_table(headers, rows))
    else:
        lines.append("*No service data available.*")

    lines.append("")

    # --- System Info ---
    lines.append("### System Info")
    lines.append("")

    headers = ["Host", "OS", "Kernel", "RAM (MB)", "vCPUs", "IP", "Uptime"]
    rows = []
    for host in sorted_hosts:
        info = hosts[host]
        rows.append(
            [
                host,
                info.get("os", "—"),
                info.get("kernel", "—"),
                info.get("ram_mb", "—"),
                info.get("vcpus", "—"),
                info.get("ip", "—"),
                format_uptime(info.get("uptime_seconds")),
            ]
        )
    lines.extend(render_table(headers, rows))
    lines.append("")


def section_jobs(state, lines):
    """Render the Deployed Jobs table with drift detection."""
    lines.append("## Deployed Jobs")
    lines.append("")

    jobs = state.get("jobs", {})
    intended = state.get("intended_images", {})

    # Merge job names from both sources
    all_job_names = sorted(set(list(jobs.keys()) + list(intended.keys())))

    if not all_job_names:
        lines.append("*No job data available.*")
        lines.append("")
        return

    headers = ["Job", "Status", "Type", "Node", "Live Image", "Intended Image", "Drift"]
    rows = []

    for job_name in all_job_names:
        job = jobs.get(job_name, {})
        status = job.get("status", "—")
        job_type = job.get("type", "—")
        node = job.get("node", "—")
        live_img = job.get("image_live", "—")

        # intended_images[job_name] is a dict of {var_name: image_default}
        intended_dict = intended.get(job_name, {})

        intended_display = format_intended(intended_dict)
        drift = detect_drift(live_img, intended_dict)

        rows.append(
            [job_name, status, job_type, node, live_img, intended_display, drift]
        )

    lines.extend(render_table(headers, rows))
    lines.append("")


def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <input.json> <output.md>", file=sys.stderr)
        sys.exit(1)

    input_path = Path(sys.argv[1])
    output_path = Path(sys.argv[2])

    if not input_path.exists():
        print(f"Error: input file not found: {input_path}", file=sys.stderr)
        sys.exit(1)

    with open(input_path) as f:
        state = json.load(f)

    lines = []

    # Header
    lines.append("# Octant Lab State")
    lines.append("")
    lines.append(f"**Captured:** {state.get('captured_at', 'unknown')}")
    lines.append("")

    # Cluster
    section_cluster(state, lines)

    # Hosts
    section_hosts(state, lines)

    # Deployed Jobs
    section_jobs(state, lines)

    # Footer
    lines.append("---")
    lines.append("")
    lines.append("*Generated by `make capture-state`*")
    lines.append("")

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text("\n".join(lines))
    print(f"Wrote {output_path}")


if __name__ == "__main__":
    main()
