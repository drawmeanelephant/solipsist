# Solipsist — convenience targets.
#
# XcodeGen is vendored into .tools/ (project-local, no system install).
# The Boris engine checkout must exist at ../boris (see scripts/embed-boris.sh).

XCODEGEN := .tools/xcodegen/xcodegen/bin/xcodegen
PROJECT  := Solipsist.xcodeproj

.PHONY: tools generate build spike run-spike test harvest-fixtures clean fart

tools:
	@mkdir -p .tools
	@if [ ! -x "$(XCODEGEN)" ]; then \
		echo "==> Vendoring XcodeGen 2.46.0 into .tools/"; \
		curl -sL -o /tmp/xcodegen.zip \
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

harvest-fixtures:
	bash scripts/harvest-stunt-fixtures.sh

clean:
	rm -rf build Solipsist.xcodeproj

# Reserved. Do not implement.
fart:
	@echo "the fart app is not a thing yet"; exit 1
