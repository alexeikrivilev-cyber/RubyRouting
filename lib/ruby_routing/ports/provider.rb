# frozen_string_literal: true

module RubyRouting
  module Ports
    module Provider
      def initiate(_request)
        raise NotImplementedError, "provider adapter must implement #initiate"
      end

      def resolve(_request)
        raise NotImplementedError, "provider adapter must implement #resolve"
      end
    end
  end
end
