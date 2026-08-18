# Solipsist — convenience targets.
#
# XcodeGen is vendored into .tools/ (project-local, no system install).
# The Boris engine checkout must exist at ../boris (see scripts/embed-boris.sh).

XCODEGEN := .tools/xcodegen/xcodegen/bin/xcodegen
PROJECT  := Solipsist.xcodeproj

.PHONY: tools generate build spike run-spike test lint harvest-fixtures site check-site clean fart

tools:
	@mkdir -p .tools
	@if [ ! -x "$(XCODEGEN)" ]; then \
		echo "==> Vendoring XcodeGen 2.46.0 into .tools/"; \
		/usr/bin/curl -sL -o /tmp/xcodegen.zip \
			https://github.com/yonaskolb/XcodeGen/releases/download/2.46.0/xcodegen.zip && \
		rm -rf .tools/xcodegen && unzip -q /tmp/xcodegen.zip -d .tools/xcodegen && \
		"$(XCODEGEN)" --version; \
	else \
		echo "==> XcodeGen already vendored"; \
	fi

generate: tools
	"$(XCODEGEN)" generate

build: generate
	xcodebuild -project $(PROJECT) -scheme Solipsist -configuration Debug \
		-derivedDataPath build build

spike: generate
	xcodebuild -project $(PROJECT) -scheme spike -configuration Debug \
		-derivedDataPath build build

run-spike: spike
	build/Build/Products/Debug/boris-spike

test: generate
	xcodebuild -project $(PROJECT) -scheme ContractTests -configuration Debug \
		-derivedDataPath build -destination 'platform=macOS' test

lint:
	@missing=""; \
	if ! command -v swiftformat >/dev/null 2>&1; then missing="$$missing swiftformat"; fi; \
	if ! command -v swiftlint >/dev/null 2>&1; then missing="$$missing swiftlint"; fi; \
	if [ -n "$$missing" ]; then \
		echo "error: missing required lint tool(s):$$missing. Install with: brew install swiftformat swiftlint" >&2; \
		exit 1; \
	fi; \
	echo "==> Running SwiftFormat"; \
	swiftformat --lint . && \
	echo "==> Running SwiftLint" && \
	swiftlint --strict

harvest-fixtures:
	bash scripts/harvest-stunt-fixtures.sh

# SITE_FLAGS mirror the deploy-site.yml workflow: the single public target is
# synthesized as "default", the home layout is selected per-page, and
# --site-url feeds sitemap.xml.
SITE_FLAGS := --layout-rule default id:index themes/boris/layouts/home.html --sitemap --site-url https://solipsist.filed.fyi

site:
	@if [ -n "$$SOLIPSIST_BORIS_BIN" ] && [ -x "$$SOLIPSIST_BORIS_BIN" ]; then \
		(cd site && "$$SOLIPSIST_BORIS_BIN" build --profile boris.json $(SITE_FLAGS)); \
	elif [ -x "../boris/zig-out/bin/boris" ]; then \
		(cd site && ../boris/zig-out/bin/boris build --profile boris.json $(SITE_FLAGS)); \
	elif command -v boris >/dev/null 2>&1; then \
		(cd site && boris build --profile boris.json $(SITE_FLAGS)); \
	else \
		echo "error: boris binary not found. Set SOLIPSIST_BORIS_BIN or build ../boris" >&2; \
		exit 1; \
	fi

check-site: site
	cp site/robots.txt site/dist/robots.txt
	python3 scripts/check-site-links.py --root site/dist --base-url https://solipsist.filed.fyi

clean:
	rm -rf build Solipsist.xcodeproj

# Reserved. Do not implement.
fart:
	@echo "the fart app is not a thing yet"; exit 1
