import os
import sys
import re
import argparse
import requests

def sanitize_filename(filename):
    """
    Sanitize the filename by removing invalid characters and replacing spaces with underscores.
    """
    sanitized = re.sub(r'[<>:"/\\|?*]', '', filename.strip())
    sanitized = re.sub(r'[\u200b\u200e\u200f\u202a\u202c\u202d\u202e\ufeff\u2028\u2029]+', '', sanitized)
    sanitized = re.sub(r'\s+', '_', sanitized)
    return sanitized

def parse_m3u(raw_m3u):
    """
    Parse the raw M3U content into a dictionary called 'index'.
    The 'index' dictionary contains tvg-type as keys and a dictionary of group-title and entries as values.
    Each entry is a dictionary containing metadata such as tvg-id, tvg-name, group-title, and path.
    """
    lines = raw_m3u.strip().split('\n')
    if lines[0] != '#EXTM3U':
        raise ValueError('Invalid M3U file')

    index = {}
    current_meta = {}

    for line in lines[1:]:
        if line.startswith('#EXTINF:'):
            tvg_id = re.search(r'tvg-id="(.*?)"', line)
            tvg_name = re.search(r'tvg-name="(.*?)"', line)
            tvg_type = re.search(r'tvg-type="(.*?)"', line)
            group_title = re.search(r'group-title="(.*?)"', line)
            title = line.split(',', 1)[-1].strip()

            if tvg_id and tvg_name and tvg_type and group_title and title:
                current_meta['tvg_id'] = tvg_id.group(1)
                current_meta['tvg_name'] = tvg_name.group(1)
                current_meta['tvg_type'] = tvg_type.group(1)
                current_meta['group_title'] = group_title.group(1)
                current_meta['title'] = title
            else:
                current_meta = {}
        elif line.startswith('#'):
            continue
        else:
            if current_meta:
                current_meta['path'] = line.strip()
                tvg_type = current_meta['tvg_type']
                group_title = current_meta['group_title']

                if tvg_type not in index:
                    index[tvg_type] = {}
                if group_title not in index[tvg_type]:
                    index[tvg_type][group_title] = []

                index[tvg_type][group_title].append(current_meta)
                current_meta = {}

    return index

def save_strm_files(index, output_dir, verbose):
    """
    Save the entries in the 'index' dictionary as .strm files in the appropriate tvg-type and group-title directories.
    The tvg-type directories are created under the specified output directory.
    The group-title directories are created as subdirectories of the tvg-type directories.
    """
    num_groups = 0
    num_files = 0

    for tvg_type, groups in index.items():
        sanitized_tvg_type = sanitize_filename(tvg_type)
        for group_title, entries in groups.items():
            # Remove tvg-type from group-title if it matches at the beginning (case-insensitive)
            subfolder = re.sub(rf'^{re.escape(tvg_type)}\s*', '', group_title, flags=re.IGNORECASE)
            sanitized_subfolder = sanitize_filename(subfolder)
            os.makedirs(f'{output_dir}/{sanitized_tvg_type}/{sanitized_subfolder}', exist_ok=True)
            num_groups += 1

            for entry in entries:
                title = entry['title']
                path = entry['path']

                # Remove the year from the title if it matches the subfolder
                title = re.sub(rf'\s*\({re.escape(subfolder)}\)$', '', title)
                sanitized_title = sanitize_filename(title)

                if verbose:
                    print(f'Type: {sanitized_tvg_type} | Group: {sanitized_subfolder} | Title: {sanitized_title}')

                with open(f'{output_dir}/{sanitized_tvg_type}/{sanitized_subfolder}/{sanitized_title}.strm', 'w') as f:
                    f.write(path)
                    num_files += 1

    print(f'Created {num_groups} groups and {num_files} files.')

def main():
    """
    Main function that serves as the entry point of the script.
    It performs the following steps:
    1. Parse command-line arguments.
    2. Read the M3U content either from a URL or a local file.
    3. Parse the M3U content using the 'parse_m3u' function.
    4. Save the parsed entries as .strm files using the 'save_strm_files' function.
    5. Handle any errors that may occur during the execution of the script.
    """
    parser = argparse.ArgumentParser(description='M3U to STRM Converter')
    parser.add_argument('m3u_input', help='M3U URL or file path')
    parser.add_argument('-v', '--verbose', action='store_true', help='Enable verbose output')
    parser.add_argument('-o', '--output-dir', default='output', help='Output directory (default: output)')
    args = parser.parse_args()

    m3u_input = args.m3u_input
    verbose = args.verbose
    output_dir = args.output_dir

    try:
        if m3u_input.startswith('http://') or m3u_input.startswith('https://'):
            response = requests.get(m3u_input)
            response.raise_for_status()
            raw_m3u = response.text
        else:
            with open(m3u_input, 'r') as f:
                raw_m3u = f.read()

        index = parse_m3u(raw_m3u)
        save_strm_files(index, output_dir, verbose)
    except (requests.exceptions.RequestException, FileNotFoundError, ValueError) as e:
        print(f'Error: {str(e)}')
        sys.exit(1)

if __name__ == '__main__':
    main()