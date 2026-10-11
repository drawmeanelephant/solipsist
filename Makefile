# Solipsist — convenience targets.
#
# XcodeGen is vendored into .tools/ (project-local, no system install).
# Engine sources: boris + oliver checkouts. The embed script resolves them via
# BORIS_REPO_DIR / OLIVER_REPO_DIR (required from worktrees), derives the boris
# repo from SOLIPSIST_BORIS_BIN inside a checkout, then sibling fallbacks
# (see scripts/embed-boris.sh). It bundles boris, boris-editor + editor-ui,
# and oliver into Resources/ — a missing piece fails the build.

XCODEGEN := .tools/xcodegen/xcodegen/bin/xcodegen
PROJECT  := Solipsist.xcodeproj
# Empty SPIKE_CONTENT = spike default ../boris/content.
SPIKE_CONTENT ?=
SPIKE_PAGE ?=

.PHONY: tools generate build install-app spike run-spike test-spike test test-doctor lint doctor harvest-fixtures site check-site editor-ui clean fart

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

# Siri / Spotlight only register App Intents for apps they index — the
# Xcode build folder is not it. Install into /Applications and launch
# once so siriactionsd picks up Metadata.appintents.
#
# The product is deleted BEFORE building: the embed phase writes into
# Resources on every build, and an incremental xcodebuild will happily
# leave those files outside the code signature ("file added" seal
# errors). A fresh product directory forces a complete signing pass.
install-app:
	rm -rf /Applications/Solipsist.app
	rm -rf build/Build/Products/Debug/Solipsist.app
	$(MAKE) build
	ditto build/Build/Products/Debug/Solipsist.app /Applications/Solipsist.app
	open /Applications/Solipsist.app

spike: generate
	xcodebuild -project $(PROJECT) -scheme spike -configuration Debug \
		-derivedDataPath build build

run-spike: spike
	build/Build/Products/Debug/boris-spike $(if $(SPIKE_CONTENT),"$(SPIKE_CONTENT)",$(if $(SPIKE_PAGE),"../boris/content")) $(if $(SPIKE_PAGE),"$(SPIKE_PAGE)")

test-spike: spike
	python3 -B -m unittest discover -s Tests/Spike -p 'test_*.py' -v

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

# Environment + repo-hygiene check. Safe to run anywhere (Linux included);
# macOS-only checks are skipped off-Mac.
doctor:
	bash scripts/doctor.sh

test-doctor:
	python3 -B -m unittest discover -s Tests/Doctor -p 'test_*.py' -v

harvest-fixtures:
	bash scripts/harvest-stunt-fixtures.sh

# Builds the compiled editor shell (editor/ui/dist) inside the resolved
# boris checkout so `make build` can bundle it. Needs node + npm; the embed
# script deliberately never runs this — run it after touching editor/ui/src.
editor-ui:
	bash scripts/build-editor-ui.sh

# SITE_FLAGS are gone: site/boris.json declares the layout rule, sitemap,
# site URL, and static dir itself, and `build --profile` executes them
# (boris ≥ 0.8.2, profile-driven HTML execution). Passing the old explicit
# selectors now hits the consistency-check refusal — don't re-add them.
site:
	@SITE_BORIS=""; \
	if [ -n "$$SOLIPSIST_BORIS_BIN" ] && [ -x "$$SOLIPSIST_BORIS_BIN" ]; then \
		SITE_BORIS="$$SOLIPSIST_BORIS_BIN"; \
	elif [ -n "$$BORIS_REPO_DIR" ] && [ -x "$$BORIS_REPO_DIR/zig-out/bin/boris" ]; then \
		SITE_BORIS="$$BORIS_REPO_DIR/zig-out/bin/boris"; \
	elif [ -x "../boris/zig-out/bin/boris" ]; then \
		SITE_BORIS="../boris/zig-out/bin/boris"; \
	fi; \
	if [ -z "$$SITE_BORIS" ]; then \
		echo "error: boris binary not found. Set SOLIPSIST_BORIS_BIN or build ../boris" >&2; \
		echo "(PATH boris is deliberately not used — the site's profile" >&2; \
		echo " semantics must come from a verified engine; see vendor/boris-agent-kit/MANIFEST.json)" >&2; \
		exit 1; \
	fi; \
	SITE_REV="$$("$$SITE_BORIS" --build-info 2>/dev/null | sed -n 's/.*"vcsRevision": *"\([^"]*\)".*/\1/p')"; \
	PIN_REV="$$(sed -n 's/.*"vcs_revision": *"\([^"]*\)".*/\1/p' vendor/boris-agent-kit/MANIFEST.json)"; \
	if [ -n "$$SITE_REV" ] && [ -n "$$PIN_REV" ] && [ "$$SITE_REV" != "$$PIN_REV" ]; then \
		echo "warn: site engine vcsRevision $$SITE_REV != pin $$PIN_REV — output may drift" >&2; \
	fi; \
	(cd site && "$$SITE_BORIS" build --profile boris.json)

check-site: site
	python3 scripts/check-site-links.py --root site/dist --base-url https://solipsist.filed.fyi

clean:
	rm -rf build Solipsist.xcodeproj

# Reserved. Do not implement.
fart:
	@echo "the fart app is not a thing yet"; exit 1
