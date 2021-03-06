ifndef CCPROOT
	export CCPROOT=$(GOPATH)/src/github.com/crunchydata/crunchy-containers
endif

# Default values if not already set
CCP_BASEOS ?= centos7
CCP_PG_VERSION ?= 12
CCP_PG_FULLVERSION ?= 12.1
CCP_PATRONI_VERSION ?= 1.6.3
CCP_BACKREST_VERSION ?= 2.18
CCP_VERSION ?= 4.2.0
CCP_PGAUDIT = "14_12" #no need to be env overridable given override logic below
CCP_POSTGIS_VERSION ?= 2.5

# Valid values: buildah (default), docker
IMGBUILDER ?= buildah
IMGCMDSTEM=sudo --preserve-env buildah bud --layers $(SQUASH)

# pgaudit compatibility is tied to PG version
ifeq ($(CCP_PGVERSION),9.5)
	CCP_PGAUDIT = "_95"
endif
ifeq ($(CCP_PGVERSION),9.6)
	CCP_PGAUDIT = "11_96"
endif
ifeq ($(CCP_PGVERSION),10)
	CCP_PGAUDIT = "12_10"
endif
ifeq ($(CCP_PGVERSION),11)
	CCP_PGAUDIT = "13_11"
endif
ifeq ($(CCP_PGVERSION),12)
	CCP_PGAUDIT = "14_12"
endif

# Allows simplification of IMGBUILDER switching
ifeq ("$(IMGBUILDER)","docker")
	IMGCMDSTEM=docker build
endif

.PHONY:	all extras pgimages

# Default target
all: cc-pg-base-image pgimages extras

# Build non-postgres images
extras: grafana prometheus scheduler

# Build images that use postgres - ordered for potential concurrent benefits
pgimages: postgres postgres-ha backup backrestrestore collect crunchyadm pgadmin4 pgbadger pgbasebackuprestore postgres-gis postgres-gis-ha pgbench pgbouncer pgdump pgpool pgrestore upgrade


#===========================================
# Targets generating commands
#===========================================

commands: pgc

pgc:
	cd $(CCPROOT)/commands/pgc && go build pgc.go && mv pgc $(GOBIN)/pgc
	cp $(GOBIN)/pgc bin/postgres


#===========================================
# Targets generating pg-based images
#===========================================

backrestrestore: backrest-restore-pgimg-$(IMGBUILDER)
backup:	backup-pgimg-$(IMGBUILDER)
collect: collect-pgimg-$(IMGBUILDER)
crunchyadm: admin-pgimg-$(IMGBUILDER)
pgadmin4: pgadmin4-pgimg-$(IMGBUILDER)
pgbadger: pgbadger-pgimg-$(IMGBUILDER)
pgbench: pgbench-pgimg-$(IMGBUILDER)
pgbouncer: pgbouncer-pgimg-$(IMGBUILDER)
pgdump: pgdump-pgimg-$(IMGBUILDER)
pgpool: pgpool-pgimg-$(IMGBUILDER)
pgrestore: pgrestore-pgimg-$(IMGBUILDER)
postgres: postgres-pgimg-$(IMGBUILDER)
postgres-ha: postgres-ha-pgimg-$(IMGBUILDER)
postgres-gis: postgres-gis-pgimg-$(IMGBUILDER)
postgres-gis-ha: postgres-gis-ha-pgimg-$(IMGBUILDER)

postgres-appdev: commands postgres-appdev-pgimg-$(IMGBUILDER)


#===========================================
# Targets generating non-pg-based images
#===========================================

grafana: grafana-img-$(IMGBUILDER)
pgbasebackuprestore: pgbasebackup-restore-img-$(IMGBUILDER)
prometheus: prometheus-img-$(IMGBUILDER)
scheduler: scheduler-img-$(IMGBUILDER)


#===========================================
# Pattern-based image generation targets
#===========================================

$(CCPROOT)/$(CCP_BASEOS)/Dockerfile.%.$(CCP_BASEOS):
	$(error No Dockerfile found for $* naming pattern: [$@])

# ----- Base Image -----
ccbase-image: ccbase-image-$(IMGBUILDER)

ccbase-image-build: $(CCPROOT)/$(CCP_BASEOS)/Dockerfile.base.$(CCP_BASEOS)
	$(IMGCMDSTEM) \
		-f $(CCPROOT)/$(CCP_BASEOS)/Dockerfile.base.$(CCP_BASEOS) \
		-t $(CCP_IMAGE_PREFIX)/crunchy-base:$(CCP_IMAGE_TAG) \
		--build-arg RELVER=$(CCP_VERSION) \
		$(CCPROOT)

