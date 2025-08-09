IMAGE = gitea.solution-nine.monofuel.dev/monofuel/regen

.PHONY: docker-build
docker-build:
	docker buildx build \
	--platform linux/amd64 \
	--tag $(IMAGE):latest \
	-f Dockerfile .

.PHONY: docker-push
docker-push:
	docker buildx build \
	--platform linux/amd64 \
	--push \
	--tag $(IMAGE):latest \
	-f Dockerfile .


