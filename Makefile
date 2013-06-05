# Set default locations for runtime and deployment
# if the directories are not already set:
DEPLOY_RUNTIME ?= /kb/runtime
TARGET         ?= /kb/deployment
# Include standard makefile
TOP_DIR = ../..
include $(TOP_DIR)/tools/Makefile.common

SRC_PERL = $(wildcard scripts/*.pl)
BIN_PERL = $(addprefix $(BIN_DIR)/,$(basename $(notdir $(SRC_PERL))))
KB_PERL  = $(addprefix $(TARGET)/bin/,$(basename $(notdir $(SRC_PERL))))

# SERVER_SPEC   : workspaceService.spec
# SERVER_MODULE : workspaceService
# SERVICE       : workspaceService
# SERVICE_PORT  : 7058 
# PSGI_PATH     : lib/workspaceService.psgi

# workspaceService
SERV_SERVER_SPEC 	= workspaceService.spec
SERV_SERVER_MODULE 	= workspaceService
SERV_SERVICE 		= workspaceService
SERV_PSGI_PATH 		= lib/workspaceService.psgi
SERV_SERVICE_PORT 	= 7058
SERV_SERVICE_DIR = $(TARGET)/services/$(SERV_SERVICE)
SERV_TPAGE = $(KB_RUNTIME)/bin/perl $(KB_RUNTIME)/bin/tpage
SERV_TPAGE_ARGS = --define kb_top=$(TARGET) --define kb_runtime=$(KB_RUNTIME) --define kb_service_name=$(SERV_SERVICE) \
	--define kb_service_port=$(SERV_SERVICE_PORT) --define kb_service_psgi=$(SERV_PSGI_PATH)

all: bin compile-typespec

bin: $(BIN_PERL)

$(BIN_DIR)/%: scripts/%.pl 
	$(TOOLS_DIR)/wrap_perl '$$KB_TOP/modules/$(CURRENT_DIR)/$<' $@

CLIENT_TESTS = $(wildcard client-tests/*.t)
SCRIPT_TESTS = $(wildcard script-tests/*.sh)
SERVER_TESTS = $(wildcard server-tests/*.t)

test: test-service test-client test-scripts
	@echo "running server, script and client tests"

test-service:
	for t in $(SERVER_TESTS) ; do \
		if [ -f $$t ] ; then \
			$(DEPLOY_RUNTIME)/bin/prove $$t ; \
			if [ $$? -ne 0 ] ; then \
				exit 1 ; \
			fi \
		fi \
	done

test-scripts:
	for t in $(SCRIPT_TESTS) ; do \
		if [ -f $$t ] ; then \
			/bin/sh $$t ; \
			if [ $$? -ne 0 ] ; then \
				exit 1 ; \
			fi \
		fi \
	done

test-client:
	for t in $(CLIENT_TESTS) ; do \
		if [ -f $$t ] ; then \
			$(DEPLOY_RUNTIME)/bin/prove $$t ; \
			if [ $$? -ne 0 ] ; then \
				exit 1 ; \
			fi \
		fi \
	done

deploy: deploy-client deploy-service
deploy-all: deploy-client deploy-service

deploy-service: deploy-dir deploy-libs deploy-scripts deploy-services deploy-cfg
deploy-client: install-client-libs deploy-dir deploy-libs deploy-scripts deploy-docs


install-client-libs:
	perl ./Build.PL ;\
	./Build installdeps --cpan_client `which cpanm` --install_path lib=$(KB_PERL_PATH);

deploy-dir:
	if [ ! -d $(SERV_SERVICE_DIR) ] ; then mkdir -p $(SERV_SERVICE_DIR) ; fi
	if [ ! -d $(SERV_SERVICE_DIR)/webroot ] ; then mkdir -p $(SERV_SERVICE_DIR)/webroot ; fi

#deploy-scripts:
#	export KB_TOP=$(TARGET); \
#	export KB_RUNTIME=$(KB_RUNTIME); \
#	export KB_PERL_PATH=$(TARGET)/lib bash ; \
#	for src in $(SRC_PERL) ; do \
#		basefile=`basename $$src`; \
#		base=`basename $$src .pl`; \
#		echo install $$src $$base ; \
#		cp $$src $(TARGET)/plbin ; \
#		bash $(TOOLS_DIR)/wrap_perl.sh "$(TARGET)/plbin/$$basefile" $(TARGET)/bin/$$base ; \
#	done 

deploy-libs: compile-typespec
	rsync -arv lib/. $(TARGET)/lib/.

deploy-services: deploy-basic-service

deploy-basic-service:
	tpage $(SERV_TPAGE_ARGS) service/start_service.tt > $(TARGET)/services/$(SERV_SERVICE)/start_service; \
	chmod +x $(TARGET)/services/$(SERV_SERVICE)/start_service; \
	tpage $(SERV_TPAGE_ARGS) service/stop_service.tt > $(TARGET)/services/$(SERV_SERVICE)/stop_service; \
	chmod +x $(TARGET)/services/$(SERV_SERVICE)/stop_service; \
	tpage $(SERV_TPAGE_ARGS) service/process.tt > $(TARGET)/services/$(SERV_SERVICE)/process.$(SERV_SERVICE); \
	chmod +x $(TARGET)/services/$(SERV_SERVICE)/process.$(SERV_SERVICE); 

deploy-docs:
	if [ ! -d docs ] ; then mkdir -p docs ; fi
	$(KB_RUNTIME)/bin/pod2html -t "workspaceService" lib/Bio/KBase/workspaceService/Client.pm > docs/workspaceService.html
	cp docs/*html $(SERV_SERVICE_DIR)/webroot/.

compile-typespec:
	mkdir -p lib/biokbase/workspaceService
	touch lib/biokbase/__init__.py
	touch lib/biokbase/workspaceService/__init__.py
	mkdir -p lib/javascript/workspaceService
	compile_typespec \
	-impl Bio::KBase::workspaceService::Impl \
	-service Bio::KBase::workspaceService::Server \
	-psgi workspaceService.psgi \
	-client Bio::KBase::workspaceService::Client \
	-js javascript/workspaceService/Client \
	-py biokbase/workspaceService/client \
	workspaceService.spec lib
	rm -f lib/workspaceServiceImpl.py
	rm -f lib/workspaceServiceServer.py
	rm -rf Bio

include $(TOP_DIR)/tools/Makefile.common.rules

