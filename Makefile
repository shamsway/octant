GCP_VM_NAME := phil
GCP_ZONE := us-central1-a
GCP_PROJECT := octant-426722

.PHONY: run run-flush-cache lint check-env build-base-image provision-vms deploy-cluster deploy-haproxy remove-haproxy start-haproxy stop-haproxy restart-haproxy deploy-ceph deploy-volumes deploy-services destroy-services health-check capture-state deploy-vm teardown rebuild clear-secrets install-hashi-cli podman-cleanup shutdown snapshot start docs docs-publish

check-env:
ifeq ($(strip $(TAILSCALE_CLOUD_KEY)),)
	@echo "TAILSCALE_CLOUD_KEY environment variable is not set. Running 'direnv allow'..."
	@direnv allow
else
	@echo "TAILSCALE_CLOUD_KEY environment variable is set."
endif

check-vm:
	@echo "Checking if VM $(GCP_VM_NAME) is running..."
	@gcloud compute instances describe "$(GCP_VM_NAME)" --zone="$(GCP_ZONE)" --format='get(status)' | grep -q RUNNING && echo "VM $(GCP_VM_NAME) is running." || echo "VM $(GCP_VM_NAME) is not running."

start-vm:
	@echo "Starting VM $(GCP_VM_NAME)..."
	@gcloud compute instances start "$(GCP_VM_NAME)" --zone="$(GCP_ZONE)"

ensure-vm: check-vm
	@if ! gcloud compute instances describe $(GCP_VM_NAME) --zone=$(GCP_ZONE) --format='get(status)' | grep -q RUNNING; then \
		echo "VM $(GCP_VM_NAME) is not running. Starting it..."; \
		gcloud compute instances start $(GCP_VM_NAME) --zone=$(GCP_ZONE); \
	fi

ssh-gcp:
	gcloud compute ssh --zone "$(GCP_ZONE)" "$(GCP_VM_NAME)" --project "$(GCP_PROJECT)"

deploy: check-env
	ansible-playbook octant.yml -i inventory/groups.yml

deploy-verbose: check-env
	ansible-playbook -vvv octant.yml -i inventory/groups.yml

deploy-host: check-env
	ansible-playbook octant.yml $(VM_CLUSTER_INVENTORY) -l $(HOST)

deploy-role: check-env
	ansible-playbook octant.yml $(VM_CLUSTER_INVENTORY) --tags "$(ROLE)"

deploy-role-host: check-env
	ansible-playbook octant.yml $(VM_CLUSTER_INVENTORY) --tags "$(ROLE)" -l $(HOST)

update-nomad: check-env
	ansible-playbook update-nomad.yml -i inventory/groups.yml -l $(HOST)

update-consul-configs: check-env
	ansible-playbook update-consul-configs.yml -i inventory/groups.yml

update-nomad-configs: check-env
	ansible-playbook update-nomad-configs.yml -i inventory/groups.yml

reset-consul: check-env
	ansible-playbook reset-consul.yml -i inventory/groups.yml

reset-nomad: check-env
	ansible-playbook reset-nomad.yml -i inventory/groups.yml

run-flush-cache: check-env
	ansible-playbook octant.yml -i inventory/groups.yml --flush-cache

start-consul: check-env
	ansible-playbook start-consul.yml -i inventory/groups.yml

start-consul-host: check-env
	ansible-playbook start-consul.yml -i inventory/groups.yml -l $(HOST)

start-nomad: check-env
	ansible-playbook start-nomad.yml -i inventory/groups.yml

start-nomad-host: check-env
	ansible-playbook start-nomad.yml -i inventory/groups.yml -l $(HOST)

stop-consul: check-env
	ansible-playbook stop-consul.yml -i inventory/groups.yml

stop-consul-host: check-env
	ansible-playbook stop-consul.yml -i inventory/groups.yml -l $(HOST)

stop-nomad: check-env
	ansible-playbook stop-nomad.yml -i inventory/groups.yml

stop-nomad-host: check-env
	ansible-playbook stop-nomad.yml -i inventory/groups.yml -l $(HOST)

tf-apply-gcp:
	cd terraform/gcp ; terraform apply -auto-approve

tf-destroy-gcp:
	cd terraform/gcp ; terraform destroy -auto-approve

tf-update-dns:
	cd terraform/dns ; terraform apply -auto-approve

tf-update-dns-lab:
	cd terraform/dns-lab ; terraform init -upgrade && terraform apply -auto-approve

tf-destroy-dns-lab:
	cd terraform/dns-lab ; terraform destroy -auto-approve

reset-server:
	ansible-playbook reset-server.yml -i inventory/groups.yml



lint:
	find . -type f -name '*.yml' -exec ansible-lint --fix {} +

# --- VM Deployment ---
VM_INVENTORY := -i inventory/hypervisors.yml -i inventory/groups.yml
VM_CLUSTER_INVENTORY := -i inventory/provisioned_vms.yml -i inventory/groups.yml

