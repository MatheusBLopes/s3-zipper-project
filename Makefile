SHELL := /bin/bash
.ONESHELL:

export $(shell sed 's/=.*//' .env 2>/dev/null)

PY := python3
BUILD_DIR := build

.PHONY: build clean tf-init tf-apply tf-destroy package

build: clean
	mkdir -p $(BUILD_DIR)
	# Enqueue (sem deps externas)
	cd lambdas/enqueue && zip -r ../../$(BUILD_DIR)/lambda_enqueue.zip . -x "__pycache__/*"
	# Status (sem deps externas)
	cd lambdas/status && zip -r ../../$(BUILD_DIR)/lambda_status.zip . -x "__pycache__/*"
	# Zipper (com deps zipstream-ng)
	cd lambdas/zipper
	rm -rf .python
	$(PY) -m venv .python
	source .python/bin/activate
	pip install --upgrade pip
	pip install -r requirements.txt -t python
	deactivate
	zip -r ../../$(BUILD_DIR)/lambda_zipper.zip python handler.py -x "python/__pycache__/*"
	rm -rf python .python

tf-init:
	cd infra && terraform init

tf-apply:
	cd infra && terraform apply -auto-approve

tf-destroy:
	cd infra && terraform destroy -auto-approve

clean:
	rm -rf $(BUILD_DIR)

package: build
	@echo "Pacotes prontos em $(BUILD_DIR)/"
