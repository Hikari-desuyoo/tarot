push: build
	@gem push ./tarot.gem

install: build
	@gem install ./tarot.gem

build:
	@gem build tarot.gemspec -o tarot.gem
