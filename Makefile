.PHONY: lint template schema unittest kyverno-test validate check-digests

FIND_CHARTS = find infrastructure applications -type f -name Chart.yaml -exec dirname {} \;
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
	@test_dirs=$$(find infrastructure applications -type d -name tests 2>/dev/null); \
	if [ -z "$$test_dirs" ]; then \
		echo "No tests found; skipping helm unittest"; \
	else \
		for dir in $$test_dirs; do \
			chart=$$(dirname $$dir); \
			helm unittest $$chart || exit 1; \
		done; \
	fi

kyverno-test:
	@test_dirs=$$(find infrastructure applications -type d -name kyverno-tests 2>/dev/null); \
	if [ -z "$$test_dirs" ]; then \
		echo "No kyverno-tests found; skipping"; \
	else \
		for dir in $$test_dirs; do \
			for run in $$dir/*/run.sh; do \
				echo "$$run"; \
				"$$run" || exit 1; \
			done; \
		done; \
	fi

validate: lint template schema unittest kyverno-test

check-digests:
	@./scripts/check-image-digests.sh
