# frozen_string_literal: true

require "test_helper"

# Ported from Google's robots.txt parser test suite, which pins down RFC 9309:
# https://github.com/google/robotstxt/blob/master/robots_test.cc
#
# Only the RFC cases (ID_*) and the URL-matching examples from Google's
# documentation are ported. Google-only behaviour (index.html as a directory,
# line length limits) is left out.
class TestGoogleConformance < Minitest::Test
  def allowed?(robotstxt, agent, url) = Probot.new(robotstxt, agent: agent).allowed?(url)

  def test_line_syntax_line
    correct = "user-agent: FooBot\ndisallow: /\n"
    incorrect = "foo: FooBot\nbar: /\n"
    incorrect_accepted = "user-agent FooBot\ndisallow /\n"
    url = "http://foo.bar/x/y"

    refute allowed?(correct, "FooBot", url)
    assert allowed?(incorrect, "FooBot", url)
    refute allowed?(incorrect_accepted, "FooBot", url)
  end

  def test_line_syntax_groups
    robotstxt = "allow: /foo/bar/\n\nuser-agent: FooBot\ndisallow: /\nallow: /x/\nuser-agent: BarBot\ndisallow: /\nallow: /y/\n\n\nallow: /w/\nuser-agent: BazBot\n\nuser-agent: FooBot\nallow: /z/\ndisallow: /\n"

    assert allowed?(robotstxt, "FooBot", "http://foo.bar/x/b")
    assert allowed?(robotstxt, "FooBot", "http://foo.bar/z/d")
    refute allowed?(robotstxt, "FooBot", "http://foo.bar/y/c")
    assert allowed?(robotstxt, "BarBot", "http://foo.bar/y/c")
    assert allowed?(robotstxt, "BarBot", "http://foo.bar/w/a")
    refute allowed?(robotstxt, "BarBot", "http://foo.bar/z/d")
    assert allowed?(robotstxt, "BazBot", "http://foo.bar/z/d")

    refute allowed?(robotstxt, "FooBot", "http://foo.bar/foo/bar/")
    refute allowed?(robotstxt, "BarBot", "http://foo.bar/foo/bar/")
    refute allowed?(robotstxt, "BazBot", "http://foo.bar/foo/bar/")
  end

  def test_line_syntax_groups_other_rules
    sitemap = "User-agent: BarBot\nSitemap: https://foo.bar/sitemap\nUser-agent: *\nDisallow: /\n"
    refute allowed?(sitemap, "FooBot", "http://foo.bar/")
    refute allowed?(sitemap, "BarBot", "http://foo.bar/")

    unknown = "User-agent: FooBot\nInvalid-Unknown-Line: unknown\nUser-agent: *\nDisallow: /\n"
    refute allowed?(unknown, "FooBot", "http://foo.bar/")
    refute allowed?(unknown, "BarBot", "http://foo.bar/")
  end

  def test_line_names_case_insensitive
    [
      "USER-AGENT: FooBot\nALLOW: /x/\nDISALLOW: /\n",
      "user-agent: FooBot\nallow: /x/\ndisallow: /\n",
      "uSeR-aGeNt: FooBot\nAlLoW: /x/\ndIsAlLoW: /\n"
    ].each do |robotstxt|
      assert allowed?(robotstxt, "FooBot", "http://foo.bar/x/y")
      refute allowed?(robotstxt, "FooBot", "http://foo.bar/a/b")
    end
  end

  def test_user_agent_value_case_insensitive
    [
      "User-Agent: FOO BAR\nAllow: /x/\nDisallow: /\n",
      "User-Agent: foo bar\nAllow: /x/\nDisallow: /\n",
      "User-Agent: FoO bAr\nAllow: /x/\nDisallow: /\n"
    ].each do |robotstxt|
      %w[Foo foo].each do |agent|
        assert allowed?(robotstxt, agent, "http://foo.bar/x/y")
        refute allowed?(robotstxt, agent, "http://foo.bar/a/b")
      end
    end
  end

  def test_user_agent_up_to_first_space
    robotstxt = "User-Agent: *\nDisallow: /\nUser-Agent: Foo Bar\nAllow: /x/\nDisallow: /\n"
    assert allowed?(robotstxt, "Foo", "http://foo.bar/x/y")
  end

  def test_global_groups_secondary
    global = "user-agent: *\nallow: /\nuser-agent: FooBot\ndisallow: /\n"
    only_specific = "user-agent: FooBot\nallow: /\nuser-agent: BarBot\ndisallow: /\nuser-agent: BazBot\ndisallow: /\n"
    url = "http://foo.bar/x/y"

    assert allowed?("", "FooBot", url)
    refute allowed?(global, "FooBot", url)
    assert allowed?(global, "BarBot", url)
    assert allowed?(only_specific, "QuxBot", url)
  end

  def test_allow_disallow_value_case_sensitive
    refute allowed?("user-agent: FooBot\ndisallow: /x/\n", "FooBot", "http://foo.bar/x/y")
    assert allowed?("user-agent: FooBot\ndisallow: /X/\n", "FooBot", "http://foo.bar/x/y")
  end

  def test_longest_match
    url = "http://foo.bar/x/page.html"

    refute allowed?("user-agent: FooBot\ndisallow: /x/page.html\nallow: /x/\n", "FooBot", url)

    robotstxt = "user-agent: FooBot\nallow: /x/page.html\ndisallow: /x/\n"
    assert allowed?(robotstxt, "FooBot", url)
    refute allowed?(robotstxt, "FooBot", "http://foo.bar/x/")

    assert allowed?("user-agent: FooBot\ndisallow: \nallow: \n", "FooBot", url)
    assert allowed?("user-agent: FooBot\ndisallow: /\nallow: /\n", "FooBot", url)

    robotstxt = "user-agent: FooBot\ndisallow: /x\nallow: /x/\n"
    refute allowed?(robotstxt, "FooBot", "http://foo.bar/x")
    assert allowed?(robotstxt, "FooBot", "http://foo.bar/x/")

    assert allowed?("user-agent: FooBot\ndisallow: /x/page.html\nallow: /x/page.html\n", "FooBot", url)

    robotstxt = "user-agent: FooBot\nallow: /page\ndisallow: /*.html\n"
    refute allowed?(robotstxt, "FooBot", "http://foo.bar/page.html")
    assert allowed?(robotstxt, "FooBot", "http://foo.bar/page")

    robotstxt = "user-agent: FooBot\nallow: /x/page.\ndisallow: /*.html\n"
    assert allowed?(robotstxt, "FooBot", url)
    refute allowed?(robotstxt, "FooBot", "http://foo.bar/x/y.html")

    robotstxt = "User-agent: *\nDisallow: /x/\nUser-agent: FooBot\nDisallow: /y/\n"
    assert allowed?(robotstxt, "FooBot", "http://foo.bar/x/page")
    refute allowed?(robotstxt, "FooBot", "http://foo.bar/y/page")
  end

  def test_encoding
    robotstxt = "User-agent: FooBot\nDisallow: /\nAllow: /foo/bar?qux=taz&baz=http://foo.bar?tar&par\n"
    assert allowed?(robotstxt, "FooBot", "http://foo.bar/foo/bar?qux=taz&baz=http://foo.bar?tar&par")

    robotstxt = "User-agent: FooBot\nDisallow: /\nAllow: /foo/bar/ツ\n"
    assert allowed?(robotstxt, "FooBot", "http://foo.bar/foo/bar/%E3%83%84")
    refute allowed?(robotstxt, "FooBot", "http://foo.bar/foo/bar/ツ")

    robotstxt = "User-agent: FooBot\nDisallow: /\nAllow: /foo/bar/%E3%83%84\n"
    assert allowed?(robotstxt, "FooBot", "http://foo.bar/foo/bar/%E3%83%84")
    refute allowed?(robotstxt, "FooBot", "http://foo.bar/foo/bar/ツ")

    robotstxt = "User-agent: FooBot\nDisallow: /\nAllow: /foo/bar/%62%61%7A\n"
    refute allowed?(robotstxt, "FooBot", "http://foo.bar/foo/bar/baz")
    assert allowed?(robotstxt, "FooBot", "http://foo.bar/foo/bar/%62%61%7A")
  end

  def test_special_characters
    robotstxt = "User-agent: FooBot\nDisallow: /foo/bar/quz\nAllow: /foo/*/qux\n"
    refute allowed?(robotstxt, "FooBot", "http://foo.bar/foo/bar/quz")
    assert allowed?(robotstxt, "FooBot", "http://foo.bar/foo/quz")
    assert allowed?(robotstxt, "FooBot", "http://foo.bar/foo//quz")
    assert allowed?(robotstxt, "FooBot", "http://foo.bar/foo/bax/quz")

    robotstxt = "User-agent: FooBot\nDisallow: /foo/bar$\nAllow: /foo/bar/qux\n"
    refute allowed?(robotstxt, "FooBot", "http://foo.bar/foo/bar")
    assert allowed?(robotstxt, "FooBot", "http://foo.bar/foo/bar/qux")
    assert allowed?(robotstxt, "FooBot", "http://foo.bar/foo/bar/")
    assert allowed?(robotstxt, "FooBot", "http://foo.bar/foo/bar/baz")

    robotstxt = "User-agent: FooBot\n# Disallow: /\nDisallow: /foo/quz#qux\nAllow: /\n"
    assert allowed?(robotstxt, "FooBot", "http://foo.bar/foo/bar")
    refute allowed?(robotstxt, "FooBot", "http://foo.bar/foo/quz")
  end

  def test_documentation_checks
    robotstxt = "user-agent: FooBot\ndisallow: /\nallow: /fish\n"
    refute allowed?(robotstxt, "FooBot", "http://foo.bar/bar")
    %w[/fish /fish.html /fish/salmon.html /fishheads /fishheads/yummy.html /fish.html?id=anything].each do |path|
      assert allowed?(robotstxt, "FooBot", "http://foo.bar#{path}"), path
    end
    %w[/Fish.asp /catfish /?id=fish].each do |path|
      refute allowed?(robotstxt, "FooBot", "http://foo.bar#{path}"), path
    end

    robotstxt = "user-agent: FooBot\ndisallow: /\nallow: /fish*\n"
    refute allowed?(robotstxt, "FooBot", "http://foo.bar/bar")
    %w[/fish /fish.html /fish/salmon.html /fishheads /fishheads/yummy.html /fish.html?id=anything].each do |path|
      assert allowed?(robotstxt, "FooBot", "http://foo.bar#{path}"), path
    end
    %w[/Fish.bar /catfish /?id=fish].each do |path|
      refute allowed?(robotstxt, "FooBot", "http://foo.bar#{path}"), path
    end

    robotstxt = "user-agent: FooBot\ndisallow: /\nallow: /fish/\n"
    refute allowed?(robotstxt, "FooBot", "http://foo.bar/bar")
    %w[/fish/ /fish/salmon /fish/?salmon /fish/salmon.html /fish/?id=anything].each do |path|
      assert allowed?(robotstxt, "FooBot", "http://foo.bar#{path}"), path
    end
    %w[/fish /fish.html /Fish/Salmon.html].each do |path|
      refute allowed?(robotstxt, "FooBot", "http://foo.bar#{path}"), path
    end

    robotstxt = "user-agent: FooBot\ndisallow: /\nallow: /*.php\n"
    refute allowed?(robotstxt, "FooBot", "http://foo.bar/bar")
    %w[/filename.php /folder/filename.php /folder/filename.php?parameters //folder/any.php.file.html /filename.php/ /index?f=filename.php/].each do |path|
      assert allowed?(robotstxt, "FooBot", "http://foo.bar#{path}"), path
    end
    %w[/php/ /index?php /windows.PHP].each do |path|
      refute allowed?(robotstxt, "FooBot", "http://foo.bar#{path}"), path
    end

    robotstxt = "user-agent: FooBot\ndisallow: /\nallow: /*.php$\n"
    refute allowed?(robotstxt, "FooBot", "http://foo.bar/bar")
    %w[/filename.php /folder/filename.php].each do |path|
      assert allowed?(robotstxt, "FooBot", "http://foo.bar#{path}"), path
    end
    %w[/filename.php?parameters /filename.php/ /filename.php5 /php/ /filename?php /aaaphpaaa //windows.PHP].each do |path|
      refute allowed?(robotstxt, "FooBot", "http://foo.bar#{path}"), path
    end

    robotstxt = "user-agent: FooBot\ndisallow: /\nallow: /fish*.php\n"
    refute allowed?(robotstxt, "FooBot", "http://foo.bar/bar")
    assert allowed?(robotstxt, "FooBot", "http://foo.bar/fish.php")
    assert allowed?(robotstxt, "FooBot", "http://foo.bar/fishheads/catfish.php?parameters")
    refute allowed?(robotstxt, "FooBot", "http://foo.bar/Fish.PHP")

    assert allowed?("user-agent: FooBot\nallow: /p\ndisallow: /\n", "FooBot", "http://example.com/page")
    assert allowed?("user-agent: FooBot\nallow: /folder\ndisallow: /folder\n", "FooBot", "http://example.com/folder/page")
    refute allowed?("user-agent: FooBot\nallow: /page\ndisallow: /*.htm\n", "FooBot", "http://example.com/page.htm")

    robotstxt = "user-agent: FooBot\nallow: /$\ndisallow: /\n"
    assert allowed?(robotstxt, "FooBot", "http://example.com/")
    refute allowed?(robotstxt, "FooBot", "http://example.com/page.html")
  end

  def test_utf8_byte_order_mark_is_skipped
    ["\xEF\xBB\xBF", "\xEF\xBB", "\xEF"].each do |bom|
      robotstxt = "#{bom}User-Agent: foo\nDisallow: /AnyValue\n".b
      refute allowed?(robotstxt, "foo", "http://foo.bar/AnyValue"), bom.inspect
    end

    # A BOM in the middle of the file is garbage, not a BOM.
    robotstxt = "User-Agent: foo\n\xEF\xBB\xBFDisallow: /AnyValue\n".b
    assert allowed?(robotstxt, "foo", "http://foo.bar/AnyValue")
  end

  def test_path_params_query
    {
      "http://www.example.com" => "/",
      "http://www.example.com/" => "/",
      "http://www.example.com/a" => "/a",
      "http://www.example.com/a/" => "/a/",
      "http://www.example.com/a/b?c=http://d.e/" => "/a/b?c=http://d.e/",
      "http://www.example.com/a/b?c=d&e=f#fragment" => "/a/b?c=d&e=f",
      "http://www.example.com/a;b#c" => "/a;b",
      "/a" => "/a"
    }.each do |url, path|
      assert_equal path, Probot.path(url), url
    end
  end

  def test_escape_pattern
    assert_equal "http://www.example.com", Probot.escape("http://www.example.com")
    assert_equal "/a/b/c", Probot.escape("/a/b/c")
    assert_equal "%C3%A1", Probot.escape("á")
    assert_equal "%AA", Probot.escape("%aa")
  end

  # Rules are anchored at the start of the path, not matched anywhere in it.
  def test_rules_match_from_the_start_of_the_path
    assert allowed?("User-agent: *\nDisallow: /ab\n", "FooBot", "http://foo.bar/x/ab")
    assert allowed?("User-agent: *\nDisallow: /ab\n", "FooBot", "/x/ab")
  end

  # The rule that decided a URL keeps its line, so callers can point at it.
  def test_decisive_rule
    robotstxt = "User-agent: *\n\n# Tracking links\nDisallow: /*?utm_\n"
    rule = Probot.new(robotstxt, agent: "Twitterbot").decisive_rule("https://example.com/notes/a?utm_source=x")

    assert_equal [4, "Disallow: /*?utm_", ["*"]], [rule.line, rule.to_s, rule.agents]
  end
end
