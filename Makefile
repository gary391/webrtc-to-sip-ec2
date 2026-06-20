SHELL := /usr/bin/env bash

.PHONY: validate-env detect-ec2-env native-install native-configure native-configure-mariadb native-configure-rtpengine native-configure-kamailio native-configure-nginx native-render-client native-start native-stop native-restart native-status healthcheck collect-debug sip-trace rtp-trace test validate-cloudformation deploy-readiness clean-local-generated

validate-env:
	@ENV_FILE="$${ENV_FILE:-.env}" ./deploy/common/validate-env.sh

native-render-client: validate-env
	@ENV_FILE="$${ENV_FILE:-.env}" ./deploy/native/render-client-config.sh

detect-ec2-env:
	@OUTPUT_FILE="$${OUTPUT_FILE:-/opt/webrtc-to-sip/aws-instance.env}" ./deploy/common/detect-ec2-env.sh

native-install: validate-env
	@ENV_FILE="$${ENV_FILE:-.env}" ./deploy/native/install.sh

native-configure-rtpengine: validate-env
	@ENV_FILE="$${ENV_FILE:-.env}" ./deploy/native/configure-rtpengine.sh

native-configure-mariadb: validate-env
	@ENV_FILE="$${ENV_FILE:-.env}" ./deploy/native/configure-mariadb.sh

native-configure-kamailio: validate-env
	@ENV_FILE="$${ENV_FILE:-.env}" ./deploy/native/configure-kamailio.sh

native-configure-nginx: validate-env
	@ENV_FILE="$${ENV_FILE:-.env}" ./deploy/native/configure-nginx.sh

native-configure: validate-env
	@ENV_FILE="$${ENV_FILE:-.env}" ./deploy/native/configure.sh

native-start: validate-env
	@ENV_FILE="$${ENV_FILE:-.env}" ./deploy/native/start-services.sh

native-stop:
	@./deploy/native/stop-services.sh

native-restart: native-stop native-start

native-status:
	@./deploy/native/status.sh

healthcheck: validate-env
	@ENV_FILE="$${ENV_FILE:-.env}" ./deploy/debug/healthcheck.sh

collect-debug:
	@./deploy/debug/collect-debug.sh

sip-trace:
	@./deploy/debug/sip-trace.sh

rtp-trace:
	@ENV_FILE="$${ENV_FILE:-.env}" ./deploy/debug/rtp-trace.sh

validate-cloudformation:
	@./tests/test-cloudformation.sh

deploy-readiness:
	@./scripts/check-deploy-readiness.sh

test: validate-cloudformation
	@./tests/test-env-and-render.sh
	@./tests/test-detect-ec2-env.sh
	@./tests/test-rtpengine-release.sh
	@./tests/test-native-installer.sh
	@./tests/test-rtpengine-config.sh
	@./tests/test-mariadb-config.sh
	@./tests/test-github-workflow.sh
	@./tests/test-kamailio-config.sh
	@./tests/test-nginx-config.sh
	@./tests/test-operations.sh
	@./tests/test-required-files.sh

clean-local-generated:
	rm -rf generated
