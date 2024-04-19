GCP_VM_NAME := phil
GCP_ZONE := us-central1-a
GCP_PROJECT := shamsway

.PHONY: run run-flush-cache lint check-env

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
	ansible-playbook homelab.yml -i inventory/groups.yml

deploy-verbose: check-env
	ansible-playbook -vvv homelab.yml -i inventory/groups.yml

deploy-host: check-env
	ansible-playbook homelab.yml -i inventory/groups.yml -l $(HOST)

deploy-role: check-env
	ansible-playbook homelab.yml -i inventory/groups.yml --tags "$(ROLE)"

update-mounts: check-env
	ansible-playbook configure-mounts.yml -i inventory/groups.yml

update-nomad: check-env
	ansible-playbook update-nomad.yml -i inventory/groups.yml -l $(HOST)

run-flush-cache: check-env
	ansible-playbook homelab.yml -i inventory/groups.yml --flush-cache

tf-apply-gcp: 
	cd terraform/gcp ; terraform apply -auto-approve

tf-destroy-gcp: 
	cd terraform/gcp ; terraform destroy -auto-approve

tf-update-dns: 
	cd terraform/dns ; terraform apply -auto-approve

reset-server:
	ansible-playbook reset-server.yml -i inventory/groups.yml

lint:
	find . -type f -name '*.yml' -exec ansible-lint --fix {} +