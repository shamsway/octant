import os
import mimetypes
import logging
import argparse
import fnmatch
from pathlib import Path
import re
import yaml
import ast

# Reduced maximum size of each output chunk (in bytes)
MAX_CHUNK_SIZE = 180000  # Leaving room for prompts and other input

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def is_binary(file_path):
    _, extension = os.path.splitext(file_path)    
    if extension in ['.sh', '.json', '.xml']:
        return False
        
    mime_type, _ = mimetypes.guess_type(file_path)
    return mime_type is not None and not mime_type.startswith('text')

def parse_gitignore(directory):
    gitignore_path = os.path.join(directory, '.gitignore')
    patterns = ['.git','**/.git','/.git/*']  # Always exclude .git
    
    if os.path.exists(gitignore_path):
        with open(gitignore_path, 'r') as gitignore:
            for line in gitignore:
                line = line.strip()
                if line and not line.startswith('#'):
                    patterns.append(line)
    
    return patterns

def should_exclude(path, root, excluded_patterns):
    rel_path = os.path.relpath(path, root)
    for pattern in excluded_patterns:
        if pattern.startswith('/'):
            if fnmatch.fnmatch(rel_path, pattern[1:]) or fnmatch.fnmatch(rel_path, f"*{pattern}"):
                return True
        elif pattern.startswith('**/'):
            if fnmatch.fnmatch(rel_path, pattern[3:]) or fnmatch.fnmatch(rel_path, f"*/{pattern[3:]}"):
                return True
        elif fnmatch.fnmatch(rel_path, pattern) or fnmatch.fnmatch(os.path.basename(path), pattern):
            return True
    return False

def process_files(directory, output_files, tree_file, excluded_patterns, file_list, prefix='', root_only=False):
    try:
        for item in os.scandir(directory):
            rel_path = os.path.relpath(item.path, directory)
            full_rel_path = os.path.normpath(os.path.join(os.path.relpath(directory, os.path.dirname(os.path.dirname(directory))), rel_path))
            logger.debug(f"Processing item: {full_rel_path}")
            
            if should_exclude(item.path, directory, excluded_patterns):
                logger.info(f"Skipped excluded item: {full_rel_path}")
                continue
            
            if item.is_file():
                file_list.append(full_rel_path)
                logger.debug(f"Added to file list: {full_rel_path}")
                
                if not is_binary(item.path):
                    try:
                        with open(item.path, 'r', encoding='utf-8', errors='ignore') as file:
                            content = file.read()
                            file_header = f"==== File: {full_rel_path} ====\n"
                            file_content = file_header + content + "\n\n"
                            file_size = len(file_content.encode('utf-8'))
                            
                            if file_size > MAX_CHUNK_SIZE:
                                logger.warning(f"File {full_rel_path} exceeds the maximum chunk size and will be skipped.")
                            else:
                                current_file = output_files[-1]
                                current_file_size = current_file['size']
                                
                                if current_file_size + file_size > MAX_CHUNK_SIZE:
                                    output_files.append({'file': open(f'bundled_files_{len(output_files)}.txt', 'w', encoding='utf-8'), 'size': 0})
                                    current_file = output_files[-1]
                                
                                current_file['file'].write(file_content)
                                current_file['size'] += file_size
                                logger.info(f"Processed file: {full_rel_path}")
                    except Exception as e:
                        logger.error(f"Error processing file {full_rel_path}: {str(e)}")
                else:
                    logger.info(f"Skipped binary file: {full_rel_path}")
                
                tree_file.write(f"{prefix}├── {full_rel_path}\n")
            
            elif item.is_dir():
                tree_file.write(f"{prefix}├── {full_rel_path}/\n")
                logger.info(f"Processing directory: {full_rel_path}")
                if not root_only:
                    new_prefix = prefix + "│   "
                    process_files(item.path, output_files, tree_file, excluded_patterns, file_list, new_prefix, root_only)
                else:
                    file_list.append(f"{full_rel_path}/")
    except Exception as e:
        logger.error(f"Error processing directory {directory}: {str(e)}")