ccbase-image-buildah: ccbase-image-build
	sudo --preserve-env buildah push $(CCP_IMAGE_PREFIX)/crunchy-base:$(CCP_IMAGE_TAG) docker-daemon:$(CCP_IMAGE_PREFIX)/crunchy-base:$(CCP_IMAGE_TAG)

ccbase-image-docker: ccbase-image-build

# ----- PG Base Image -----
cc-pg-base-image: cc-pg-base-image-$(IMGBUILDER)

cc-pg-base-image-build: ccbase-image $(CCPROOT)/$(CCP_BASEOS)/Dockerfile.pg-base.$(CCP_BASEOS)
	$(IMGCMDSTEM) \
		-f $(CCPROOT)/$(CCP_BASEOS)/Dockerfile.pg-base.$(CCP_BASEOS) \
		-t $(CCP_IMAGE_PREFIX)/crunchy-pg-base:$(CCP_IMAGE_TAG) \
		--build-arg BASEVER=$(CCP_VERSION) \
		--build-arg PG_FULL=$(CCP_PG_FULLVERSION) \
		--build-arg PG_LBL=$(subst .,,$(CCP_PGVERSION)) \
		--build-arg PG_MAJOR=$(CCP_PGVERSION) \
		--build-arg PREFIX=$(CCP_IMAGE_PREFIX) \
		$(CCPROOT)

cc-pg-base-image-buildah: cc-pg-base-image-build
	sudo --preserve-env buildah push $(CCP_IMAGE_PREFIX)/crunchy-pg-base:$(CCP_IMAGE_TAG) docker-daemon:$(CCP_IMAGE_PREFIX)/crunchy-pg-base:$(CCP_IMAGE_TAG)

cc-pg-base-image-docker: cc-pg-base-image-build

# ----- Special case pg-based image (postgres) -----
# Special case args: BACKREST_VER, PGAUDIT_LBL
postgres-pgimg-build: cc-pg-base-image commands $(CCPROOT)/$(CCP_BASEOS)/Dockerfile.postgres.$(CCP_BASEOS)
	$(IMGCMDSTEM) \
		-f $(CCPROOT)/$(CCP_BASEOS)/Dockerfile.postgres.$(CCP_BASEOS) \
		-t $(CCP_IMAGE_PREFIX)/crunchy-postgres:$(CCP_IMAGE_TAG) \
		--build-arg BASEVER=$(CCP_VERSION) \
		--build-arg PG_FULL=$(CCP_PG_FULLVERSION) \
		--build-arg PG_MAJOR=$(CCP_PGVERSION) \
		--build-arg PREFIX=$(CCP_IMAGE_PREFIX) \
		--build-arg BACKREST_VER=$(CCP_BACKREST_VERSION) \
		--build-arg PGAUDIT_LBL="$(CCP_PGAUDIT)" \
		$(CCPROOT)

postgres-pgimg-buildah: postgres-pgimg-build
	sudo --preserve-env buildah push $(CCP_IMAGE_PREFIX)/crunchy-postgres:$(CCP_IMAGE_TAG) docker-daemon:$(CCP_IMAGE_PREFIX)/crunchy-postgres:$(CCP_IMAGE_TAG)

postgres-pgimg-docker: postgres-pgimg-build

# ----- Special case pg-based image (postgres-gis) -----
# Special case args: POSTGIS_LBL
postgres-gis-pgimg-build: postgres commands $(CCPROOT)/$(CCP_BASEOS)/Dockerfile.postgres-gis.$(CCP_BASEOS)
	$(IMGCMDSTEM) \
		-f $(CCPROOT)/$(CCP_BASEOS)/Dockerfile.postgres-gis.$(CCP_BASEOS) \
		-t $(CCP_IMAGE_PREFIX)/crunchy-postgres-gis:$(CCP_IMAGE_TAG) \
		--build-arg BASEVER=$(CCP_VERSION) \
		--build-arg PG_FULL=$(CCP_PG_FULLVERSION) \
		--build-arg PG_MAJOR=$(CCP_PGVERSION) \
		--build-arg PREFIX=$(CCP_IMAGE_PREFIX) \
		--build-arg POSTGIS_LBL=$(subst .,,$(CCP_POSTGIS_VERSION)) \
		$(CCPROOT)

