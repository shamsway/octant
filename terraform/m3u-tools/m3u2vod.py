import argparse
import os

def process_m3u_file(file_path):
    with open(file_path, 'r') as file:
        lines = file.readlines()

    modified_lines = []
    entry_lines = []
    for line in lines:
        if line.startswith('#EXTINF:'):
            title = line.split(',', 1)[-1].strip()
            if title and title != '()':
                entry_lines.append('#EXT-X-PLAYLIST-TYPE:VOD\n')
                entry_lines.append(line)
            else:
                entry_lines = []
        elif entry_lines:
            entry_lines.append(line)
            modified_lines.extend(entry_lines)
            entry_lines = []

    return modified_lines

def write_to_file(file_path, lines):
    with open(file_path, 'w') as file:
        file.writelines(lines)

def main():
    parser = argparse.ArgumentParser(description='M3U Modifier')
    parser.add_argument('input_file', help='Path to the input M3U file')
    parser.add_argument('-o', '--output', help='Path to the output M3U file')
    args = parser.parse_args()

    input_file = args.input_file
    output_file = args.output or input_file

    if not os.path.isfile(input_file):
        print(f"File {input_file} does not exist.")
        return

    modified_lines = process_m3u_file(input_file)
    write_to_file(output_file, modified_lines)
    print(f"Modified M3U file saved as {output_file}")

if __name__ == '__main__':
    main()