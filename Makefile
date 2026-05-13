SHELL := /bin/bash

ROOT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
TASO_DIR := $(ROOT_DIR)/TASO
TASO_BUILD_DIR ?= $(TASO_DIR)/build
TENSAT_DIR := $(ROOT_DIR)/tensat
VENV_DIR ?= $(ROOT_DIR)/.venv
PYTHON ?= python3
JOBS ?= $(shell nproc)

.PHONY: compile compile.both compile.taso compile.tensat install.taso clean clean.both clean.taso clean.tensat setup setup.python setup.rust-check setup.system-check

compile: compile.both

compile.both: compile.taso compile.tensat

compile.taso:
	cmake -S $(TASO_DIR) -B $(TASO_BUILD_DIR)
	cmake --build $(TASO_BUILD_DIR) -j$(JOBS)

compile.tensat:
	cd $(TENSAT_DIR) && \
		RUSTFLAGS="-L native=$(TASO_BUILD_DIR) $(RUSTFLAGS)" \
		cargo build --release

install.taso: compile.taso
	cmake --install $(TASO_BUILD_DIR)

clean: clean.both

clean.both: clean.taso clean.tensat

clean.taso:
	cmake --build $(TASO_BUILD_DIR) --target clean

clean.tensat:
	cd $(TENSAT_DIR) && cargo clean

setup: setup.system-check setup.rust-check setup.python

setup.python:
	@test -x $(VENV_DIR)/bin/python || $(PYTHON) -m venv $(VENV_DIR)
	$(VENV_DIR)/bin/python -m pip install --upgrade pip setuptools wheel
	$(VENV_DIR)/bin/python -m pip install cython numpy onnx protobuf ortools
	cd $(TASO_DIR)/python && $(VENV_DIR)/bin/python -m pip install -e .

setup.rust-check:
	@command -v cargo >/dev/null || { echo "Missing cargo. Install Rust with rustup or your package manager."; exit 1; }
	@command -v rustc >/dev/null || { echo "Missing rustc. Install Rust with rustup or your package manager."; exit 1; }
	@cargo --version
	@rustc --version

setup.system-check:
	@missing=0; \
	check_cmd() { command -v "$$1" >/dev/null || { echo "Missing $$1"; missing=1; }; }; \
	check_cmd cmake; \
	check_cmd g++; \
	check_cmd nvcc; \
	check_cmd protoc; \
	check_cmd clang; \
	check_cmd llvm-config; \
	if ! ldconfig -p 2>/dev/null | grep -q libcudnn && \
	   [ ! -f /usr/include/cudnn.h ] && \
	   [ ! -f /usr/local/cuda/include/cudnn.h ]; then \
		echo "Missing cuDNN headers/libs"; \
		missing=1; \
	fi; \
	if [ "$$missing" -ne 0 ]; then \
		echo "Install the missing system dependencies, then rerun make setup."; \
		exit 1; \
	fi; \
	echo "System dependency check passed."