postgres-gis-pgimg-buildah: postgres-gis-pgimg-build
	sudo --preserve-env buildah push $(CCP_IMAGE_PREFIX)/crunchy-postgres-gis:$(CCP_IMAGE_TAG) docker-daemon:$(CCP_IMAGE_PREFIX)/crunchy-postgres-gis:$(CCP_IMAGE_TAG)

postgres-gis-pgimg-docker: postgres-gis-pgimg-build

# ----- Special case pg-based image (postgres-ha) -----
# Special case args: BACKREST_VER, PGAUDIT_LBL, PATRONI_VER
postgres-ha-pgimg-build: cc-pg-base-image commands $(CCPROOT)/$(CCP_BASEOS)/Dockerfile.postgres-ha.$(CCP_BASEOS)
	$(IMGCMDSTEM) \
		-f $(CCPROOT)/$(CCP_BASEOS)/Dockerfile.postgres-ha.$(CCP_BASEOS) \
		-t $(CCP_IMAGE_PREFIX)/crunchy-postgres-ha:$(CCP_IMAGE_TAG) \
		--build-arg BASEVER=$(CCP_VERSION) \
		--build-arg PG_FULL=$(CCP_PG_FULLVERSION) \
		--build-arg PG_MAJOR=$(CCP_PGVERSION) \
		--build-arg PREFIX=$(CCP_IMAGE_PREFIX) \
		--build-arg BACKREST_VER=$(CCP_BACKREST_VERSION) \
		--build-arg PGAUDIT_LBL="$(CCP_PGAUDIT)" \
	    --build-arg PATRONI_VER=$(CCP_PATRONI_VERSION) \
		$(CCPROOT)

postgres-ha-pgimg-buildah: postgres-ha-pgimg-build
	sudo --preserve-env buildah push $(CCP_IMAGE_PREFIX)/crunchy-postgres-ha:$(CCP_IMAGE_TAG) docker-daemon:$(CCP_IMAGE_PREFIX)/crunchy-postgres-ha:$(CCP_IMAGE_TAG)

postgres-ha-pgimg-docker: postgres-ha-pgimg-build

# ----- Special case pg-based image (postgres-gis-ha) -----
# Special case args: POSTGIS_LBL
postgres-gis-ha-pgimg-build: postgres-ha commands $(CCPROOT)/$(CCP_BASEOS)/Dockerfile.postgres-gis-ha.$(CCP_BASEOS)
	$(IMGCMDSTEM) \
		-f $(CCPROOT)/$(CCP_BASEOS)/Dockerfile.postgres-gis-ha.$(CCP_BASEOS) \
		-t $(CCP_IMAGE_PREFIX)/crunchy-postgres-gis-ha:$(CCP_IMAGE_TAG) \
		--build-arg BASEVER=$(CCP_VERSION) \
		--build-arg PG_FULL=$(CCP_PG_FULLVERSION) \
		--build-arg PG_MAJOR=$(CCP_PGVERSION) \
		--build-arg PREFIX=$(CCP_IMAGE_PREFIX) \
		--build-arg POSTGIS_LBL=$(subst .,,$(CCP_POSTGIS_VERSION)) \
		$(CCPROOT)

postgres-gis-ha-pgimg-buildah: postgres-gis-ha-pgimg-build
	sudo --preserve-env buildah push $(CCP_IMAGE_PREFIX)/crunchy-postgres-gis-ha:$(CCP_IMAGE_TAG) docker-daemon:$(CCP_IMAGE_PREFIX)/crunchy-postgres-gis-ha:$(CCP_IMAGE_TAG)

postgres-gis-ha-pgimg-docker: postgres-gis-ha-pgimg-build

# ----- Special case pg-based image (backrest-restore) -----
# Special case args: BACKREST_VER
backrest-restore-pgimg-build: cc-pg-base-image $(CCPROOT)/$(CCP_BASEOS)/Dockerfile.backrest-restore.$(CCP_BASEOS)
	$(IMGCMDSTEM) \
		-f $(CCPROOT)/$(CCP_BASEOS)/Dockerfile.backrest-restore.$(CCP_BASEOS) \
		-t $(CCP_IMAGE_PREFIX)/crunchy-backrest-restore:$(CCP_IMAGE_TAG) \
		--build-arg BASEVER=$(CCP_VERSION) \
		--build-arg PG_FULL=$(CCP_PG_FULLVERSION) \
		--build-arg PG_MAJOR=$(CCP_PGVERSION) \
		--build-arg PREFIX=$(CCP_IMAGE_PREFIX) \
		--build-arg BACKREST_VER=$(CCP_BACKREST_VERSION) \
		$(CCPROOT)

