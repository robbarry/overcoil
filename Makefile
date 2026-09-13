# Override APPLE_ENV to use another authorized credential-reference file.
APPLE_ENV ?= $(HOME)/Sync/repos/tank2/ios/.env

.PHONY: setup generate simulator device archive apple-status
setup:
	uv sync --locked

generate:
	xcodegen generate --spec ios/project.yml

simulator:
	uv run --locked scripts/apple.py simulator

device:
	uv run --locked scripts/apple.py device --env-file "$(APPLE_ENV)"

archive:
	uv run --locked scripts/apple.py archive --env-file "$(APPLE_ENV)"

apple-status:
	uv run --locked scripts/apple.py status --env-file "$(APPLE_ENV)"