def bundle_files(directory, excluded_patterns, root_only=False, analyze=False):
    gitignore_patterns = parse_gitignore(directory)
    excluded_patterns = list(set(excluded_patterns + gitignore_patterns))
    
    output_files = [{'file': open('bundled_files_0.txt', 'w', encoding='utf-8'), 'size': 0}]
    file_list = []
    
    try:
        with open('file_tree.txt', 'w', encoding='utf-8') as tree_file:
            tree_file.write(f"{directory}/\n")
            logger.info(f"Starting file bundling process for directory: {directory}")
            process_files(directory, output_files, tree_file, excluded_patterns, file_list, root_only=root_only)
            logger.info("File bundling process completed.")

        logger.debug(f"File list after processing: {file_list}")

        # Add consolidated file list to the end of each bundle
        for i, file_obj in enumerate(output_files):
            file_obj['file'].write("\n=== Files in this bundle ===\n")
            for file_path in file_list:
                file_obj['file'].write(f"{file_path}\n")
            file_obj['file'].flush()  # Ensure all data is written to disk

        # Calculate and display total bundle size
        total_size = sum(os.path.getsize(f'bundled_files_{i}.txt') for i in range(len(output_files)))
        logger.info(f"Total bundle size: {total_size / 1024:.2f} KB")

        if analyze:
            analysis_report = generate_analysis_report(directory, file_list, root_only, excluded_patterns)
            with open('analysis_report.txt', 'w', encoding='utf-8') as report_file:
                report_file.write(analysis_report)
            logger.info("Analysis report generated: analysis_report.txt")

    except Exception as e:
        logger.error(f"Error during file bundling: {str(e)}")
    finally:
        for file_obj in output_files:
            file_obj['file'].close()

def categorize_files(file_list):
    categories = {
        'Configuration': ['.gitignore', '.env', '*.conf', '*.config', '*.json', 'agent.yml', 'configuration.yaml', 'config.yml', 'nomad-dynamic-config.yml'],
        'Docker': ['docker-compose.yml'],
        'Ansible Playbooks': ['*.yml', '*.yaml'],
        'Python Scripts': ['*.py'],
        'Documentation': ['*.md', '*.txt'],
        'Build/Deployment': ['Makefile', '*.sh'],
        'Terraform': ['*.tf'],
        'Nomad Job/Template': ['*.hcl', '*.nomad'],
        'Jinja': ['*.j2']
    }
    
    categorized = {cat: [] for cat in categories}
    
    for file in file_list:
        logger.debug(f"Categorizing file: {file}")
        for category, patterns in categories.items():
            if any(fnmatch.fnmatch(os.path.basename(file), pattern) for pattern in patterns):
                categorized[category].append(file)
                logger.debug(f"Categorized {file} as {category}")
                break
        else:
            categorized.setdefault('Other', []).append(file)
            logger.debug(f"Categorized {file} as Other")
    
    return categorized

def analyze_dependencies(directory, file_list):
    dependencies = set()
    for file in file_list:
        full_path = os.path.join(directory, file)
        if os.path.isfile(full_path):
            if file.endswith('.py'):
                with open(full_path, 'r', encoding='utf-8', errors='ignore') as f:
                    content = f.read()
                    tree = ast.parse(content)
                    for node in ast.walk(tree):
                        if isinstance(node, ast.Import):
                            for n in node.names:
                                dependencies.add(n.name)
                        elif isinstance(node, ast.ImportFrom):
                            dependencies.add(node.module)
            elif file.endswith('.yml') or file.endswith('.yaml'):
                with open(full_path, 'r', encoding='utf-8', errors='ignore') as f:
                    content = f.read()
                    if 'ansible' in content.lower():
                        dependencies.add('ansible')
    return list(dependencies)

def find_todos(directory, file_list):
    todos = []
    for file in file_list:
        full_path = os.path.join(directory, file)
        if os.path.isfile(full_path):
            with open(full_path, 'r', encoding='utf-8', errors='ignore') as f:
                for i, line in enumerate(f, 1):
                    if 'TODO' in line:
                        todos.append(f"{file}:{i}: {line.strip()}")
    return todos

