import argparse
import os
import re
import requests
import logging

def process_m3u_file(file_path, group_title):
    if file_path.startswith(('http://', 'https://')):
        response = requests.get(file_path)
        response.raise_for_status()
        lines = response.text.strip().split('\n')
    else:
        with open(file_path, 'r') as file:
            lines = file.readlines()

    modified_lines = []
    num_changes = 0
    for line in lines:
        if line.startswith('#EXTINF:'):
            if 'group-title' not in line:
                line = re.sub(r'(#EXTINF:-1)', rf'\1 group-title="{group_title}"', line)
                num_changes += 1
        modified_lines.append(line.strip())

    return modified_lines, num_changes

def write_to_file(file_path, lines):
    with open(file_path, 'w', encoding='utf-8') as file:
        file.write('\n'.join(lines))

def main():
    parser = argparse.ArgumentParser(description='M3U Group Title Adder')
    parser.add_argument('input_file', help='Path or URL to the input M3U file')
    parser.add_argument('group_title', help='Group title to add to each entry')
    parser.add_argument('-o', '--output', help='Path to the output M3U file', required=True)
    args = parser.parse_args()

    input_file = args.input_file
    group_title = args.group_title
    output_file = args.output

    logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')

    try:
        modified_lines, num_changes = process_m3u_file(input_file, group_title)
        write_to_file(output_file, modified_lines)
        logging.info(f"Modified M3U file saved as {output_file}")
        logging.info(f"Number of entries modified: {num_changes}")
    except (requests.exceptions.RequestException, FileNotFoundError, IOError) as e:
        logging.error(f"Error: {str(e)}")

if __name__ == '__main__':
    main()