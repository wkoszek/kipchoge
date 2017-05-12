all:
	bundle exec ./kipchoge.rb
install:
	bundle install --path vendor/bundle
clean:
	rm -rf .byebug_history
