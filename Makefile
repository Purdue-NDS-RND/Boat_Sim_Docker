.PHONY: run build rebuild validate smoke down logs

run:
	./run.sh

build:
	./run.sh --build-only

rebuild:
	./run.sh --rebuild-only

validate:
	./validate.sh

smoke:
	./smoke.sh

down:
	./run.sh --down

logs:
	docker compose -f compose.yaml logs -f simulator
