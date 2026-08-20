.PHONY: lint template schema unittest validate

FIND_CHARTS = find infrastructure applications charts -type f -name Chart.yaml -exec dirname {} \;
HELM_SET = --set image.tag=ci

lint:
	yamllint .
	@for chart in $$($(FIND_CHARTS)); do \
		echo "helm lint $$chart"; \
		helm lint $$chart $(HELM_SET) || exit 1; \
	done

template:
	@for chart in $$($(FIND_CHARTS)); do \
		name=$$(basename $$chart); \
		echo "helm template $$name $$chart"; \
		helm template $$name $$chart $(HELM_SET) >/dev/null || exit 1; \
	done

schema:
	@for chart in $$($(FIND_CHARTS)); do \
		name=$$(basename $$chart); \
		echo "kubeconform $$chart"; \
		helm template $$name $$chart $(HELM_SET) | kubeconform -strict -summary -ignore-missing-schemas || exit 1; \
	done

unittest:
	@charts=$$(find charts -type f -name Chart.yaml -exec dirname {} \;); \
	if [ -z "$$charts" ]; then \
		echo "No charts under charts/; skipping helm unittest"; \
	else \
		helm unittest $$charts; \
	fi

validate: lint template schema unittest
