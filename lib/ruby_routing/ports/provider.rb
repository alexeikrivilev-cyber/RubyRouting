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

    # Provider-specific webhook adapters implement this boundary. Raw
    # transport fields never enter the lifecycle reducer directly.
    module ProviderNormalizer
      def normalize(_raw:, _provider_id:)
        raise NotImplementedError, "provider normalizer must implement #normalize"
      end
    end

    # Provider adapters must convert transport uncertainty into a
    # ProviderTransportResult or ProviderTransportError. The orchestrator only
    # handles that explicit transport contract; adapter programming/contract
    # errors are allowed to surface while the already-committed operation stays
    # resumable through its persisted identity and phase.
  end
end
