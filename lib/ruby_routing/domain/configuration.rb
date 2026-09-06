# frozen_string_literal: true

module RubyRouting
  # Raised when an application active configuration no longer describes the
  # Coordinator's provider catalog. Continuing with either side would create
  # a mixed routing generation and can make the durable history unrestorable.
  class ConfigurationDriftError < StandardError; end
end
