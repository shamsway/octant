import argparse
import os
import re
import sys
import urllib.parse

parser = argparse.ArgumentParser("iptv_filtering_script")
parser.add_argument("--m3u", help="A m3u file stored locally.", type=str, required=True)
parser.add_argument("--output-dir", help="Output directory.", type=str)
parser.add_argument("--output-file", help="Output file prefix.", type=str)
parser.add_argument("--regex", help="Groups to export in regex format. Case insensitive.", type=str)

args = parser.parse_args()
m3u_file = args.m3u
output_dir = args.output_dir
output_file_prefix = args.output_file
groups_regex = args.regex if args.regex else "."

def sanitize_filename(filename):
    """
    Sanitize the filename by removing spaces and replacing them with underscores.
    """
    return urllib.parse.quote(filename.replace(" ", "_"))

def process_m3u_file(file_path):
    """
    Process the m3u file and return a dictionary of groups and their corresponding content.
    """
    with open(file_path) as f:
        content = f.readlines()
        if content[0].strip("\n") != "#EXTM3U":
            print(f"File {file_path} is an invalid m3u file.")
            sys.exit(-1)

        # Delete first line with #EXTM3U tag
        content.pop(0)
        groups = {}
        for i in range(0, len(content), 2):
            if i+1 < len(content):
                line = content[i].strip()
                if 'group-title="' in line:
                    group = line.split('group-title="')[-1].split('"')[0]
                    if group not in groups:
                        groups[group] = []
                    groups[group].append(line + '\n' + content[i+1])
        return groups

def write_to_file(output_path, group, content):
    """
    Write the content of a group to a file.
    """
    with open(output_path, "w+") as f:
        f.writelines("#EXTM3U\n")
        f.writelines(content)

# Check if m3u file exists
if not os.path.isfile(m3u_file):
    print(f"File {m3u_file} does not exist.")
    sys.exit(-1)

# Process the m3u file and get the groups
groups = process_m3u_file(m3u_file)

# Filter groups based on regex pattern if provided
pattern = re.compile(groups_regex, re.IGNORECASE)
filtered_groups = {group: content for group, content in groups.items() if pattern.search(group)}

# Output to directory
if output_dir:
    for group, content in filtered_groups.items():
        sanitized_group = sanitize_filename(group)
        os.makedirs(output_dir, exist_ok=True)
        if output_file_prefix:
            output_path = os.path.join(output_dir, f"{output_file_prefix}_{sanitized_group}.m3u")
        else:
            output_path = os.path.join(output_dir, f"{sanitized_group}.m3u")
        write_to_file(output_path, group, content)

# Output to files with prefix
elif output_file_prefix:
    for group, content in filtered_groups.items():
        sanitized_group = sanitize_filename(group)
        output_path = f"{output_file_prefix}_{sanitized_group}.m3u"
        write_to_file(output_path, group, content)