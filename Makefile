PROJECT = teacup_nats
PROJECT_VERSION = $(shell head -n 1 relx.config | awk '{split($$0, a, "\""); print a[2]}')

app:: rebar.config

DEPS = lager jsx teacup

dep_lager = git https://github.com/erlang-lager/lager 3.9.1
dep_jsx = git https://github.com/talentdeficit/jsx.git v3.1.0
dep_teacup = git https://github.com/yuce/teacup.git 2ab8a3c

include erlang.mk

ERLC_COMPILE_OPTS= +'{parse_transform, lager_transform}'
ERLC_OPTS += $(ERLC_COMPILE_OPTS)
TEST_ERLC_OPTS += $(ERLC_COMPILE_OPTS)