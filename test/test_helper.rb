# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "minitest/autorun"
require "ruby_routing"
require "timeout"
require_relative "support/controlled_clock"
require_relative "support/simulator/scripted_provider"
require_relative "support/simulator/normalizer"
require_relative "support/synchronization"
require_relative "support/acceptance_evidence"
