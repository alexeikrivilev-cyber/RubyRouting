# frozen_string_literal: true

module RubyRouting
  # Current version of the bounded offline Case product surface. Keep report,
  # demo and judge evidence metadata on this one authority.
  module Case
    VERSION = "0.4.4".freeze
  end
end

require_relative "case/errors"
require_relative "case/calendar"
require_relative "case/input"
require_relative "case/state"
require_relative "case/traffic"
require_relative "case/factors"
require_relative "case/configuration"
require_relative "case/router"
require_relative "case/report"
require_relative "case/release"
require_relative "case/runner"
require_relative "case/semantic_validator"
require_relative "case/validator"

module RubyRouting
  # Bounded offline competition engine for the authoritative Hack.Genesis
  # dataset. This namespace is intentionally separate from the production
  # execution kernel: simulated expiry is not a production UNKNOWN mapping.
  module Case
  end
end
