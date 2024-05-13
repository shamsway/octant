# M3U Filter/Splitter
Adapted from https://github.com/faniryxx/iptv-filtering-script/tree/main

This Python script filters an M3U playlist based on user-specified criteria and splits it into smaller playlists. It provides options to output the filtered playlists to either separate files or a directory structure.

## Usage

```
python m3u_filter.py --m3u <m3u_file> [--output-dir <output_directory>] [--output-file <output_file_prefix>] [--regex <regex_pattern>] [--verbose]
```

- `--m3u <m3u_file>`: The path to the local M3U file to be filtered (required).
- `--output-dir <output_directory>`: The directory where the filtered playlists will be saved as separate files.
- `--output-file <output_file_prefix>`: The prefix for the output files when saving the filtered playlists as separate files in the current directory.
- `--regex <regex_pattern>`: A regular expression pattern to filter the groups. Only the groups matching the pattern will be included in the output (optional).
- `--verbose`: Enable verbose logging to display the created files and directories.

Note: Either `--output-dir` or `--output-file` must be provided, but not both.

## Dependencies

- Python 3.x

## Functionality

1. The script takes the path to a local M3U file as a required command-line argument.
2. It reads the M3U file and parses its content into a dictionary called `index`, where the keys are the group names and the values are lists of entries. Each entry is a dictionary containing metadata such as group, title, and path.
3. If a regex pattern is provided using the `--regex` option, the script filters the groups based on the pattern. Only the groups matching the pattern will be included in the output.
4. If the `--output-dir` option is specified, the script creates a directory structure where each group has its own directory, and the filtered playlists are saved as separate files within their respective group directories.
5. If the `--output-file` option is specified, the script saves the filtered playlists as separate files in the current directory, with the provided prefix followed by the sanitized group name.
6. The script sanitizes the group names and file names by replacing characters that are not allowed in file names with underscores.
7. If the `--verbose` option is provided, the script logs the created files and directories to the console.

## Example

```
python m3u_filter.py --m3u playlist.m3u --output-dir filtered_playlists --regex "Sports|News" --verbose
```

This command will filter the `playlist.m3u` file, keeping only the groups matching the regex pattern "Sports|News". The filtered playlists will be saved as separate files in the `filtered_playlists` directory, and verbose logging will be enabled.

# XMLTV Merge tool

## Example usage
file1 = 'schedule1.xml'
file2 = 'schedule2.xml'
output_file = 'combined_schedule.xml'

combine_xmltv_schedules(file1, file2, output_file)

# M3U to STRM Converter

This Python script converts an M3U playlist to a directory structure containing .strm files. It takes an M3U URL or file path as input and generates .strm files in the appropriate tvg-type and group-title directories under the specified output directory.
Usage
Copy codepython m3u2strm.py <m3u_url_or_file> [-v] [-o OUTPUT_DIR]

<m3u_url_or_file>: The URL or local file path of the M3U playlist.
-v, --verbose: Enable verbose output to display the files being created (optional).
-o OUTPUT_DIR, --output-dir OUTPUT_DIR: Specify the output directory (default: output).

## Dependencies

Python 3.x
requests library (can be installed via pip install requests)

## Functionality

The script takes an M3U URL or file path as a command-line argument.
It reads the M3U content either from the provided URL or local file.
The M3U content is parsed into a nested dictionary called index, where the keys are the tvg-type values and the values are dictionaries containing group-title as keys and lists of entries as values. Each entry is a dictionary containing metadata such as tvg-id, tvg-name, tvg-type, group-title, title, and path.
The script creates folders for each unique tvg-type under the specified output directory.
For each group-title, a subfolder is created within the corresponding tvg-type folder. The group-title is modified by removing the tvg-type and any whitespace from the beginning of the string (case-insensitive).
For each entry in the index dictionary, a .strm file is created in the corresponding tvg-type and group-title directory. The filename is derived from the entry's title, and the file content is the entry's path.
If the title of an entry ends with a year in parentheses that matches the subfolder name, the year and parentheses are removed from the filename.
If an entry is missing a title, it is skipped.
The script sanitizes both directory and file names by replacing characters that are not allowed with underscores.
If the -v or --verbose option is provided, the script displays the files being created.
After the script completes, it outputs the number of groups and files created.
The script handles errors that may occur during execution, such as invalid URLs, file not found, or invalid M3U content.

## Example
Copy codepython m3u2strm.py https://example.com/playlist.m3u -v -o /path/to/output
This command will convert the M3U playlist located at https://example.com/playlist.m3u to .strm files in the /path/to/output directory, organized by tvg-type and group-title. Verbose output will be enabled, displaying the files being created. After completion, the script will output the number of groups and files created.

# XMLTV Info
This Python script reads an XMLTV file and outputs the following information:

- Number of channels in the XMLTV file
- Number of programs in the XMLTV file
- The start time & date of the earliest program
- The end time & date of the latest program

The script also includes an option to output the data in JSON format.

## Usage

Make sure you have Python installed on your system.
Save the script to a file named xmltv_info.py.
Open a terminal or command prompt and navigate to the directory where the script is located.
Run the script using the following command:
`python xmltv_info.py <file_path> [--format FORMAT]`

<file_path>: The path to the XMLTV file.
--format FORMAT (optional): The output format. Valid options are text (default) and json.

The script will analyze the XMLTV file and output the requested information based on the specified format.

## Command-Line Arguments
The script accepts the following command-line arguments:

file_path (required): The path to the XMLTV file.
--format FORMAT (optional): The output format. Valid options are text (default) and json.

Output
The script outputs the following information:

Number of channels in the XMLTV file
Number of programs in the XMLTV file
The start time & date of the earliest program
The end time & date of the latest program

By default, the output is displayed in a human-readable text format. If the --format json option is specified, the output will be in JSON format.

The script includes basic logging to provide information about the analysis process and any errors that may occur. The logging messages will be displayed in the console when running the script.

INFO level messages indicate the progress of the analysis process.
ERROR level messages indicate any errors that occur during the process, such as file not found or XML parsing errors.

## Dependencies
The script relies on the following Python modules:

xml.etree.ElementTree (built-in): Used for parsing and manipulating XML files.
logging (built-in): Used for logging messages.
argparse (built-in): Used for parsing command-line arguments.
json (built-in): Used for JSON serialization.
datetime (built-in): Used for date and time parsing and formatting.