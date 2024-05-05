import xml.etree.ElementTree as ET
import logging
import argparse

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

def combine_xmltv_schedules(file1, file2, output_file):
    logging.info(f"Combining XMLTV schedules: {file1} and {file2}")

    try:
        # Parse the first XMLTV file
        tree1 = ET.parse(file1)
        root1 = tree1.getroot()

        # Parse the second XMLTV file
        tree2 = ET.parse(file2)
        root2 = tree2.getroot()

        # Create a new root element for the combined schedule
        combined_root = ET.Element('tv')

        # Add the channels from both files to the combined schedule
        channels = root1.findall('channel') + root2.findall('channel')
        for channel in channels:
            combined_root.append(channel)

        # Add the programs from both files to the combined schedule
        programs = root1.findall('programme') + root2.findall('programme')
        for program in programs:
            combined_root.append(program)

        # Create a new ElementTree with the combined schedule
        combined_tree = ET.ElementTree(combined_root)

        # Write the combined schedule to the output file
        combined_tree.write(output_file, encoding='UTF-8', xml_declaration=True)

        logging.info(f"Combined schedule saved to: {output_file}")

    except FileNotFoundError as e:
        logging.error(f"File not found: {e}")
    except ET.ParseError as e:
        logging.error(f"Error parsing XML: {e}")
    except Exception as e:
        logging.error(f"An error occurred: {e}")

# Parse command-line arguments
parser = argparse.ArgumentParser(description='Combine two XMLTV schedules into one.')
parser.add_argument('file1', help='Path to the first XMLTV schedule file')
parser.add_argument('file2', help='Path to the second XMLTV schedule file')
parser.add_argument('output_file', help='Path to save the combined schedule')

args = parser.parse_args()

# Call the function with command-line arguments
combine_xmltv_schedules(args.file1, args.file2, args.output_file)