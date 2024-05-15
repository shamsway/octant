import argparse
import os
import subprocess
import tempfile
import requests
import logging
import re

def get_playlists_from_m3u(m3u_url):
    response = requests.get(m3u_url)
    response.raise_for_status()
    lines = response.text.strip().split('\n')

    playlists = []
    for i in range(1, len(lines), 2):
        if lines[i].startswith('#EXTINF:'):
            category = lines[i].split('type="playlist",')[1].strip()
            url = lines[i + 1].strip()
            playlists.append((category, url))

    return playlists

def sanitize_filename(filename):
    # Remove spaces and replace with underscores
    filename = filename.replace(' ', '_')
    
    # Remove any characters that are not alphanumeric, underscore, or dash
    filename = re.sub(r'[^a-zA-Z0-9_-]', '', filename)
    
    return filename

def generate_m3u_files(playlists, output_dir):
    for category, url in playlists:
        sanitized_category = sanitize_filename(category)
        output_file = os.path.join(output_dir, f"{sanitized_category}.m3u")
        logging.info(f"Generating M3U file for category: {category}")
        subprocess.run(['python3', 'm3u-group.py', url, category, '-o', output_file])
        logging.info(f"Generated M3U file: {output_file}")

def main():
    parser = argparse.ArgumentParser(description='M3U Playlist Generator')
    parser.add_argument('top_level_m3u_url', help='URL of the top-level M3U file')
    parser.add_argument('-o', '--output-dir', default='.', help='Output directory for generated M3U files (default: current directory)')
    args = parser.parse_args()

    top_level_m3u_url = args.top_level_m3u_url
    output_dir = args.output_dir

    os.makedirs(output_dir, exist_ok=True)

    logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')

    logging.info(f"Retrieving playlists from: {top_level_m3u_url}")
    playlists = get_playlists_from_m3u(top_level_m3u_url)
    logging.info(f"Found {len(playlists)} playlists")

    generate_m3u_files(playlists, output_dir)

if __name__ == '__main__':
    main()