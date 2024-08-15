import yaml
from jinja2 import Environment, FileSystemLoader

def convert_docker_compose_to_nomad(docker_compose_file, output_file):
    with open(docker_compose_file, 'r') as file:
        docker_compose = yaml.safe_load(file)

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

    with open(output_file, 'w') as file:
        file.write(nomad_job)

if __name__ == '__main__':
    docker_compose_file = 'docker-compose.yml'
    output_file = 'nomad_job.hcl'
    convert_docker_compose_to_nomad(docker_compose_file, output_file)