build-base-image:
	ansible-playbook playbooks/00-build-base-image.yml -i inventory/hypervisors.yml

provision-vms:
	ansible-playbook playbooks/01-provision-vms.yml $(VM_INVENTORY)

deploy-cluster:
	ansible-playbook octant.yml $(VM_CLUSTER_INVENTORY)

deploy-haproxy:
	ansible-playbook playbooks/02.5-deploy-haproxy.yml $(VM_INVENTORY)

remove-haproxy:
	ansible-playbook playbooks/02.5-remove-haproxy.yml -i inventory/hypervisors.yml

stop-haproxy:
	ansible -i inventory/hypervisors.yml hypervisors -b -m systemd -a "name=haproxy state=stopped"

start-haproxy:
	ansible -i inventory/hypervisors.yml hypervisors -b -m systemd -a "name=haproxy state=started"

restart-haproxy:
	ansible -i inventory/hypervisors.yml hypervisors -b -m systemd -a "name=haproxy state=restarted"

deploy-ceph:
	ansible-playbook playbooks/02-deploy-ceph.yml $(VM_CLUSTER_INVENTORY)

deploy-volumes:
	ansible-playbook playbooks/05-deploy-volumes.yml $(VM_CLUSTER_INVENTORY)

deploy-services:
	ansible-playbook playbooks/03-deploy-services.yml $(VM_CLUSTER_INVENTORY)

destroy-services:
	ansible-playbook playbooks/06-destroy-services.yml $(VM_CLUSTER_INVENTORY)

seed-secrets:
	ansible-playbook playbooks/03-deploy-services.yml $(VM_CLUSTER_INVENTORY) --tags "seed-onepassword"

health-check:
	ansible-playbook playbooks/04-health-check.yml $(VM_CLUSTER_INVENTORY)

capture-state:
	ansible-playbook playbooks/07-capture-state.yml $(VM_CLUSTER_INVENTORY)

fresh-deploy: build-base-image provision-vms deploy-cluster deploy-ceph deploy-haproxy deploy-services health-check capture-state

deploy: provision-vms deploy-cluster deploy-ceph deploy-haproxy deploy-services health-check capture-state

teardown: remove-haproxy
	ansible-playbook playbooks/99-teardown.yml $(VM_INVENTORY)

teardown-force: remove-haproxy
	ansible-playbook playbooks/99-teardown.yml $(VM_INVENTORY) -e auto_approve=true

clear-secrets:
	./scripts/clear-vault-secrets.sh

clear-secrets-force:
	./scripts/clear-vault-secrets.sh --force

rebuild: teardown-force deploy-vm

rebuild-clean: clear-secrets-force teardown-force deploy-vm

install-hashi-cli:
	ansible-playbook playbooks/install-hashi-cli.yml -i inventory/hypervisors.yml

join-hypervisor: ## Install Consul/Nomad agents on hypervisor and join VM cluster
	ansible-playbook -i inventory/hypervisors.yml -i inventory/groups.yml playbooks/11-join-hypervisor.yml $(ANSIBLE_ARGS)

remove-hypervisor: ## Stop and clean up Consul/Nomad agents on hypervisor
	ansible-playbook -i inventory/hypervisors.yml playbooks/12-remove-hypervisor.yml $(ANSIBLE_ARGS)

podman-cleanup:
	ansible-playbook playbooks/podman-cleanup.yml $(VM_CLUSTER_INVENTORY)

# --- Cluster Lifecycle ---
shutdown:
	ansible-playbook playbooks/08-graceful-shutdown.yml $(VM_CLUSTER_INVENTORY) $(ARGS)

snapshot:
	ansible-playbook playbooks/09-snapshot-cluster.yml -i inventory/hypervisors.yml -i inventory/groups.yml $(ARGS)

start:
	ansible-playbook playbooks/10-cluster-start.yml $(VM_CLUSTER_INVENTORY) -i inventory/hypervisors.yml $(ARGS)

# --- Documentation ---
DOCS_SRC := docs/sphinx
DOCS_BUILD := $(DOCS_SRC)/_build/html
DOCS_HOST := admin@192.168.122.102
DOCS_DEST := /mnt/services/nginx/html

docs:
	sphinx-build -b html $(DOCS_SRC) $(DOCS_BUILD)

docs-publish: docs
	ssh $(DOCS_HOST) "sudo rm -rf $(DOCS_DEST)/docs && sudo mkdir -p $(DOCS_DEST)/docs && sudo chown admin:hashi $(DOCS_DEST)/docs"
	scp -r $(DOCS_BUILD)/* $(DOCS_HOST):$(DOCS_DEST)/docs/
	ssh $(DOCS_HOST) "sudo install -m 644 /dev/stdin $(DOCS_DEST)/index.html" < docs/index.html
