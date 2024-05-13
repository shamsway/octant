import xml.etree.ElementTree as ET
import logging
import argparse
import json
from datetime import datetime

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

def get_xmltv_info(file_path, output_format):

    try:
        # Parse the XMLTV file
        tree = ET.parse(file_path)
        root = tree.getroot()

        # Get the number of channels
        num_channels = len(root.findall('channel'))

        # Get the number of programs
        num_programs = len(root.findall('programme'))

        # Find the earliest start time and latest end time
        earliest_start = None
        latest_end = None

        for program in root.findall('programme'):
            start_time = program.get('start')
            stop_time = program.get('stop')

            if earliest_start is None or start_time < earliest_start:
                earliest_start = start_time

            if latest_end is None or stop_time > latest_end:
                latest_end = stop_time

        # Format the start and end times
        earliest_start_formatted = datetime.strptime(earliest_start, '%Y%m%d%H%M%S %z').strftime('%Y-%m-%d %H:%M:%S %z')
        latest_end_formatted = datetime.strptime(latest_end, '%Y%m%d%H%M%S %z').strftime('%Y-%m-%d %H:%M:%S %z')

        # Create the output data
        output_data = {
            'filename': file_path,
            'num_channels': num_channels,
            'num_programs': num_programs,
            'earliest_start': earliest_start_formatted,
            'latest_end': latest_end_formatted
        }

        # Output the data based on the specified format
        if output_format == 'json':
            print(json.dumps(output_data, indent=2))
        else:
            print(f"Number of channels: {num_channels}")
            print(f"Number of programs: {num_programs}")
            print(f"Earliest start time: {earliest_start_formatted}")
            print(f"Latest end time: {latest_end_formatted}")

    except FileNotFoundError as e:
        logging.error(f"File not found: {e}")
    except ET.ParseError as e:
        logging.error(f"Error parsing XML: {e}")
    except Exception as e:
        logging.error(f"An error occurred: {e}")

# Parse command-line arguments
parser = argparse.ArgumentParser(description='Analyze an XMLTV file and output information.')
parser.add_argument('file_path', help='Path to the XMLTV file')
parser.add_argument('--format', choices=['text', 'json'], default='text', help='Output format (default: text)')

args = parser.parse_args()

# Call the function with command-line arguments
get_xmltv_info(args.file_path, args.format)