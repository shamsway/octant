import os
import sys
import re
import argparse

def sanitize_filename(filename):
    """
    Sanitize the filename by removing invalid characters and replacing spaces with underscores.
    """
    sanitized = re.sub(r'[<>:"/\\|?*\']', '', filename.strip())
    sanitized = re.sub(r'[\u200b\u200e\u200f\u202a\u202c\u202d\u202e\ufeff\u2028\u2029]+', '', sanitized)
    sanitized = re.sub(r'\s+', '_', sanitized)
    return sanitized
def rename_files_and_directories(path, verbose):
    """
    Recursively rename files and directories within the specified path using the 'sanitize_filename' function.
    Log the changes made if verbose mode is enabled.
    """
    for root, dirs, files in os.walk(path, topdown=False):
        for name in files:
            old_file_path = os.path.join(root, name)
            new_file_name = sanitize_filename(name)
            new_file_path = os.path.join(root, new_file_name)
            
            if old_file_path != new_file_path:
                os.rename(old_file_path, new_file_path)
                if verbose:
                    print(f"Renamed file: {old_file_path} -> {new_file_path}")
        
        for name in dirs:
            old_dir_path = os.path.join(root, name)
            new_dir_name = sanitize_filename(name)
            new_dir_path = os.path.join(root, new_dir_name)
            
            if old_dir_path != new_dir_path:
                os.rename(old_dir_path, new_dir_path)
                if verbose:
                    print(f"Renamed directory: {old_dir_path} -> {new_dir_path}")

def main():
    """
    Main function that serves as the entry point of the script.
    It performs the following steps:
    1. Parse command-line arguments.
    2. Call the 'rename_files_and_directories' function with the specified path and verbose mode.
    3. Handle any errors that may occur during the execution of the script.
    """
    parser = argparse.ArgumentParser(description='Directory and File Renaming Script')
    parser.add_argument('path', help='Path to the directory containing files and subdirectories to be renamed')
    parser.add_argument('-v', '--verbose', action='store_true', help='Enable verbose output')
    args = parser.parse_args()

    path = args.path
    verbose = args.verbose

    if not os.path.exists(path):
        print(f"Error: The specified path does not exist: {path}")
        sys.exit(1)

    try:
        rename_files_and_directories(path, verbose)
    except Exception as e:
        print(f"Error: {str(e)}")
        sys.exit(1)

if __name__ == '__main__':
    main()
