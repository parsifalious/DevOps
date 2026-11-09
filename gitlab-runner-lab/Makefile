
.PHONY: help install register status logs cleanup

help:
	@echo "Available targets:"
	@echo "  make install              Install GitLab Runner"
	@echo "  make register GROUP_URL=  Register group runner"
	@echo "  make status               Show runner status"
	@echo "  make logs                 Show runner logs"
	@echo "  make cleanup              Remove runner resources"
	@echo "Registration requires GITLAB_TOKEN."

install:
	./install_gitlab_runner.sh

register:
	@test -n "$(GROUP_URL)" || (echo "GROUP_URL is required"; exit 1)
	./register_gitlab_runner.sh "$(GROUP_URL)"

status:
	sudo docker ps -a --filter "name=^/gitlab-runner-lab$$"

logs:
	sudo docker logs --tail 50 gitlab-runner-lab

cleanup:
	./cleanup.sh
