.PHONY: new-project

new-project:
	@read -p "New project name: " name; \
	./scripts/new-project.sh "$$name"
