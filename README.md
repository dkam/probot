# Probot

OMG another Ruby Robot.txt parser? It was an accident, I didn't mean to make it and I shouldn't have but here we are. It started out tiny and grew. Yes I should have used one of the other gems.

Does this even deserve a gem? Feel free to just copy and paste the single file which implements this - one less dependency eh? 

On the plus side of this yak shaving, there are some nice features I don't think the others have.

1. Support for consecutive user agents making up a single record:

```txt
User-agent: first-agent
User-agent: second-agent
Disallow: /
```

This record blocks both first-agent and second-agent from the site.

2. It selects the most specific allow / disallow rule, using rule length as a proxy for specificity. You can also ask it to show you the matching rules and their scores. 

```ruby
txt = %Q{
User-agent: *
Disallow: /dir1
Allow: /dir1/dir2
Disallow: /dir1/dir2/dir3
}
Probot.new(txt).matches("/dir1/dir2/dir3")
=> {:disallowed=>{/\/dir1/=>5, /\/dir1\/dir2\/dir3/=>15}, :allowed=>{/\/dir1\/dir2/=>10}}
```

In this case, we can see the Disallow rule with length 15 would be followed.

3. It sets the User-Agent string when fetching robots.txt

## Installation

Install the gem and add to the application's Gemfile by executing:

    $ bundle add probot

If bundler is not being used to manage dependencies, install the gem by executing:

    $ gem install probot

## Usage

It's straightforward to use. Instantiate it if you'll make a few requests:

```ruby
> r = Probot.new('https://booko.info', agent: 'BookScraper')
> r.rules
=>  {"*"=>{"disallow"=>[/\/search/, /\/products\/search/, /\/.*\/refresh_prices/, /\/.*\/add_to_cart/, /\/.*\/get_prices/, /\/lists\/add/, /\/.*\/add$/, /\/api\//, /\/users\/bits/, /\/users\/create/, /\/prices\//, /\/widgets\/issue/], "allow"=>[], "crawl_delay"=>0, "crawl-delay"=>0.1},
 "YandexBot"=>{"disallow"=>[], "allow"=>[], "crawl_delay"=>0, "crawl-delay"=>300.0}}

> r.allowed?("/abc/refresh_prices")
=> false
> r.allowed?("https://booko.info/9780765397522/All-Systems-Red")
=> true
> r.allowed?("https://booko.info/9780765397522/refresh_prices")
=> false
```

Or just one-shot it for one-offs: 

```ruby
Probot.allowed?("https://booko.info/9780765397522/All-Systems-Red", agent: "BookScraper")
```


## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/Probot.

## Further Reading

*  https://moz.com/learn/seo/robotstxt
*  https://stackoverflow.com/questions/45293419/order-of-directives-in-robots-txt-do-they-overwrite-each-other-or-complement-ea
*  https://developers.google.com/search/docs/crawling-indexing/robots/robots_txt
*  https://developers.google.com/search/docs/crawling-indexing/robots/create-robots-txt

*  https://github.com/google/robotstxt  - Google's official parser


## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
