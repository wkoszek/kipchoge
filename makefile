all:
	bundle exec ./kipchoge.rb
alld:
	bundle exec ./kipchoge.rb -d
install:
	bundle install --path vendor/bundle
clean:
	rm -rf .byebug_history
