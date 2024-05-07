import streamlit as st
import yaml
from jinja2 import Environment, FileSystemLoader
import requests

def convert_docker_compose_to_nomad(docker_compose_content, api_key):
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {api_key}"
    }

    prompt = f"""
    Please convert the following docker-compose YAML to a Nomad job configuration:

    ```yaml
    {docker_compose_content}
    ```

    Consider the following requirements:
    - Use Podman for running the containers.
    - Map the services to corresponding Nomad job tasks.
    - Handle volumes, ports, and environment variables appropriately.
    - Define appropriate job-level settings, such as job name, datacenters, and constraints.
    - Add Traefik tags for each service, including the job-specific hostname and other required tags.
    - Mount volumes exposed to Nomad properly using the 'volume' block in the job definition and 'volume_mount' within the task block.
    - Set the 'provider' to "consul" in the service definition and configure a health check with a default path of "/".
    - Ensure the output follows the general structure of the provided example.

    Please provide the converted Nomad job configuration in HCL format.
    Provide podman commands to run the container from the command line to verify it works when running rootless.
    """

    data = {
        "prompt": prompt,
        "max_tokens_to_sample": 2048,
        "stop_sequences": ["\n\n"]
    }

    response = requests.post("https://api.anthropic.com/v1/complete", headers=headers, json=data)
    response.raise_for_status()

    return response.json()["completion"]

def convert_locally(docker_compose_content):
    docker_compose = yaml.safe_load(docker_compose_content)

    env = Environment(loader=FileSystemLoader('.'))
    template = env.get_template('nomad_job_template.hcl')

    services = []
    for service_name, service_config in docker_compose['services'].items():
        service = {
            'name': service_name,
            'image': service_config['image'],
            'ports': service_config.get('ports', []),
            'volumes': service_config.get('volumes', []),
            'environment': service_config.get('environment', []),
        }
        services.append(service)

    nomad_job = template.render(services=services)
    return nomad_job

def main():
    st.title("Docker Compose to Nomad Converter")

    api_key = st.text_input("Enter your Claude API key:")
    docker_compose_content = st.text_area("Enter your Docker Compose YAML:", height=300)

    if st.button("Convert using Claude API"):
        if api_key and docker_compose_content:
            nomad_job = convert_docker_compose_to_nomad(docker_compose_content, api_key)
            st.code(nomad_job, language='hcl')
        else:
            st.warning("Please provide both API key and Docker Compose YAML.")

    if st.button("Convert Locally"):
        if docker_compose_content:
            nomad_job = convert_locally(docker_compose_content)
            st.code(nomad_job, language='hcl')
        else:
            st.warning("Please provide Docker Compose YAML.")

if __name__ == '__main__':
    main()