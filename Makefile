#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

#
# Copyright (c) 2019, Joyent, Inc.
#

#
# Files
#
JS_FILES := $(shell find {bin,lib,tests} -name '*.js')
ESLINT_FILES := $(JS_FILES)

# Should be the same version as the platform's /usr/node/bin/node.
NODE_PREBUILT_TAG =	gz
NODE_PREBUILT_VERSION =	v6.15.1
ifeq ($(shell uname -s),SunOS)
	# Allow building on a SmartOS image other than sdc-smartos/1.6.3.
	NODE_PREBUILT_IMAGE =	18b094b0-eb01-11e5-80c1-175dac7ddf02
endif

# Included definitions
ENGBLD_REQUIRE := $(shell git submodule update --init deps/eng)
include ./deps/eng/tools/mk/Makefile.defs
TOP ?= $(error Unable to access eng.git submodule Makefiles.)

ifeq ($(shell uname -s),SunOS)
	include ./deps/eng/tools/mk/Makefile.node_prebuilt.defs
else
	NPM=npm
	NODE=node
	NPM_EXEC=$(shell which npm)
	NODE_EXEC=$(shell which node)
endif
include ./deps/eng/tools/mk/Makefile.smf.defs

NAME :=			vm-agent
RELEASE_TARBALL :=	$(NAME)-$(STAMP).tgz
RELEASE_MANIFEST :=	$(NAME)-$(STAMP).manifest
RELSTAGEDIR :=		/tmp/$(NAME)-$(STAMP)

#
# Due to the unfortunate nature of npm, the Node Package Manager, there appears
# to be no way to assemble our dependencies without running the lifecycle
# scripts.  These lifecycle scripts should not be run except in the context of
# an agent installation or uninstallation, so we provide a magic environment
# varible to disable them here.
#
NPM_ENV =		SDC_AGENT_SKIP_LIFECYCLE=yes
RUN_NPM_INSTALL =	$(NPM_ENV) $(NPM) install

#
# Repo-specific targets
#
.PHONY: all
all: $(SMF_MANIFESTS) | $(NPM_EXEC) $(REPO_DEPS)
	$(RUN_NPM_INSTALL)
	$(NODE) ./node_modules/.bin/kthxbai || true # work around trentm/node-kthxbai#1
	$(NODE) ./node_modules/.bin/kthxbai

.PHONY: test
test:
	true

.PHONY: release
release: all deps docs $(SMF_MANIFESTS)
	@echo "Building $(RELEASE_TARBALL)"
	@mkdir -p $(RELSTAGEDIR)/$(NAME)
	(git symbolic-ref HEAD | awk -F/ '{print $$3}' && git describe) \
	    >$(TOP)/describe
	cp -r \
	$(TOP)/bin \
	$(TOP)/describe \
	$(TOP)/lib \
	$(TOP)/Makefile \
	$(TOP)/node_modules \
	$(TOP)/package.json \
	$(TOP)/runtests \
	$(TOP)/tests \
	$(TOP)/sapi_manifests \
	$(TOP)/smf \
	$(TOP)/npm \
	$(RELSTAGEDIR)/$(NAME)
	rm -rf $(RELSTAGEDIR)/$(NAME)/node_modules/eslint \
	    $(RELSTAGEDIR)/$(NAME)/node_modules/.bin/eslint
	rm -rf $(RELSTAGEDIR)/$(NAME)/node_modules/kthxbai \
	    $(RELSTAGEDIR)/$(NAME)/node_modules/.bin/kthxbai
	uuid -v4 > $(RELSTAGEDIR)/$(NAME)/image_uuid
	mkdir -p $(RELSTAGEDIR)/$(NAME)/node
	cp -PR $(NODE_INSTALL)/* $(RELSTAGEDIR)/$(NAME)/node/
	rm -rf $(RELSTAGEDIR)/$(NAME)/node/bin/npm \
	    $(RELSTAGEDIR)/$(NAME)/node/include \
	    $(RELSTAGEDIR)/$(NAME)/node/lib/node_modules \
	    $(RELSTAGEDIR)/$(NAME)/node/share
	cd $(RELSTAGEDIR) && $(TAR) -I pigz -cf $(TOP)/$(RELEASE_TARBALL) *
	cat $(TOP)/manifest.tmpl | sed \
	    -e "s/UUID/$$(cat $(RELSTAGEDIR)/$(NAME)/image_uuid)/" \
	    -e "s/NAME/$$(json name < $(TOP)/package.json)/" \
	    -e "s/VERSION/$$(json version < $(TOP)/package.json)/" \
	    -e "s/DESCRIPTION/$$(json description < $(TOP)/package.json)/" \
	    -e "s/BUILDSTAMP/$(STAMP)/" \
	    -e "s/SIZE/$$(stat --printf="%s" $(TOP)/$(RELEASE_TARBALL))/" \
	    -e "s/SHA/$$(openssl sha1 $(TOP)/$(RELEASE_TARBALL) \
	    | cut -d ' ' -f2)/" \
	    >$(TOP)/$(RELEASE_MANIFEST)
	@rm -rf $(RELSTAGEDIR)

.PHONY: publish
publish: release
	@if [[ -z "$(ENGBLD_BITS_DIR)" ]]; then \
	    @echo "error: 'ENGBLD_BITS_DIR' must be set for 'publish' target"; \
	    exit 1; \
	fi
	mkdir -p $(ENGBLD_BITS_DIR)/$(NAME)
	cp $(TOP)/$(RELEASE_TARBALL) $(ENGBLD_BITS_DIR)/$(NAME)/$(RELEASE_TARBALL)
	cp $(TOP)/$(RELEASE_MANIFEST) $(ENGBLD_BITS_DIR)/$(NAME)/$(RELEASE_MANIFEST)

.PHONY: dumpvar
dumpvar:
	@if [[ -z "$(VAR)" ]]; then \
	    echo "error: set 'VAR' to dump a var"; \
	    exit 1; \
	fi
	@echo "$(VAR) is '$($(VAR))'"

# Here "cutting a release" is just tagging the current commit with
# "v(package.json version)". We don't publish this to npm.
.PHONY: cutarelease
cutarelease:
	@echo "# Ensure working copy is clean."
	[[ -z `git status --short` ]]  # If this fails, the working dir is dirty.
	@echo "# Ensure have 'json' tool."
	which json 2>/dev/null 1>/dev/null
	ver=$(shell cat package.json | json version) && \
	    git tag "v$$ver" && \
	    git push origin "v$$ver"

include ./deps/eng/tools/mk/Makefile.deps
ifeq ($(shell uname -s),SunOS)
    include ./deps/eng/tools/mk/Makefile.node_prebuilt.targ
endif
include ./deps/eng/tools/mk/Makefile.smf.targ
include ./deps/eng/tools/mk/Makefile.targ
