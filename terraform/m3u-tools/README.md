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

# M3U to VOD

# M3U to VOD Converter

`m3u2vod.py` is a Python script that modifies an M3U file by inserting the line `#EXT-X-PLAYLIST-TYPE:VOD` before each entry that has a valid title. Entries missing a title or with an empty title `()` are excluded from the output file. This script is useful for converting M3U playlists to VOD (Video on Demand) format.

## Usage

```
python m3u2vod.py <input_file> [-o OUTPUT]
```

- `<input_file>`: The path to the input M3U file (required).
- `-o OUTPUT`, `--output OUTPUT`: The path to the output M3U file (optional). If not specified, the input file will be overwritten.

## Functionality

1. The script takes the path to an input M3U file as a required command-line argument.
2. It reads the M3U file and processes each line.
3. For each line starting with `#EXTINF:`, the script checks if the entry has a valid title.
   - If the entry has a valid title (not empty and not `()`), the script inserts the line `#EXT-X-PLAYLIST-TYPE:VOD` before it and includes the entry in the output file.
   - If the entry is missing a title or has an empty title `()`, it is excluded from the output file.
4. The modified lines are written to the output M3U file.
5. If an output file path is specified using the `-o` or `--output` option, the modified M3U file will be saved with that name. Otherwise, the input file will be overwritten.
6. The script displays a message indicating the path of the modified M3U file.

## Example

Suppose you have an M3U file named `input.m3u` with the following content:

```
#EXTM3U
#EXTINF:-1 tvg-id="tt0010323" tvg-name="tt0010323" tvg-type="movies" group-title="Movies 1920" ,The Cabinet of Dr. Caligari (1920)
https://streaming.com/movie/tt0010323
#EXTINF:-1 tvg-id="tt0643109" tvg-name="tt0643109" tvg-type="movies" group-title="Movies " , ()
https://streaming.commovie/tt0643109
#EXTINF:-1 tvg-id="tt0015864" tvg-name="tt0015864" tvg-type="movies" group-title="Movies 1920" ,The Gold Rush (1925) 
https://streaming.com/movie/tt0015864
```

To convert this M3U file to VOD format and save the modified file as `output.m3u`, run the following command:

```
python m3u2vod.py input.m3u -o output.m3u
```

After running the script, the `output.m3u` file will contain the following:

```
#EXTM3U
#EXT-X-PLAYLIST-TYPE:VOD
#EXTINF:-1 tvg-id="tt0010323" tvg-name="tt0010323" tvg-type="movies" group-title="Movies 1920" ,The Cabinet of Dr. Caligari (1920)
https://streaming.com/movie/tt0010323
#EXT-X-PLAYLIST-TYPE:VOD
#EXTINF:-1 tvg-id="tt0015864" tvg-name="tt0015864" tvg-type="movies" group-title="Movies 1920" ,The Gold Rush (1925) 
https://streaming.com/movie/tt0015864
```

The entry with the empty title `()` has been excluded from the output file, and the line `#EXT-X-PLAYLIST-TYPE:VOD` has been inserted before each valid entry.

# M3U Group Title Adder

`m3u-group.py` is a Python script that modifies an M3U file by adding a specified `group-title` attribute to each entry that doesn't already have one. It can load an M3U file from a local path or a URL and saves the modified M3U file to a specified output path.

## Usage

```
python m3u-group.py <input_file> <group_title> -o <output_file>
```

- `<input_file>`: The path or URL to the input M3U file (required).
- `<group_title>`: The group title to add to each entry (required).
- `-o <output_file>`, `--output <output_file>`: The path to the output M3U file (required).

## Functionality

1. The script takes the path or URL to an input M3U file, the group title to add, and the path to the output M3U file as command-line arguments.
2. It reads the M3U file either from a local path or a URL.
3. For each line starting with `#EXTINF:`, the script checks if the `group-title` attribute is missing.
   - If the `group-title` attribute is missing, the script adds it with the specified group title.
4. The modified lines are written to the output M3U file.
5. The script logs informational messages indicating the path of the modified M3U file and the number of entries modified.
6. If an error occurs during the process (e.g., invalid URL, file not found), the script logs an error message.

## Example

Suppose you have an M3U file named `input.m3u` with the following content:

```
#EXTM3U
#EXTINF:-1 tvg-id="channel1" tvg-name="Channel 1",Channel 1
http://example.com/channel1.m3u8
#EXTINF:-1 tvg-id="channel2" tvg-name="Channel 2" group-title="Sports",Channel 2
http://example.com/channel2.m3u8
#EXTINF:-1 tvg-id="channel3" tvg-name="Channel 3",Channel 3
http://example.com/channel3.m3u8
```

To add the `group-title="Entertainment"` attribute to each entry that doesn't already have a `group-title` attribute and save the modified M3U file as `output.m3u`, run the following command:

```
python m3u-group.py input.m3u "Entertainment" -o output.m3u
```

After running the script, the `output.m3u` file will contain the following:

```
#EXTM3U
#EXTINF:-1 tvg-id="channel1" tvg-name="Channel 1" group-title="Entertainment",Channel 1
http://example.com/channel1.m3u8
#EXTINF:-1 tvg-id="channel2" tvg-name="Channel 2" group-title="Sports",Channel 2
http://example.com/channel2.m3u8
#EXTINF:-1 tvg-id="channel3" tvg-name="Channel 3" group-title="Entertainment",Channel 3
http://example.com/channel3.m3u8
```

