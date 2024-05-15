import os
import argparse
import re

def sanitize_filename(filename):
    return re.sub(r'[^a-zA-Z0-9]', '', filename)

def find_duplicates(directory):
    duplicates = []
    file_dict = {}

    for filename in os.listdir(directory):
        if filename.endswith('.strm') or filename.endswith('.nfo'):
            base_name = os.path.splitext(filename)[0]
            sanitized_name = sanitize_filename(base_name)

            if sanitized_name in file_dict:
                if filename.endswith('.strm'):
                    if file_dict[sanitized_name]['strm']:
                        duplicates.append(os.path.join(directory, filename))
                    else:
                        file_dict[sanitized_name]['strm'] = True
                elif filename.endswith('.nfo'):
                    if file_dict[sanitized_name]['nfo']:
                        duplicates.append(os.path.join(directory, filename))
                    else:
                        file_dict[sanitized_name]['nfo'] = True
            else:
                file_dict[sanitized_name] = {'strm': filename.endswith('.strm'), 'nfo': filename.endswith('.nfo')}

    return duplicates

def search_directory(directory):
    all_duplicates = []

    for root, dirs, files in os.walk(directory):
        duplicates = find_duplicates(root)
        if duplicates:
            all_duplicates.extend(duplicates)

    return all_duplicates

def save_duplicates_to_file(duplicates, output_file):
    with open(output_file, 'w') as file:
        file.write('\n'.join(duplicates))

def main():
    parser = argparse.ArgumentParser(description='Find duplicate .strm and .nfo files.')
    parser.add_argument('directory', help='Directory to search for duplicates')
    parser.add_argument('-o', '--output', help='Output file to save the list of duplicates')
    args = parser.parse_args()

    duplicates = search_directory(args.directory)

    if duplicates:
        print("Duplicate files found:")
        for duplicate in duplicates:
            print(duplicate)

        if args.output:
            save_duplicates_to_file(duplicates, args.output)
            print(f"\nDuplicate files saved to: {args.output}")
    else:
        print("No duplicate files found.")

if __name__ == '__main__':
    main()