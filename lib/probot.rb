# frozen_string_literal: true

require_relative "Probot/version"

require "uri"
require "net/http"

# https://moz.com/learn/seo/robotstxt
# https://stackoverflow.com/questions/45293419/order-of-directives-in-robots-txt-do-they-overwrite-each-other-or-complement-ea
# https://developers.google.com/search/docs/crawling-indexing/robots/create-robots-txt
# https://developers.google.com/search/docs/crawling-indexing/robots/robots_txt
#
# https://github.com/google/robotstxt  - Google's official parser

# Note: User-agent found on consecutive lines are considered to be part of the same record.
# Note: Google ignores crawl_delay
# Note: Google does not consider crawl_delay or sitemap to be part of the per-agent records.

# Two main parts of this class:
#   Parse a robots.txt file
#   Find the most specific rule for a given URL. We use the length of the regexp as a proxy for specificity.

class Robots
  attr_reader :rules, :sitemap, :doc
  attr_accessor :agent

  def initialize(data, agent: "*")
    raise ArgumentError, "The first argument must be a string" unless data.is_a?(String)
    @agent = agent

    @rules = {}
    @current_agents = ["*"]
    @current_agents.each { |agent| @rules[agent] ||= {"disallow" => [], "allow" => [], "crawl_delay" => 0} }
    @sitemaps = []

    @doc = data.start_with?("http") ? fetch_robots_txt(data) : data
    parse(@doc)
  end

  def request_headers = (agent == "*") ? {} : {"User-Agent" => @agent}

  def fetch_robots_txt(url)
    Net::HTTP.get(URI(url).tap { |u| u.path = "/robots.txt" }, request_headers)
  rescue
    ""
  end

  def crawl_delay = rules.dig(@agent, "crawl_delay")

  def found_agents = rules.keys

  def disallowed = rules.dig(@agent, "disallow") || rules.dig("*", "disallow")

  def allowed = rules.dig(@agent, "allow") || rules.dig("*", "allow")

  def disallowed_matches(url) = disallowed.select { |disallowed_url| url.match?(disallowed_url) }.to_h { |rule| [rule, pattern_length(rule)] }

  def allowed_matches(url) = allowed.select { |allowed_url| url.match?(allowed_url) }.to_h { |rule| [rule, pattern_length(rule)] }

  def matches(url) = {disallowed: disallowed_matches(url), allowed: allowed_matches(url)}

  def disallowed_best(url) = disallowed_matches(url).max_by { |k, v| v }

  def allowed_best(url) = allowed_matches(url).max_by { |k, v| v }

  def matching_rule(url) = (disallowed_best(url)&.last.to_i > allowed_best(url)&.last.to_i) ? {disallow: disallowed_best(url)&.first} : {allow: allowed_best(url)&.first}

  # If a URL is not disallowed, it is allowed - so we check if it is explictly disallowed and if not, it's allowed.
  def allowed?(url) = !disallowed?(url)

  def disallowed?(url) = matching_rule(url)&.keys&.first == :disallow

  def parse(doc)
    # We need to handle consective user-agent lines, which are considered to be part of the same record.
    subsequent_agent = false

    doc.lines.each do |line|
      next if line.start_with?("#") || !line.include?(":") || line.split(":").length < 2

      data = ParsedLine.new(line)

      if data.agent?
        if subsequent_agent
          @current_agents << data.value
        else
          @current_agents = [data.value]
          subsequent_agent = true
        end

        @current_agents.each { |agent| rules[agent] ||= {"disallow" => [], "allow" => [], "crawl_delay" => 0} }
        next
      end

      # All Regex characters are escaped, then we unescape * and $ as they may used in robots.txt

      if data.allow? || data.disallow?
        @current_agents.each { |agent| rules[agent][data.key] << Regexp.new(Regexp.escape(data.value).gsub('\*', ".*").gsub('\$', "$")) }

        subsequent_agent = false # When user-agent strings are found on consecutive lines, they are considered to be part of the same record. Google ignores crawl_delay.
        next
      end

      if data.crawl_delay?
        @current_agents.each { |agent| rules[agent][data.key] = data.value }
        next
      end

      if data.sitemap?
        @sitemap = URI(data.value).path
        next
      end

      @current_agents.each { |agent| rules[agent][data.key] = data.value }
    end
  end

  def pattern_length(regexp) = regexp.source.gsub(/(\\[\*\$\.])/, "*").length

  # ParedLine Note: In the case of 'Sitemap: https://example.com/sitemap.xml', raw_value needs to rejoin after splitting the URL.

  ParsedLine = Struct.new(:input_string) do
    def key = input_string.split(":").first&.strip&.downcase

    def raw_value = input_string.split(":").slice(1..)&.join(":")&.strip

    def clean_value = raw_value.split("#").first&.strip

    def agent? = key == "user-agent"

    def disallow? = key == "disallow"

    def allow? = key == "allow"

    def crawl_delay? = key == "crawl-delay"

    def sitemap? = key == "sitemap"

    def value
      return clean_value.to_f if crawl_delay?
      return URI(clean_value).to_s if disallow? || allow?

      raw_value
    rescue URI::InvalidURIError
      raw_value
    end
  end

  def self.allowed?(url, agent: "*") = Robots.new(url, agent: agent).allowed?(url)
end

# Robots.allowed?("https://booko.info/9780765397522/All-Systems-Red")
# => true
# r = Robots.new('https://booko.info', agent: 'YandexBot')
# r = Robots.new('https://www.allenandunwin.com')
# $ Robots.new('https://www.amazon.com/').matches("/gp/wishlist/ipad-install/gcrnsts")
# => {:disallowed=>{/\/wishlist\//=>10, /\/gp\/wishlist\//=>13, /.*\/gcrnsts/=>10}, :allowed=>{/\/gp\/wishlist\/ipad\-install.*/=>28}}
#
# Test with
# assert Robots.new(nil, doc: %Q{allow: /$\ndisallow: /}).matching_rule('https://example.com/page.htm') == {disallow: /\//}