backrest-restore-pgimg-buildah: backrest-restore-pgimg-build
	sudo --preserve-env buildah push $(CCP_IMAGE_PREFIX)/crunchy-backrest-restore:$(CCP_IMAGE_TAG) docker-daemon:$(CCP_IMAGE_PREFIX)/crunchy-backrest-restore:$(CCP_IMAGE_TAG)

backrest-restore-pgimg-docker: backrest-restore-pgimg-build

# ----- All other pg-based images ----
%-pgimg-build: cc-pg-base-image $(CCPROOT)/$(CCP_BASEOS)/Dockerfile.%.$(CCP_BASEOS)
	$(IMGCMDSTEM) \
		-f $(CCPROOT)/$(CCP_BASEOS)/Dockerfile.$*.$(CCP_BASEOS) \
		-t $(CCP_IMAGE_PREFIX)/crunchy-$*:$(CCP_IMAGE_TAG) \
		--build-arg BASEVER=$(CCP_VERSION) \
		--build-arg PG_FULL=$(CCP_PG_FULLVERSION) \
		--build-arg PG_MAJOR=$(CCP_PGVERSION) \
		--build-arg PREFIX=$(CCP_IMAGE_PREFIX) \
		$(CCPROOT)

%-pgimg-buildah: %-pgimg-build
	sudo --preserve-env buildah push $(CCP_IMAGE_PREFIX)/crunchy-$*:$(CCP_IMAGE_TAG) docker-daemon:$(CCP_IMAGE_PREFIX)/crunchy-$*:$(CCP_IMAGE_TAG)

%-pgimg-docker: %-pgimg-build ;

# ----- Extra images -----
%-img-build: ccbase-image $(CCPROOT)/$(CCP_BASEOS)/Dockerfile.%.$(CCP_BASEOS)
	$(IMGCMDSTEM) \
		-f $(CCPROOT)/$(CCP_BASEOS)/Dockerfile.$*.$(CCP_BASEOS) \
		-t $(CCP_IMAGE_PREFIX)/crunchy-$*:$(CCP_IMAGE_TAG) \
		--build-arg BASEVER=$(CCP_VERSION) \
		--build-arg PG_FULL=$(CCP_PG_FULLVERSION) \
		--build-arg PG_MAJOR=$(CCP_PGVERSION) \
		--build-arg PREFIX=$(CCP_IMAGE_PREFIX) \
		$(CCPROOT)

%-img-buildah: %-img-build
	sudo --preserve-env buildah push $(CCP_IMAGE_PREFIX)/crunchy-$*:$(CCP_IMAGE_TAG) docker-daemon:$(CCP_IMAGE_PREFIX)/crunchy-$*:$(CCP_IMAGE_TAG)

%-img-docker: %-img-build ;

# ----- Upgrade Images -----
upgrade: upgrade-$(CCP_PGVERSION)

upgrade-%: upgrade-%-pgimg-$(IMGBUILDER) ;

upgrade-9.5: # Do nothing but log to avoid erroring out on missing Dockerfile
	$(info Upgrade build skipped for 9.5)

upgrade-%-pgimg-build: cc-pg-base-image $(CCPROOT)/$(CCP_BASEOS)/Dockerfile.upgrade-%.$(CCP_BASEOS)
	$(IMGCMDSTEM) \
		-f $(CCPROOT)/$(CCP_BASEOS)/Dockerfile.upgrade-$*.$(CCP_BASEOS) \
		-t $(CCP_IMAGE_PREFIX)/crunchy-upgrade:$(CCP_IMAGE_TAG) \
		--build-arg BASEVER=$(CCP_VERSION) \
		--build-arg PG_FULL=$(CCP_PG_FULLVERSION) \
		--build-arg PREFIX=$(CCP_IMAGE_PREFIX) \
		$(CCPROOT)

upgrade-%-pgimg-buildah: upgrade-%-pgimg-build
	sudo --preserve-env buildah push $(CCP_IMAGE_PREFIX)/crunchy-upgrade:$(CCP_IMAGE_TAG) docker-daemon:$(CCP_IMAGE_PREFIX)/crunchy-upgrade:$(CCP_IMAGE_TAG)

upgrade-%-pgimg-docker: upgrade-%-pgimg-build ;


#=================
# Utility targets
#=================
setup:
	$(CCPROOT)/bin/install-deps.sh

docbuild:
	cd $(CCPROOT) && ./generate-docs.sh

push:
	./bin/push-to-dockerhub.sh

-include Makefile.build
