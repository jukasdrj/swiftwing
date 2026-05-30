.PHONY: help build clean-build test-ui update-spec update-spec-force format lint status

SCHEME=swiftwing
WORKSPACE=swiftwing.xcodeproj
DESTINATION="platform=iOS Simulator,name=iPhone 17 Pro Max"
SDK=iphonesimulator

help:
	@echo "SwiftWing iOS Book Scanner App - Makefile"
	@echo "========================================="
	@echo "build             - Build for simulator and parse output via xcsift"
	@echo "clean-build       - Clean and build for simulator"
	@echo "test-ui           - Run UI tests with parallel testing disabled (using xcsift)"
	@echo "update-spec       - Check and update OpenAPI spec (checksum validation)"
	@echo "update-spec-force - Force update OpenAPI spec (bypasses checksum)"
	@echo "format            - Format Swift code (using swiftformat)"
	@echo "lint              - Lint Swift code (using swiftlint)"
	@echo "status            - Check project status via Ralph TUI"

build:
	xcodebuild -project $(WORKSPACE) -scheme $(SCHEME) \
	  -sdk $(SDK) \
	  -destination $(DESTINATION) \
	  build 2>&1 | xcsift

clean-build:
	xcodebuild -project $(WORKSPACE) -scheme $(SCHEME) \
	  -sdk $(SDK) \
	  -destination $(DESTINATION) \
	  clean build 2>&1 | xcsift

test-ui:
	xcodebuild test -project $(WORKSPACE) -scheme $(SCHEME) \
	  -sdk $(SDK) \
	  -destination $(DESTINATION) \
	  -only-testing:swiftwingUITests \
	  -parallel-testing-enabled NO \
	  2>&1 | xcsift

update-spec:
	./Scripts/update-api-spec.sh

update-spec-force:
	./Scripts/update-api-spec.sh --force

format:
	swiftformat .

lint:
	swiftlint

status:
	ralph-tui status
