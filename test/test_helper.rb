# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "probot"
require "probot/version" # for testing the version number - otherwise the gemspec does it.

require "minitest/autorun"
