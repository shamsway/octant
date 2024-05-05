import os
import sys
import re
import requests

def sanitize_filename(filename):
    """
    Sanitize the filename by replacing characters that are not allowed in file names with underscores.
    """
    return re.sub(r'[/\\."\'\`]', '_', filename.strip())

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

def save_strm_files(index):
    """
    Save the entries in the 'index' dictionary as .strm files in the appropriate tvg-type and group-title directories.
    The tvg-type directories are created under the 'output' directory.
    The group-title directories are created as subdirectories of the tvg-type directories.
    """
    for tvg_type, groups in index.items():
        for group_title, entries in groups.items():
            # Remove tvg-type from group-title if it matches at the beginning (case-insensitive)
            subfolder = re.sub(rf'^{re.escape(tvg_type)}\s*', '', group_title, flags=re.IGNORECASE)
            os.makedirs(f'output/{tvg_type}/{subfolder}', exist_ok=True)

            for entry in entries:
                title = entry['title']
                path = entry['path']

                # Remove the year from the title if it matches the subfolder
                title = re.sub(rf'\s*\({re.escape(subfolder)}\)$', '', title)

                print(f'Type: {tvg_type} | Group: {subfolder} | Title: {title}')
                with open(f'output/{tvg_type}/{subfolder}/{sanitize_filename(title)}.strm', 'w') as f:
                    f.write(path)

def main():
    """
    Main function that serves as the entry point of the script.
    It performs the following steps:
    1. Check if the required command-line argument (M3U URL or file path) is provided.
    2. Read the M3U content either from a URL or a local file.
    3. Parse the M3U content using the 'parse_m3u' function.
    4. Save the parsed entries as .strm files using the 'save_strm_files' function.
    5. Handle any errors that may occur during the execution of the script.
    """
    if len(sys.argv) < 2:
        print('Usage: python m3u2strm.py <m3u_url_or_file>')
        sys.exit(1)

    m3u_input = sys.argv[1]

    try:
        if m3u_input.startswith('http://') or m3u_input.startswith('https://'):
            response = requests.get(m3u_input)
            response.raise_for_status()
            raw_m3u = response.text
        else:
            with open(m3u_input, 'r') as f:
                raw_m3u = f.read()

        index = parse_m3u(raw_m3u)
        save_strm_files(index)
    except (requests.exceptions.RequestException, FileNotFoundError, ValueError) as e:
        print(f'Error: {str(e)}')
        sys.exit(1)

if __name__ == '__main__':
    main()