import os
import argparse

def delete_duplicates(duplicates_file):
    with open(duplicates_file, 'r') as file:
        duplicates = file.read().splitlines()

    confirm = input("Are you sure you want to delete the duplicate files? (y/n): ")
    if confirm.lower() != 'y':
        print("Deletion cancelled.")
        return

    for duplicate in duplicates:
        if os.path.exists(duplicate):
            os.remove(duplicate)
            print(f"Deleted: {duplicate}")
        else:
            print(f"File not found: {duplicate}")

def main():
    parser = argparse.ArgumentParser(description='Delete duplicate files based on the output of the duplicate finder script.')
    parser.add_argument('duplicates_file', help='File containing the list of duplicates')
    args = parser.parse_args()

    delete_duplicates(args.duplicates_file)

if __name__ == '__main__':
    main()