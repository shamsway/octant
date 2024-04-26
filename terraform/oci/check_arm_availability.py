import sys
import json
import oci
import logging


# Set up logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

def check_availability(config, shape, max_instances):
    # Create OCI clients
    compute_client = oci.core.ComputeClient(config)
    identity_client = oci.identity.IdentityClient(config)

    # Call ListAvailabilityDomains OCI API method
    logging.info("Calling ListAvailabilityDomains OCI API method...")
    availability_domains = oci.pagination.list_call_get_all_results(
        identity_client.list_availability_domains,
        compartment_id=config['tenancy']
    ).data
    logging.info(f"Found {len(availability_domains)} availability domains.")

    # Call ListInstances OCI API method
    logging.info("Calling ListInstances OCI API method...")
    instances = oci.pagination.list_call_get_all_results(
        compute_client.list_instances,
        compartment_id=config['tenancy']
    ).data
    logging.info(f"Found {len(instances)} instances.")

    # Filter instances based on shape and count
    existing_instances = [instance for instance in instances if instance.shape == shape]
    logging.info(f"Found {len(existing_instances)} existing instances with shape {shape}.")

    if len(existing_instances) >= max_instances:
        logging.info(f"Already have {len(existing_instances)} instances with shape {shape}.")
        return None

    # Find an available domain
    for domain in availability_domains:
        domain_instances = [instance for instance in existing_instances if instance.availability_domain == domain.name]
        if len(domain_instances) < max_instances:
            logging.info(f"Found available domain: {domain.name}")
            return domain.name

    logging.info("No available domains found.")
    return None

def main():
    # Read input variables from stdin
    input_vars = json.load(sys.stdin)
    shape = input_vars['shape']
    max_instances = int(input_vars['max_instances'])

    # Set up OCI configuration
    config = oci.config.from_file()

    # Check availability
    availability_domain = check_availability(config, shape, max_instances)

    if availability_domain:
        logging.info(f"Availability found in domain: {availability_domain}")
        # Output the result as JSON to stdout
        result = {'availability_domain': availability_domain}
        print(json.dumps(result))
    else:
        logging.info("No availability found.")
        # Output an empty result
        print(json.dumps({}))

if __name__ == "__main__":
    main()