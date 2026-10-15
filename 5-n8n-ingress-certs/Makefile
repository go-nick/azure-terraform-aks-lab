.PHONY: init plan apply destroy output

init:
	set -a && . ./.env && set +a && terraform init

plan:
	set -a && . ./.env && set +a && terraform plan

apply:
	set -a && . ./.env && set +a && terraform apply -target=azurerm_kubernetes_cluster.main --auto-approve
	set -a && . ./.env && set +a && terraform apply --auto-approve

destroy:
	set -a && . ./.env && set +a && terraform destroy

output:
	set -a && . ./.env && set +a && terraform output
