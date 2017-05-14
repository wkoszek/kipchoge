all:
	bundle exec ./kipchoge.rb
allm:
	bundle exec ./kipchoge.rb -m
alld:
	bundle exec ./kipchoge.rb -d
install:
	bundle install --path vendor/bundle
clean:
	rm -rf .byebug_history