def analyze_code_structure(file):
    structure = []
    with open(file, 'r') as f:
        content = f.read()
        if file.endswith('.yml') or file.endswith('.yaml'):
            # Simple YAML structure analysis
            for i, line in enumerate(content.split('\n'), 1):
                if line.strip() and not line.startswith(' '):
                    structure.append(f"Line {i}: {line.strip()}")
        elif file.endswith('.py'):
            tree = ast.parse(content)
            for node in ast.walk(tree):
                if isinstance(node, (ast.FunctionDef, ast.ClassDef)):
                    structure.append(f"Line {node.lineno}: {node.__class__.__name__} {node.name}")
    return structure

def find_env_variables(directory, file_list):
    env_vars = set()
    for file in file_list:
        full_path = os.path.join(directory, file)
        if os.path.isfile(full_path):
            with open(full_path, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
                # Look for common environment variable patterns
                vars = re.findall(r'\${?\w+}?', content)
                vars += re.findall(r'os\.environ\.get\([\'"](\w+)[\'"]', content)
                vars += re.findall(r'os\.getenv\([\'"](\w+)[\'"]', content)
                env_vars.update(vars)
    return list(env_vars)

def analyze_makefile(file):
    targets = []
    with open(file, 'r') as f:
        content = f.read()
        targets = re.findall(r'^([a-zA-Z0-9_-]+):', content, re.MULTILINE)
    return targets

def explain_folder_structure(directory):
    explanation = {}
    gitignore_patterns = parse_gitignore(directory)
    
    for root, dirs, files in os.walk(directory):
        rel_path = os.path.relpath(root, directory)
        if rel_path == '.':
            continue
        
        # Filter out ignored directories and files
        dirs[:] = [d for d in dirs if not should_exclude(os.path.join(root, d), directory, gitignore_patterns)]
        files = [f for f in files if not should_exclude(os.path.join(root, f), directory, gitignore_patterns)]
        
        if dirs or files:  # Only include non-empty directories
            explanation[rel_path] = f"Contains {len(files)} files and {len(dirs)} subdirectories"
    
    return explanation

def generate_analysis_report(directory, file_list, root_only, excluded_patterns):
    logger.debug(f"Generating analysis report for directory: {directory}")
    logger.debug(f"File list for analysis: {file_list}")
    
    report = "Code Analysis Report\n=====================\n\n"
    
    categorized_files = categorize_files(file_list)
    report += "File Categorization:\n"
    for category, files in categorized_files.items():
        report += f"{category}:\n"
        for file in sorted(files):
            report += f"  - {file}\n"
    report += "\n"
    
    dependencies = analyze_dependencies(directory, file_list)
    report += "Dependencies:\n"
    for dep in dependencies:
        report += f"  - {dep}\n"
    report += "\n"
    
    todos = find_todos(directory, file_list)
    report += "TODO Items:\n"
    for todo in todos:
        report += f"  - {todo}\n"
    report += "\n"
    
    env_vars = find_env_variables(directory, file_list)
    report += "Environment Variables:\n"
    for var in env_vars:
        report += f"  - {var}\n"
    report += "\n"
    
    makefile_path = os.path.join(directory, 'Makefile')
    if os.path.exists(makefile_path):
        makefile_targets = analyze_makefile(makefile_path)
        report += "Makefile Targets:\n"
        for target in makefile_targets:
            report += f"  - {target}\n"
    report += "\n"
    
    folder_structure = explain_folder_structure(directory)
    report += "Folder Structure:\n"
    for folder, description in sorted(folder_structure.items()):
        report += f"  - {folder}: {description}\n"
    report += "\n"
    
    return report

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Bundle code files for analysis.")
    parser.add_argument("directory", nargs="?", default=os.getcwd(), help="Target directory to bundle (default: current directory)")
    parser.add_argument("--exclude", nargs="*", default=[], help="Additional patterns to exclude (files or folders)")
    parser.add_argument("--root-only", action="store_true", help="Only bundle files in the root directory and list subdirectories")
    parser.add_argument("--analyze", action="store_true", help="Generate an analysis report")
    
    args = parser.parse_args()
    
    bundle_files(args.directory, args.exclude, args.root_only, args.analyze)