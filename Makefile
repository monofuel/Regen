IMAGE = gitea.solution-nine.monofuel.dev/monofuel/regen

.PHONY: test integration-test e2e-test build

test:
	@echo "no tests configured"

integration-test:
	@echo "no integration tests configured"

e2e-test:
	@echo "no e2e tests configured"

build:
	@echo "no build configured"

.PHONY: docker-build
docker-build:
	docker buildx build \
	--platform linux/amd64 \
	--tag $(IMAGE)/regen:latest \
	-f Dockerfile .

.PHONY: docker-push
docker-push:
	docker buildx build \
	--platform linux/amd64 \
	--push \
	--tag $(IMAGE)/regen:latest \
	-f Dockerfile .


