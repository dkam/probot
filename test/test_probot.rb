# frozen_string_literal: true

require "test_helper"

class TestProbot < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::Probot::VERSION
  end

  TEST_CASES = [
    {
      txt: %(
      User-Agent: *
      Disallow : /admin/
      Disallow : /cart/
      Disallow : /client/
      Sitemap: http://www.allenandunwin.com/sitemap.xml

      User-Agent: FooBot
      Disallow: /private/
      Allow: /cart/

      User-Agent: BlahBot
      User-Agent: YadaBot
      Disallow: /noblah/
      Allow: /cart/
      ),
      sitemaps: ["http://www.allenandunwin.com/sitemap.xml"],
      found_agents: ["*", "FooBot", "BlahBot", "YadaBot"],
      tests: [
        {
          agent: "*",
          allowed: ["/books/9781760878854", "/books/9781760878861", "/books/9781760878878"],
          disallowed: ["/admin/", "/cart/", "/client/"],
          crawl_delay: 0
        }
      ]
    }, {
      txt: %(
      User-agent: *
      Disallow: /?*\t\t\t#comment
      Disallow: /home/
      Disallow: /dashboard
      Disallow: /terms-conditions
      Disallow: /privacy-policy
      Disallow: /index.php
      Disallow: /chargify_system
      Disallow: /test*
      Disallow: /team*     # comment
      Disallow: /index
      Allow: /    # comment
      Sitemap: http://example.com/sitemap.xml
      ),
      sitemaps: ["http://example.com/sitemap.xml"],
      found_agents: ["*"],
      tests: [
        {
          agent: "*",
          allowed: ["/home", "/books/9781760878878", "/client/"],
          disallowed: ["/home/", "/dashboard", "/test/hello", "/team/", "/team/1", "/teamtest"],
          crawl_delay: 0
        },
        {
          agent: "UnfoundAgent",
          allowed: ["/home", "/books/9781760878878", "/client/"],
          disallowed: ["/home/", "/dashboard", "/test/hello", "/team/", "/team/1", "/teamtest"],
          crawl_delay: 0
        }
      ]
    },
    # These tests from https://github.com/rinzi/robotstxt
    {
      txt: %(User-agent: rubytest
      Disallow: /no-dir/
      Disallow: /no-page.php
      Disallow: /*-no-dir/
      Disallow: /dir/*.php
      Disallow: *?var
      Disallow: /dir/*?var

      # this is a test
      useragent: *
      disalow: /test/

      sitemap: /sitemapxml.xml

      ),
      sitemaps: ["/sitemapxml.xml"],
      found_agents: ["*", "rubytest"],
      tests: [
        {
          agent: "rubytest",
          allowed: ["/", "/blog/", "/blog/page.php"],
          disallowed: ["/no-dir/", "/foo-no-dir/", "/foo-no-dir/page.html", "/dir/page.php", "/page.php?var=0", "/dir/page.php?var=0", "/blog/page.php?var=0"],
          crawl_delay: 0
        }
      ]
    },
    {
      txt: %("User-agent: *\nDisallow: /wp/wp-admin/\nAllow: /wp/wp-admin/admin-ajax.php\n\nUser-agent: *\nDisallow: /wp-content/uploads/wpo/wpo-plugins-tables-list.json\n\n# START YOAST BLOCK\n# ---------------------------\nUser-agent: *\nDisallow:\n\nSitemap: https://prhinternationalsales.com/sitemap_index.xml\n# ---------------------------\n# END YOAST BLOCK"),
      sitemaps: ["https://prhinternationalsales.com/sitemap_index.xml"],
      found_agents: ["*"],
      tests: [
        {
          agent: "*",
          allowed: ["/wp/wp-admin/admin-ajax.php"],
          disallowed: ["/wp/wp-admin/", "/wp-content/uploads/wpo/wpo-plugins-tables-list.json"],
          crawl_delay: 0
        }
      ]
    }
  ].freeze

  def test_some_tests
    TEST_CASES.each_with_index do |test_case, ind|
      r = Probot.new(test_case[:txt])

      assert_equal test_case[:found_agents], r.found_agents, "found_agents for test #{ind}"
      assert_equal test_case[:sitemaps], r.sitemaps, "sitemap for test #{ind}"

      test_case[:tests].each do |tst|
        r = Probot.new(test_case[:txt], agent: tst[:agent])

        tst[:allowed].each do |url|
          assert r.allowed?(url), "expected #{url} to be allowed, for agent #{tst[:agent]} | test #{ind}"
        end

        tst[:disallowed].each do |url|
          assert r.disallowed?(url), "expected #{url} to be disallowed, for agent #{tst[:agent]} | test #{ind}"
        end
      end
    end
  end

  # https://developers.google.com/search/docs/crawling-indexing/robots/robots_txt#url-matching-based-on-path-values
  def test_googles_tests
    assert Probot.new(%(allow: /p\ndisallow: /)).matching_rule("https://example.com/page") == {allow: /\/p/}
    assert Probot.new(%(allow: /folder\ndisallow: /folder)).matching_rule("https://example.com/folder/page") == {allow: /\/folder/}
    assert Probot.new(%(allow: /page\ndisallow: /*.htm)).matching_rule("https://example.com/page.htm") == {disallow: /\/.*\.htm/}
    assert Probot.new(%(allow: /page\ndisallow: /*.ph)).matching_rule("https://example.com/page.php5") == {disallow: /\/.*\.ph/}  # FAIL
    assert Probot.new(%(allow: /$\ndisallow: /)).matching_rule("https://example.com/") == {allow: /\/$/}
    assert Probot.new(%(allow: /$\ndisallow: /)).matching_rule("https://example.com/page.htm") == {disallow: /\//}
  end

  def test_empty_allow_disallow
    assert Probot.new(%(User-agent: *\nAllow:)).rules.dig("*", "allow").empty?
    assert Probot.new(%(User-agent: *\nDisallow:)).rules.dig("*", "disallow").empty?
    assert Probot.new(%(User-agent: *\nDisallow:\n\n)).rules.dig("*", "disallow").empty?
  end

  def test_consecutive_user_agents
    txt = %(User-agent: Curl
             User-agent: Wget
             Disallow: /url)
    r = Probot.new(txt)
    assert r.allowed?("/url") == true

    r.agent = "Curl"
    assert r.allowed?("/url") == false

    r.agent = "Wget"
    assert r.allowed?("/url") == false

    r.agent = "Other"
    assert r.allowed?("/url") == true
  end

  def test_unfound_robots
    r = Probot.new("")
    assert r.allowed?("/url") == true
    r.agent = "Curl"
    assert r.allowed?("/url") == true
  end

  def test_more_other_tests
    txt = %(User-agent: rubytest\nDisallow: /no-dir/\nDisallow: /no-page.php\nDisallow: /*-no-dir/\nDisallow: /dir/*.php\nDisallow: *?var\nDisallow: /dir/*?var\n\n# this is a test\nuseragent: *\ndisalow: /test/\n\nsitemap: /sitemapxml.xml\n\n )

    r = Probot.new(txt, agent: "rubytest")
    assert r.allowed?("/dir/page.php") == false
    assert r.allowed?("/dir/home.php") == false
    assert r.allowed?("/dir/page") == true
    assert r.allowed?("/dir/page?var") == false
  end

  def test_multiple_sitemaps
    txt = %(User-agent: *\nSitemap: https://example.com/sitemapxml.xml\nSitemap: https://example.com/sitemapxml2.xml\n\n)
    r = Probot.new(txt)
    assert_equal 2, r.sitemaps.length
    assert r.sitemaps.include?("https://example.com/sitemapxml.xml")
    assert r.sitemaps.include?("https://example.com/sitemapxml2.xml")
  end

  # Sitemaps should be absolute URLs, but we'll accept relative URLs and make them absolute.
  # However, we need to test both scenarios - when we know the site, and when we don't because we're parsing a robots.txt file.
  # This test is a little gross, reaching into the guts of the class, but it's the easiest way to test this.
  def test_absolute_sitemaps
    txt = %(User-agent: *\nSitemap: /sitemapxml.xml\nSitemap: /sitemapxml2.xml\n\n)

    r = Probot.new(txt)
    assert_equal 2, r.sitemaps.length
    assert r.sitemaps.include?("/sitemapxml.xml"), "expected /sitemapxml.xml, got #{r.sitemaps}"
    assert r.sitemaps.include?("/sitemapxml2.xml"), "expected /sitemapxml2.xml, got #{r.sitemaps}"

    # We have to manually set the site, as we're not parsing a URL - then we need to reset the sitemaps array and reparse the doc. Gross.
    r = Probot.new(txt)
    r.site = URI("https://example.com")
    r.sitemaps = []
    r.parse(r.doc)

    assert_equal 2, r.sitemaps.length
    assert r.sitemaps.include?("https://example.com/sitemapxml.xml"), "expected https://example.com/sitemapxml.xml, got #{r.sitemaps}"
    assert r.sitemaps.include?("https://example.com/sitemapxml2.xml"), "expected https://example.com/sitemapxml2.xml, got #{r.sitemaps}"
  end
end