The script will also log the following informational messages:

```
INFO: Modified M3U file saved as output.m3u
INFO: Number of entries modified: 2
```

## Dependencies

- Python 3.x
- `requests` library (install using `pip install requests`)

# M3U Playlist Generator

`m3u-playlist-generator.py` is a Python script that generates individual M3U files for each playlist category specified in a top-level M3U file. It retrieves the playlist categories and URLs from the top-level M3U file and uses the m3u-group.py script to generate the corresponding M3U files.

## Usage

`m3u-playlist-generator.py <top_level_m3u_url> [-o <output_dir>]`

* <top_level_m3u_url>: The URL of the top-level M3U file containing the playlist categories and URLs (required).
* -o <output_dir>, --output-dir <output_dir>: The output directory for the generated M3U files (optional, default: current directory).

## Functionality

The script takes the URL of the top-level M3U file as a command-line argument.
It retrieves the content of the top-level M3U file from the specified URL.
It extracts the playlist categories and URLs from the M3U file.
For each playlist category, the script calls the m3u-group.py script to generate an individual M3U file.
The generated M3U files are saved in the specified output directory (or the current directory if not specified).
The script logs informational messages indicating the progress of the playlist retrieval and M3U file generation.

## Example

Suppose you have a top-level M3U file located at http://tvheadend.service.consul:9981/playlist/tags with the following content:

```
#EXTM3U
#EXTINF:-1 type="playlist",Animals + Nature
http://tvheadend.service.consul:9981/playlist/tagid/41841102?profile=pass
#EXTINF:-1 type="playlist",Anime
http://tvheadend.service.consul:9981/playlist/tagid/1440828330?profile=pass
#EXTINF:-1 type="playlist",Antenna
http://tvheadend.service.consul:9981/playlist/tagid/1040375511?profile=pass
#EXTINF:-1 type="playlist",Apollo
http://tvheadend.service.consul:9981/playlist/tagid/637971264?profile=pass
#EXTINF:-1 type="playlist",Classic TV
http://tvheadend.service.consul:9981/playlist/tagid/1537349529?profile=pass
```

To generate individual M3U files for each playlist category and save them in the output_playlists directory, run the following command:

`python m3u-playlist-generator.py http://tvheadend.service.consul:9981/playlist/tags -o output_playlists`

After running the script, you will find the following M3U files in the output_playlists directory:

Animals + Nature.m3u
Anime.m3u
Antenna.m3u
Apollo.m3u
Classic TV.m3u

The script will also log informational messages indicating the progress and the generated M3U files:

```
INFO: Retrieving playlists from: http://tvheadend.service.consul:9981/playlist/tags
INFO: Found 5 playlists
INFO: Generating M3U file for category: Animals + Nature
INFO: Generated M3U file: output_playlists/Animals + Nature.m3u
INFO: Generating M3U file for category: Anime
INFO: Generated M3U file: output_playlists/Anime.m3u
INFO: Generating M3U file for category: Antenna
INFO: Generated M3U file: output_playlists/Antenna.m3u
INFO: Generating M3U file for category: Apollo
INFO: Generated M3U file: output_playlists/Apollo.m3u
INFO: Generating M3U file for category: Classic TV
INFO: Generated M3U file: output_playlists/Classic TV.m3u
```

## Dependencies

- Python 3.x
- `requests` library (install using pip install requests)
- `m3u-group.py` script should be in the same directory as `m3u-playlist-generator.py`

# M3U Combiner

`m3u-combiner.py` is a Python script that combines all the M3U files in a specified folder into a single M3U file. It reads each M3U file in the folder and appends its contents (excluding the first line) to the output file.

## Usage

```
python m3u-combiner.py <folder_path> [-o OUTPUT]
```

- `<folder_path>`: The path to the folder containing the M3U files to be combined (required).
- `-o OUTPUT`, `--output OUTPUT`: The name of the output file (optional, default: `combined.m3u`).

## Functionality

1. The script takes the path to the folder containing the M3U files as a command-line argument.
2. It retrieves a list of all the M3U files (files with the `.m3u` extension) in the specified folder.
3. It creates a new output file with the specified name (or `combined.m3u` by default) and writes the `#EXTM3U` header.
4. For each M3U file in the folder:
   - It reads the contents of the file.
   - It appends the contents (excluding the first line, which is assumed to be `#EXTM3U`) to the output file.
   - It adds a newline character between each appended M3U file to maintain separation.
5. The script saves the combined M3U file with the specified output name (or `combined.m3u` by default).
6. It prints a message indicating the path of the combined M3U file.

## Example

Suppose you have a folder named `m3u_files` containing the following M3U files:

- `group1.m3u`
- `group2.m3u`
- `group3.m3u`

To combine these M3U files into a single file named `all_groups.m3u`, run the following command:

```
python m3u-combiner.py m3u_files -o all_groups.m3u
```

After running the script, you will have a file named `all_groups.m3u` in the current directory that contains the combined contents of all the M3U files in the `m3u_files` folder.

## Dependencies

- Python 3.x

## License

This script is released under the [MIT License](https://opensource.org/licenses/MIT).

---

Feel free to modify and enhance the script and documentation as needed. Let me know if you have any further questions!

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