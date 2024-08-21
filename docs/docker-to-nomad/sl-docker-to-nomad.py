# export ANTHROPIC_API_KEY=your_api_key_here

import sys
import logging
import yaml
from jinja2 import Environment, FileSystemLoader
import streamlit as st
from anthropic import Anthropic
from ollama import Client

logging.basicConfig(stream=sys.stdout, level=logging.DEBUG)
logger = logging.getLogger(__name__)


def convert_docker_compose_to_nomad(docker_compose_content):
    client = Anthropic()
    
    #print("Anthropic object attributes:")
    #print(dir(client))
    
    with open("nomad-job-template.hcl.j2", "r") as f:
        job_template = f.read()
    f.close()

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

    Use this jinja template as an example for default values and general structure

    ```jinja
    {job_template}
    ```
    """

    response = client.messages.create(
        model="claude-3-5-sonnet-20240620",
        max_tokens=2048,
        messages=[
            {"role": "user", "content": prompt}
        ],
    )

    return response.content[0].text

def ollama_convert_docker_compose_to_nomad(docker_compose_content):
    ollama_client = Client(host='http://ollama.service.consul:11434')
    
    with open("nomad-job-template.hcl.j2", "r") as f:
        job_template = f.read()
    f.close()

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

    Use this jinja template as an example for default values and general structure

    ```jinja
    {job_template}
    ```
    """

    response = ollama_client.chat(
        model='llama3-gradient', 
        messages=[{'role': 'user', 'content': prompt}]
    )

    return response['message']['content']

def convert_locally(docker_compose_content):
    docker_compose = yaml.safe_load(docker_compose_content)

    env = Environment(loader=FileSystemLoader('.'))
    template = env.get_template('nomad-job-template.hcl.j2')

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

    #api_key = st.text_input("Enter your Anthropic API key:")
    docker_compose_content = st.text_area("Enter your Docker Compose YAML:", height=300)

    if st.button("Convert using Claude API"):
        if docker_compose_content:
            nomad_job = convert_docker_compose_to_nomad(docker_compose_content)
            st.markdown(nomad_job)
        else:
            st.warning("Please provide Docker Compose YAML.")

    if st.button("Convert using Ollama"):
        if docker_compose_content:
            nomad_job = ollama_convert_docker_compose_to_nomad(docker_compose_content)
            st.markdown(nomad_job)
        else:
            st.warning("Please provide Docker Compose YAML.")

    if st.button("Convert Locally"):
        if docker_compose_content:
            nomad_job = convert_locally(docker_compose_content)
            st.code(nomad_job, language='hcl')
        else:
            st.warning("Please provide Docker Compose YAML.")

if __name__ == '__main__':
    main()