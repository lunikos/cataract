CHPL      ?= chpl
CHPLCHECK ?= chplcheck
CLI_SRC   := src/cataract.chpl
CLI_MODS  := -M src/cli -M src/compiler
CLI_BIN   := bin/cataract
CHPLFLAGS ?= --fast

EXAMPLES  := blog api docs dashboard
EXAMPLE   ?= blog

.PHONY: all cli examples lint dev routes static clean distclean $(EXAMPLES)

all: cli

# The runtime is compiled into the application binary, not into the toolchain.
cli: $(CLI_BIN)

$(CLI_BIN): $(CLI_SRC) $(wildcard src/cli/*.chpl) $(wildcard src/compiler/*.chpl)
	@mkdir -p bin
	$(CHPL) --main-module CataractCLI $(CLI_MODS) $(CHPLFLAGS) $(CLI_SRC) -o $(CLI_BIN)

examples: $(EXAMPLES)

$(EXAMPLES): %: cli
	$(CLI_BIN) build --root examples/$@

run-%: %
	@name=$$(grep -m1 '^name' examples/$*/cataract.toml | cut -d'"' -f2); \
	./examples/$*/dist/$$name

# Rule selection and the 100-column limit live in .chplcheck.cfg.
lint:
	$(CHPLCHECK) $$(git ls-files '*.chpl')

dev: cli
	$(CLI_BIN) dev --root examples/$(EXAMPLE)

routes: cli
	$(CLI_BIN) routes --root examples/$(EXAMPLE)

static: cli
	$(CLI_BIN) build --root examples/$(EXAMPLE) --static

clean:
	rm -rf $(addsuffix /.cataract,$(addprefix examples/,$(EXAMPLES))) \
	       $(addsuffix /data,$(addprefix examples/,$(EXAMPLES))) \
	       $(addsuffix /dist,$(addprefix examples/,$(EXAMPLES)))

distclean: clean
	rm -rf bin
