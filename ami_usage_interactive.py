#!/usr/bin/env python3

"""
AMI Usage Analysis (boto3, interactive)

What it does
------------
- Lists AMIs you own in a region
- Finds which AMIs are used by any non-terminated instances
- Prints:
    1) USED AMIs (with instances)
    2) UNUSED AMIs (no instances)
- Optional CSV export

Requirements
------------
- Python 3.8+
- boto3 1.28+  (installed inside a venv)

AWS permissions (read-only)
---------------------------
- ec2:DescribeImages
- ec2:DescribeInstances

Authentication
--------------
You must be logged into AWS CLI

Setup with venv
---------------
# one-time per project
cd /path/to/dir/that/contains/this/script
python3 -m venv .venv
. .venv/bin/activate
pip install --upgrade pip
pip install boto3

Run
---
# after AWS CLI login
cd /path/to/dir/that/contains/this/script
. .venv/bin/activate               # skip this if already active
python ami_usage_interactive.py    # will prompt for region/profile/CSV

Deactivate venv
---------------
Just run `deactivate`

Re-using later
--------------
You do not need to recreate the venv. Next time in a new shell:
cd /path/to/dir/that/contains/this/script
. .venv/bin/activate
python ami_usage_interactive.py

Notes
-----
- Instances in states {'terminated','shutting-down'} are ignored
- AMIs are sorted by creation date ascending
- Exit codes: 0 success, 2 AWS error, 130 interrupted
"""

from __future__ import annotations
import csv
import sys
from collections import defaultdict
from typing import Dict, List, Tuple, Optional

try:
    import boto3
    from botocore.exceptions import BotoCoreError, ClientError
except ModuleNotFoundError:
    print(f"boto3 not found for interpreter:\n  {sys.executable}\nInstall with:\n  {sys.executable} -m pip install boto3", file=sys.stderr)
    raise

# === Types ===

InstanceInfo = Tuple[str, str, str]  # (instance_id, instance_name, state)
AmiInfo = Tuple[str, str, str]       # (image_id, name, creation_date)

# === Helpers ===

def get_session(profile: Optional[str] = None, region: Optional[str] = None):
    """
    Create a boto3 session. Respects AWS_* env vars and shared config/credentials.
    """
    if profile:
        return boto3.Session(profile_name=profile, region_name=region)
    return boto3.Session(region_name=region)

def fetch_owned_amis(session, region: str) -> List[AmiInfo]:
    """
    Return all AMIs owned by the caller in the given region.
    Sorted by CreationDate ascending.
    """
    ec2 = session.client('ec2', region_name=region)
    paginator = ec2.get_paginator('describe_images')
    images: List[AmiInfo] = []
    for page in paginator.paginate(Owners=['self']):
        for img in page.get('Images', []):
            image_id = img.get('ImageId', '-')
            name = img.get('Name') or '-'
            date = img.get('CreationDate') or '-'
            images.append((image_id, name, date))
    images.sort(key=lambda x: x[2])  # by creation date (asc)
    return images

def fetch_instances(session, region: str) -> Dict[str, List[InstanceInfo]]:
    """
    Map image_id -> list of instances using that AMI.
    Excludes states {'terminated','shutting-down'}.
    """
    ec2 = session.client('ec2', region_name=region)
    paginator = ec2.get_paginator('describe_instances')
    mapping: Dict[str, List[InstanceInfo]] = defaultdict(list)
    excluded_states = {'terminated', 'shutting-down'}
    for page in paginator.paginate():
        for res in page.get('Reservations', []):
            for inst in res.get('Instances', []):
                state = (inst.get('State') or {}).get('Name', '-')
                if state in excluded_states:
                    continue
                image_id = inst.get('ImageId')
                if not image_id:
                    continue
                instance_id = inst.get('InstanceId', '-')
                # extract Name tag if present
                name = '-'
                for t in inst.get('Tags', []) or []:
                    if t.get('Key') == 'Name' and t.get('Value'):
                        name = t['Value']
                        break
                mapping[image_id].append((instance_id, name, state))
    return mapping

