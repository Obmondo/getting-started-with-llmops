OLLAMA_OPERATOR_VERSION := v0.10.10

dist/ollama-operator/$(OLLAMA_OPERATOR_VERSION).yaml:
	mkdir -p $(@D)
	curl -sfL -o $@ \
		https://raw.githubusercontent.com/nekomeowww/ollama-operator/$(OLLAMA_OPERATOR_VERSION)/dist/install.yaml

render: dist/ollama-operator/$(OLLAMA_OPERATOR_VERSION).yaml
	rm -rf renderred
	tk export ./renderred/ ./environments/ \
		--recursive \
		--format "{{env.metadata.name}}/{{(index .metadata.labels \"app.tanka.grafana.com\")}}/{{.kind}}/{{.metadata.name}}"
