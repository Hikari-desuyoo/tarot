install: build
	@gem install ./tarot.gem

build:
	@gem build tarot.gemspec -o tarot.gem
