import yaml
import csv
import ansible_runner
import argparse
import logging

def update_groups_yml(csv_file, groups_yml):
    # Configure logging
    logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

    # Read the existing groups.yml file
    with open(groups_yml, 'r') as file:
        data = yaml.safe_load(file)

    # Read the volumes from the CSV file
    with open(csv_file, 'r') as file:
        reader = csv.DictReader(file)
        volumes = list(reader)

    # Check if the volumes key exists in the data
    if 'volumes' not in data['servers']['vars']:
        logging.info("Creating 'volumes' key in groups.yml")
        data['servers']['vars']['volumes'] = []

    # Open the groups.yml file in append mode
    with open(groups_yml, 'a') as file:
        # Iterate over the volumes from the CSV file
        for volume in volumes:
            # Check if the volume is already defined in groups.yml
            volume_exists = any(
                v['name'] == volume['name']
                for v in data['servers']['vars']['volumes']
            )

            # If the volume doesn't exist, append it to groups.yml
            if not volume_exists:
                logging.info(f"Adding volume '{volume['name']}' to groups.yml")
                file.write(f"\n      - name: {volume['name']}")
                file.write(f"\n        path: {volume['path']}")
                file.write(f"\n        backup: {volume['backup']}")
            else:
                logging.info(f"Volume '{volume['name']}' already exists in groups.yml")

    logging.info("Updated groups.yml successfully")

def run_ansible_playbook(playbook, inventory):
    # Run the Ansible playbook using ansible_runner.run_command()
    ansible_runner.run_command(
        executable_cmd='ansible-playbook',
        cmdline_args=[playbook, '-i', inventory],
    )

def main(args):
    # Update groups.yml with volumes from the CSV file
    update_groups_yml('volumes.csv', 'inventory/groups.yml')

    # Run the configure-mounts.yml playbook
    run_ansible_playbook('update-nfs-mounts.yml', 'inventory/groups.yml')

    # Run the update-nomad playbooks based on the provided arguments
    if args.rootless_agents or args.all:
        logging.info('Updating rootless Nomad agents...')
        run_ansible_playbook('update-nomad-agents.yml', 'inventory/groups.yml')
        logging.info('Rootless Nomad agents updated successfully.')

    if args.root_agents or args.all:
        logging.info('Updating root Nomad agents...')
        run_ansible_playbook('update-nomad-root-agents.yml', 'inventory/groups.yml')
        logging.info('Root Nomad agents updated successfully.')

    if not any([args.rootless_agents, args.root_agents, args.all]):
        logging.info('No specific agents selected. Please use --rootless-agents, --root-agents, or --all to specify the agents to update.')

if __name__ == '__main__':
    # Configure logging
    logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

    # Parse command-line arguments
    parser = argparse.ArgumentParser(description='Update Nomad agents using Ansible playbooks.')
    parser.add_argument('--rootless-agents', action='store_true', help='Update rootless Nomad agents')
    parser.add_argument('--root-agents', action='store_true', help='Update root Nomad agents')
    parser.add_argument('--all', action='store_true', help='Update both rootless and root Nomad agents')

    args = parser.parse_args()

    main(args)