def compute_widths(rows: List[Tuple[str, str, str]], mins=(22, 40, 24)) -> Tuple[int, int, int]:
    """
    Compute column widths for aligned output with sensible minimums.
    """
    w1, w2, w3 = mins
    for a, b, c in rows:
        w1 = max(w1, len(str(a)))
        w2 = max(w2, len(str(b)))
        w3 = max(w3, len(str(c)))
    return w1, w2, w3

def print_used(amis: List[AmiInfo], usage: Dict[str, List[InstanceInfo]]):
    """
    Print AMIs that are referenced by any non-terminated instance.
    """
    print("\n1. USED AMIs (with instances):")
    print("================================")
    any_used = False
    for image_id, name, date in amis:
        if image_id in usage:
            any_used = True
            print(f"\nAMI: {image_id} - {name} (Created: {date})")
            for inst_id, inst_name, state in sorted(usage[image_id], key=lambda x: x[0]):
                print(f"  - {inst_id} ({inst_name}) - {state}")
    if not any_used:
        print("(none)")

def print_unused(amis: List[AmiInfo], usage: Dict[str, List[InstanceInfo]]):
    """
    Print AMIs that have zero referencing instances.
    """
    print("\n\n2. UNUSED AMIs (no instances):")
    print("================================")
    unused = [(i, n, d) for (i, n, d) in amis if i not in usage]
    if not unused:
        print("(none)")
        return
    w1, w2, w3 = compute_widths(unused, mins=(22, 40, 24))
    hdr = f"{'AMI ID'.ljust(w1)} {'AMI Name'.ljust(w2)} {'Creation Date'.ljust(w3)}"
    print(hdr)
    print("-" * len(hdr))
    for i, n, d in unused:
        print(f"{i.ljust(w1)} {n.ljust(w2)} {d.ljust(w3)}")

def maybe_write_csv(path: Optional[str], amis: List[AmiInfo], usage: Dict[str, List[InstanceInfo]]):
    """
    If a CSV path is provided, write a flat report of USED and UNUSED AMIs.
    """
    if not path:
        return
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["section", "ami_id", "ami_name", "creation_date", "instance_id", "instance_name", "state"])
        for image_id, name, date in amis:
            if image_id in usage:
                for inst_id, inst_name, state in usage[image_id]:
                    writer.writerow(["USED", image_id, name, date, inst_id, inst_name, state])
            else:
                writer.writerow(["UNUSED", image_id, name, date, "", "", ""])
    print(f"\nCSV written to: {path}")

# === Interactive main ===

def prompt_nonempty(prompt_text: str) -> str:
    """
    Prompt until a non-empty string is entered.
    """
    while True:
        val = input(prompt_text).strip()
        if val:
            return val
        print("Please enter a value.")

def main():
    print("=== AMI Usage Analysis (interactive) ===\n")
    region = prompt_nonempty("Enter AWS region (e.g., eu-west-1): ")
    profile = input("Enter AWS profile name (press Enter to use default creds): ").strip() or None
    csv_path = input("CSV output path (press Enter to skip): ").strip() or None
    try:
        session = get_session(profile=profile, region=region)
        amis = fetch_owned_amis(session, region)
        usage = fetch_instances(session, region)
        print(f"\n=== AMI Usage Analysis (region: {region}) ===")
        print_used(amis, usage)
        print_unused(amis, usage)
        maybe_write_csv(csv_path, amis, usage)
    except (BotoCoreError, ClientError) as e:
        print(f"AWS error: {e}", file=sys.stderr)
        sys.exit(2)
    except KeyboardInterrupt:
        print("\nInterrupted.", file=sys.stderr)
        sys.exit(130)

if __name__ == "__main__":
    main()
