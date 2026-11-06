# frozen_string_literal: true

require "uri"
require "net/http"
require_relative "probot/version"

# https://www.rfc-editor.org/rfc/rfc9309.html - the Robots Exclusion Protocol
# https://moz.com/learn/seo/robotstxt
# https://stackoverflow.com/questions/45293419/order-of-directives-in-robots-txt-do-they-overwrite-each-other-or-complement-ea
# https://developers.google.com/search/docs/crawling-indexing/robots/create-robots-txt
# https://developers.google.com/search/docs/crawling-indexing/robots/robots_txt
#
# https://github.com/google/robotstxt  - Google's official parser. test/test_google_conformance.rb
# ports its RFC test cases.

# Note: User-agent found on consecutive lines are considered to be part of the same record.
# Note: Google ignores crawl_delay
# Note: Google does not consider crawl_delay or sitemap to be part of the per-agent records.

# Two main parts of this class:
#   Parse a robots.txt file
#   Find the most specific rule for a given URL. The rule with the longest pattern wins, and Allow wins a tie.

class Probot
  # A single Allow or Disallow line. It's a Regexp anchored to the start of the
  # path, so it works anywhere the old bare Regexp rules did, and it remembers
  # where it came from so callers can point at the line that decided a URL.
  class Rule < Regexp
    attr_reader :directive, :value, :line, :agents

    def initialize(value, directive:, line: nil, agents: [])
      @directive = directive
      @value = value
      @line = line
      @agents = agents
      super(self.class.pattern(value))
    end

    def allow? = directive == "allow"

    def disallow? = directive == "disallow"

    # Specificity is the length of the pattern in octets (RFC 9309 2.2.2).
    def length = Probot.escape(value).bytesize

    def to_s = "#{directive.capitalize}: #{value}"

    # `*` matches any run of characters. `$` anchors the end, but only as the
    # last character; anywhere else it's literal.
    def self.pattern(value)
      escaped = Probot.escape(value)
      anchored = escaped.end_with?("$")
      escaped = escaped.delete_suffix("$") if anchored
      source = escaped.split("*", -1).map { Regexp.escape(_1) }.join(".*")
      "\\A#{source}#{"\\z" if anchored}"
    end
  end

  # Typos Google accepts for directive names, so a misspelled line still means what it was meant to.
  KEY_ALIASES = {
    "useragent" => "user-agent", "user agent" => "user-agent",
    "dissallow" => "disallow", "dissalow" => "disallow", "disalow" => "disallow",
    "diasllow" => "disallow", "disallaw" => "disallow"
  }.freeze

  # Full or partial UTF-8 byte order mark at the very start of the file.
  BOM = /\A(?:\xEF\xBB\xBF|\xEF\xBB|\xEF)/n

  attr_reader :rules, :doc
  attr_accessor :agent, :sitemaps, :site

  def initialize(data, agent: "*")
    raise ArgumentError, "The first argument must be a string" unless data.is_a?(String)
    @agent = agent

    @rules = {}
    @current_agents = ["*"]
    @current_agents.each { |agent| @rules[agent] ||= {"disallow" => [], "allow" => [], "crawl_delay" => 0} }
    @sitemaps = []

    @site = URI(data) if data.start_with?("http")
    @doc = @site.nil? ? data : fetch_robots_txt(@site)
    parse(@doc)
  end

  def request_headers = (agent == "*") ? {} : {"User-Agent" => @agent}

  def fetch_robots_txt(url)
    Net::HTTP.get(URI(url).tap { |u| u.path = "/robots.txt" }, request_headers)
  rescue
    ""
  end

  def crawl_delay = agent_rules&.dig("crawl_delay")

  def found_agents = rules.keys

  def disallowed = agent_rules&.dig("disallow") || rules.dig("*", "disallow")

  def allowed = agent_rules&.dig("allow") || rules.dig("*", "allow")

  def disallowed_matches(url) = disallowed.select { |rule| rule.match?(self.class.path(url)) }.to_h { |rule| [rule, pattern_length(rule)] }

  def allowed_matches(url) = allowed.select { |rule| rule.match?(self.class.path(url)) }.to_h { |rule| [rule, pattern_length(rule)] }

  def matches(url) = {disallowed: disallowed_matches(url), allowed: allowed_matches(url)}

  def disallowed_best(url) = disallowed_matches(url).max_by { |k, v| v }

  def allowed_best(url) = allowed_matches(url).max_by { |k, v| v }

  def matching_rule(url) = (disallowed_best(url)&.last.to_i > allowed_best(url)&.last.to_i) ? {disallow: disallowed_best(url)&.first} : {allow: allowed_best(url)&.first}

  # The Rule that decides the URL for this agent, or nil when no rule matches (which means allowed).
  def decisive_rule(url) = matching_rule(url).values.first

  # If a URL is not disallowed, it is allowed - so we check if it is explictly disallowed and if not, it's allowed.
  def allowed?(url) = !disallowed?(url)

  def disallowed?(url) = matching_rule(url)&.keys&.first == :disallow

  def parse(doc)
    # We need to handle consective user-agent lines, which are considered to be part of the same record.
    subsequent_agent = false

    doc = doc.b.sub(BOM, "").force_encoding(Encoding::UTF_8).scrub

    doc.each_line.with_index(1) do |line, number|
      data = ParsedLine.new(line)
      next if data.key.nil? || data.raw_value.nil?

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

      if data.allow? || data.disallow?
        unless data.value.empty?
          rule = Rule.new(data.value, directive: data.key, line: number, agents: @current_agents.dup)
          @current_agents.each { |agent| rules[agent][data.key] << rule }
        end

        # When user-agent strings are found on consecutive lines, they are considered to be part of the same record. Google ignores crawl_delay.
        subsequent_agent = false
        next
      end

      if data.crawl_delay?
        @current_agents.each { |agent| rules[agent][data.key] = data.value }
        next
      end

      # Ensure we have an absolute URL
      if data.sitemap?
        sitemap_uri = URI(data.raw_value)
        sitemap_uri = sitemap_uri.host.nil? ? URI.join(*[site, sitemap_uri].compact) : sitemap_uri
        @sitemaps << sitemap_uri.to_s
        @sitemaps.uniq!
        next
      end

      @current_agents.each { |agent| rules[agent][data.key] = data.value }
    end
  end

  def pattern_length(rule) = rule.length

  # The rules for this agent, merged across every group naming it. Agents match on
  # their product token, case-insensitively: "Twitterbot/1.0" obeys a group for
  # "twitterbot". Nil when no group names the agent, so the "*" group applies.
  def agent_rules
    return rules["*"] if agent == "*"

    token = self.class.product_token(agent)
    groups = rules.select { |name, _| name != "*" && self.class.product_token(name) == token }.values
    return if token.nil? || groups.empty?

    groups.each_with_object({"disallow" => [], "allow" => [], "crawl_delay" => 0}) do |group, merged|
      merged["disallow"] |= group["disallow"]
      merged["allow"] |= group["allow"]
      merged["crawl_delay"] = group["crawl_delay"] if group["crawl_delay"].to_f.positive?
    end
  end

  # The leading run of [a-zA-Z_-] characters, downcased (RFC 9309 2.2.1).
  def self.product_token(agent) = agent.to_s[/\A[a-zA-Z_-]+/]&.downcase

  # What rules are matched against: the path, params and query of a URL, without the fragment.
  # Paths are passed through as given.
  def self.path(url)
    return url unless url.match?(%r{\A[a-z][a-z0-9+.-]*://}i)

    uri = URI(url)
    path = uri.path.to_s.empty? ? "/" : uri.path
    uri.query ? "#{path}?#{uri.query}" : path
  rescue URI::InvalidURIError
    # Unencoded URLs (a raw "ツ") still have a path; take everything after the authority.
    path = url.sub(%r{\A[a-z][a-z0-9+.-]*://[^/?#]*}i, "").sub(/#.*/m, "")
    path.start_with?("/") ? path : "/#{path}"
  end

  # Percent-encode octets outside US-ASCII and normalize existing escapes to upper case.
  def self.escape(value)
    value.b.gsub(/[^\x00-\x7F]/n) { |byte| format("%%%02X", byte.ord) }
      .gsub(/%[0-9a-fA-F]{2}/, &:upcase)
      .force_encoding(Encoding::UTF_8)
  end

  # ParsedLine Note: In the case of 'Sitemap: https://example.com/sitemap.xml', raw_value needs to rejoin after splitting the URL.

  ParsedLine = Struct.new(:input_string) do
    # Comments run from # to the end of the line, wherever they start.
    def content = input_string.sub(/#.*/m, "").strip

    # "key: value", or "key value" for a line missing its colon.
    def parts
      @parts ||= if content.include?(":")
        content.split(":", 2).map(&:strip)
      else
        content.split(/\s+/, 2)
      end
    end

    def key
      key = parts.first&.downcase
      KEY_ALIASES.fetch(key, key)
    end

    def raw_value = (parts.length == 2) ? parts.last : nil

    def clean_value = raw_value

    def agent? = key == "user-agent"

    def disallow? = key == "disallow"

    def allow? = key == "allow"

    def crawl_delay? = key == "crawl-delay"

    def sitemap? = key == "sitemap"

    def value
      return clean_value.to_f if crawl_delay?

      raw_value
    end
  end

  def self.allowed?(url, agent: "*") = Probot.new(url, agent: agent).allowed?(url)
end
