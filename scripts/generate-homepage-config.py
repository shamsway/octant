#!/usr/bin/env python3
"""Generate Homepage dashboard config from Nomad service tags.

Queries the Nomad API for running jobs, reads homepage.* tags from service
definitions, and writes services.yaml and settings.yaml in Homepage format.

Usage:
    python3 scripts/generate-homepage-config.py [--nomad-addr URL] [--output-dir DIR] [--dry-run]
"""

import argparse
import json
import re
import sys
import urllib.error
import urllib.request
from collections import defaultdict

try:
    import yaml
except ImportError:
    sys.exit("PyYAML required: pip install pyyaml")


# ---------------------------------------------------------------------------
# Static entries for services that don't appear as Nomad service registrations
# ---------------------------------------------------------------------------
STATIC_ENTRIES = [
    {
        "group": "Observability",
        "name": "Alloy",
        "icon": "grafana",
        "description": "Telemetry Collector",
    },
]


# ---------------------------------------------------------------------------
# Nomad API helpers
# ---------------------------------------------------------------------------


def nomad_get(nomad_addr: str, path: str) -> object:
    """Perform a GET request against the Nomad API and return parsed JSON."""
    url = f"{nomad_addr.rstrip('/')}{path}"
    req = urllib.request.Request(url, headers={"Accept": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.URLError as exc:
        raise RuntimeError(f"Nomad API unreachable at {url}: {exc}") from exc


def list_running_jobs(nomad_addr: str) -> list:
    """Return all job summaries whose Status is 'running'."""
    jobs = nomad_get(nomad_addr, "/v1/jobs")
    return [j for j in jobs if j.get("Status") == "running"]


def get_job(nomad_addr: str, job_id: str) -> dict:
    """Return the full spec for a single job."""
    return nomad_get(nomad_addr, f"/v1/job/{job_id}")


# ---------------------------------------------------------------------------
# Tag parsing
# ---------------------------------------------------------------------------


def parse_homepage_tags(tags: list) -> dict:
    """Extract homepage.key=value pairs from a list of service tags.

    Returns a dict of {key: value} for tags that start with 'homepage.'.
    """
    result = {}
    for tag in tags:
        if not tag.startswith("homepage."):
            continue
        # Strip the "homepage." prefix then split on the first '='
        remainder = tag[len("homepage.") :]
        if "=" in remainder:
            key, _, value = remainder.partition("=")
            result[key.strip()] = value.strip()
        else:
            # Boolean-style flag with no value — treat as "true"
            result[remainder.strip()] = "true"
    return result


def extract_traefik_href(tags: list) -> str | None:
    """Try to derive an href from Traefik Host(...) router rules in tags.

    Looks for tags of the form:
        traefik.http.routers.<name>.rule=Host(`example.com`)

    Returns 'https://example.com' on the first match, or None.
    """
    host_rule_re = re.compile(
        r"^traefik\.http\.routers\.[^=]+=Host\(`([^`]+)`\)$",
        re.IGNORECASE,
    )
    for tag in tags:
        m = host_rule_re.match(tag)
        if m:
            return f"https://{m.group(1)}"
    return None


# ---------------------------------------------------------------------------
# Service collection
# ---------------------------------------------------------------------------


def collect_services_from_nomad(nomad_addr: str) -> list:
    """Query Nomad and return a list of service entry dicts.

    Each entry has keys: group, name, icon, href (optional), description (optional),
    weight (int).
    """
    try:
        running_jobs = list_running_jobs(nomad_addr)
    except RuntimeError as exc:
        sys.exit(f"Error: {exc}")

    entries = []

    for job_summary in running_jobs:
        job_id = job_summary.get("ID") or job_summary.get("Name")
        try:
            job = get_job(nomad_addr, job_id)
        except RuntimeError as exc:
            print(f"Warning: could not inspect job '{job_id}': {exc}", file=sys.stderr)
            continue

        task_groups = job.get("TaskGroups") or []
        for tg in task_groups:
            services = tg.get("Services") or []
            for svc in services:
                tags = svc.get("Tags") or []
                hp = parse_homepage_tags(tags)

                # Skip services with no homepage.group
                if "group" not in hp:
                    continue

                # Skip explicitly disabled services
                if hp.get("enabled", "true").lower() == "false":
                    continue

                # Resolve href: explicit tag wins, then Traefik derivation
                href = hp.get("href") or extract_traefik_href(tags)

                entry = {
                    "group": hp["group"],
                    "name": hp.get("name", svc.get("Name", job_id)),
                    "weight": _parse_weight(hp.get("weight", "50")),
                }
                if "icon" in hp:
                    entry["icon"] = hp["icon"]
                if href:
                    entry["href"] = href
                if "description" in hp:
                    entry["description"] = hp["description"]

                entries.append(entry)

    return entries


def _parse_weight(raw: str) -> int:
    """Parse a weight string into an integer, defaulting to 50 on failure."""
    try:
        return int(raw)
    except (ValueError, TypeError):
        return 50


# ---------------------------------------------------------------------------
# YAML generation
# ---------------------------------------------------------------------------


def build_services_yaml(entries: list) -> list:
    """Build the services.yaml data structure (list of single-key dicts)."""
    # Group entries
    grouped: dict[str, list] = defaultdict(list)
    for entry in entries:
        grouped[entry["group"]].append(entry)

    # Sort groups by the minimum weight of their members, then alphabetically
    sorted_groups = sorted(
        grouped.keys(),
        key=lambda g: (min(e["weight"] for e in grouped[g]), g),
    )

    services_list = []
    for group in sorted_groups:
        members = grouped[group]
        # Sort members: by weight ascending, then name alphabetically
        members_sorted = sorted(members, key=lambda e: (e["weight"], e["name"].lower()))

        service_entries = []
        for svc in members_sorted:
            props = {}
            if "icon" in svc:
                props["icon"] = svc["icon"]
            if "href" in svc:
                props["href"] = svc["href"]
            if "description" in svc:
                props["description"] = svc["description"]
            service_entries.append({svc["name"]: props})

        services_list.append({group: service_entries})

    return services_list


def build_settings_yaml(entries: list) -> dict:
    """Build the settings.yaml data structure."""
    grouped: dict[str, list] = defaultdict(list)
    for entry in entries:
        grouped[entry["group"]].append(entry)

    sorted_groups = sorted(
        grouped.keys(),
        key=lambda g: (min(e["weight"] for e in grouped[g]), g),
    )

    layout = {}
    for group in sorted_groups:
        count = len(grouped[group])
        columns = min(max(count, 2), 5)
        layout[group] = {"style": "column", "columns": columns}

    return {
        "title": "Octant Lab",
        "favicon": "https://cdn.jsdelivr.net/gh/walkxcode/dashboard-icons/png/server.png",
        "theme": "dark",
        "color": "slate",
        "layout": layout,
    }


def render_yaml(data: object) -> str:
    """Render data to YAML string with Homepage-compatible settings."""
    return "---\n" + yaml.dump(
        data,
        default_flow_style=False,
        allow_unicode=True,
        sort_keys=False,
    )


# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------


def write_file(path: str, content: str) -> None:
    """Write content to path, creating parent directories as needed."""
    import os

    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(content)
    print(f"Wrote {path}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate Homepage dashboard config from Nomad service tags.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--nomad-addr",
        metavar="URL",
        default="http://localhost:4646",
        help="Nomad API address (default: http://localhost:4646)",
    )
    parser.add_argument(
        "--output-dir",
        metavar="DIR",
        default="/mnt/services/homepage/config",
        help="Output directory (default: /mnt/services/homepage/config)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print generated YAML to stdout, don't write files",
    )
    args = parser.parse_args()

    # Collect entries from Nomad
    dynamic_entries = collect_services_from_nomad(args.nomad_addr)

    # Merge static entries (deduplicated by group+name)
    existing_keys = {(e["group"], e["name"]) for e in dynamic_entries}
    static_merged = []
    for se in STATIC_ENTRIES:
        key = (se["group"], se["name"])
        if key not in existing_keys:
            # Normalise static entries to match the internal schema
            static_merged.append(
                {
                    "group": se["group"],
                    "name": se["name"],
                    "weight": se.get("weight", 50),
                    **{
                        k: v
                        for k, v in se.items()
                        if k not in ("group", "name", "weight")
                    },
                }
            )

    all_entries = dynamic_entries + static_merged

    if not all_entries:
        sys.exit(
            "Error: zero services collected (dynamic + static). "
            "This likely indicates a misconfiguration or an empty cluster."
        )

    services_data = build_services_yaml(all_entries)
    settings_data = build_settings_yaml(all_entries)

    services_yaml = render_yaml(services_data)
    settings_yaml = render_yaml(settings_data)

    if args.dry_run:
        print("=== services.yaml ===")
        print(services_yaml)
        print("=== settings.yaml ===")
        print(settings_yaml)
        return

    write_file(f"{args.output_dir}/services.yaml", services_yaml)
    write_file(f"{args.output_dir}/settings.yaml", settings_yaml)


if __name__ == "__main__":
    main()
