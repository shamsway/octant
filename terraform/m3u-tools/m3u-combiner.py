import argparse
import os

def combine_m3u_files(folder_path, output_file):
    m3u_files = [file for file in os.listdir(folder_path) if file.endswith('.m3u')]
    
    with open(output_file, 'w', encoding='utf-8') as outfile:
        outfile.write('#EXTM3U\n')
        
        for m3u_file in m3u_files:
            file_path = os.path.join(folder_path, m3u_file)
            with open(file_path, 'r', encoding='utf-8') as infile:
                lines = infile.readlines()
                outfile.writelines(lines[1:])  # Skip the first line (#EXTM3U)
                outfile.write('\n')  # Add a newline between M3U files

def main():
    parser = argparse.ArgumentParser(description='M3U Combiner')
    parser.add_argument('folder_path', help='Path to the folder containing M3U files')
    parser.add_argument('-o', '--output', default='combined.m3u', help='Output file name (default: combined.m3u)')
    args = parser.parse_args()

    folder_path = args.folder_path
    output_file = args.output

    if not os.path.isdir(folder_path):
        print(f"Error: {folder_path} is not a valid directory.")
        return

    combine_m3u_files(folder_path, output_file)
    print(f"Combined M3U file saved as {output_file}")

if __name__ == '__main__':
    main()